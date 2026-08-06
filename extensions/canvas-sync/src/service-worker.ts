import { errorResult, SyncError } from './errors';
import { originPattern } from './origins';
import {
  readConfiguration,
  readLastAutomaticAttempt,
  readLastResult,
  saveLastAutomaticAttempt,
  saveLastResult
} from './storage';
import type { CanvasSyncSnapshotV1, ExtensionMessage, PopupState, SyncResult } from './types';

const contentScriptID = 'focalpoint-canvas-sync';
const automaticDebounceMilliseconds = 60_000;
let inFlight = false;

async function registerConfiguredContentScript(): Promise<void> {
  const registered = await chrome.scripting.getRegisteredContentScripts({ ids: [contentScriptID] });
  if (registered.length > 0) await chrome.scripting.unregisterContentScripts({ ids: [contentScriptID] });
  const configuration = await readConfiguration();
  if (!configuration) return;
  await chrome.scripting.registerContentScripts([{
    id: contentScriptID,
    matches: [originPattern(configuration.canvasOrigin)],
    js: ['content-script.js'],
    runAt: 'document_idle',
    allFrames: false,
    persistAcrossSessions: true
  }]);
}

async function activeCanvasTabID(canvasOrigin: string): Promise<number> {
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  const tab = tabs[0];
  if (!tab?.id || !tab.url || new URL(tab.url).origin !== canvasOrigin) {
    throw new SyncError('CURRENT_TAB_MISMATCH', 'The current tab is not the configured Canvas site.');
  }
  return tab.id;
}

async function collectFromTab(tabID: number, canvasOrigin: string): Promise<CanvasSyncSnapshotV1> {
  let response: { snapshot?: CanvasSyncSnapshotV1; error?: { code: SyncResult['code']; message: string } };
  try {
    response = await chrome.tabs.sendMessage(tabID, { type: 'collectCanvasSnapshot', canvasOrigin } satisfies ExtensionMessage);
  } catch {
    // A newly saved registration does not enter a Canvas tab that was already
    // open. Inject it once so the manual button works without a page reload.
    try {
      await chrome.scripting.executeScript({ target: { tabId: tabID }, files: ['content-script.js'] });
      response = await chrome.tabs.sendMessage(tabID, { type: 'collectCanvasSnapshot', canvasOrigin } satisfies ExtensionMessage);
    } catch {
      throw new SyncError('CANVAS_REQUEST_FAILED', 'Reload the signed-in Canvas page, then try again.');
    }
  }
  if (response.error) throw new SyncError(response.error.code === 'OK' ? 'RESPONSE_INVALID' : response.error.code, response.error.message);
  if (!response.snapshot) throw new SyncError('RESPONSE_INVALID', 'Canvas did not return a complete snapshot.');
  return response.snapshot;
}

async function sendSnapshot(snapshot: CanvasSyncSnapshotV1, focalpointOrigin: string, syncKey: string): Promise<{ duplicate: boolean }> {
  let response: Response;
  try {
    response = await fetch(new URL('/api/v1/integrations/canvas/sync', focalpointOrigin), {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${syncKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(snapshot)
    });
  } catch {
    throw new SyncError('FOCALPOINT_UNAVAILABLE', 'The Focalpoint origin is unavailable.');
  }
  if (response.status === 401 || response.status === 403) {
    throw new SyncError('SYNC_KEY_INVALID', 'The Focalpoint Canvas sync key is invalid.');
  }
  if (!response.ok) {
    throw new SyncError('FOCALPOINT_REJECTED', `Focalpoint rejected the complete snapshot with HTTP ${response.status}.`);
  }
  let body: { duplicate?: unknown };
  try {
    body = await response.json() as { duplicate?: unknown };
  } catch {
    throw new SyncError('FOCALPOINT_REJECTED', 'Focalpoint returned an invalid sync response.');
  }
  return { duplicate: body.duplicate === true };
}

/** Owns the cross-origin send and the global lock for one complete sync attempt. */
async function runSync(tabID: number | undefined, manual: boolean): Promise<SyncResult> {
  const attemptedAt = new Date().toISOString();
  if (inFlight) {
    return { ok: false, code: 'SYNC_ACTIVE', message: 'A Canvas sync is already active.', attemptedAt };
  }
  const configuration = await readConfiguration();
  if (!configuration) {
    return { ok: false, code: 'NOT_CONFIGURED', message: 'Configure the Canvas and Focalpoint origins first.', attemptedAt };
  }
  if (!manual) {
    const now = Date.now();
    const lastAttempt = await readLastAutomaticAttempt();
    if (now - lastAttempt < automaticDebounceMilliseconds) {
      return { ok: true, code: 'OK', message: 'The recent page-load sync attempt is still within the 60-second debounce.', attemptedAt };
    }
    await saveLastAutomaticAttempt(now);
  }

  inFlight = true;
  let result: SyncResult;
  try {
    const resolvedTabID = tabID ?? await activeCanvasTabID(configuration.canvasOrigin);
    const snapshot = await collectFromTab(resolvedTabID, configuration.canvasOrigin);
    const response = await sendSnapshot(snapshot, configuration.focalpointOrigin, configuration.syncKey);
    result = {
      ok: true,
      code: 'OK',
      message: response.duplicate ? 'This Canvas snapshot was already imported.' : 'Canvas sync completed.',
      attemptedAt,
      snapshotID: snapshot.snapshotID,
      duplicate: response.duplicate
    };
  } catch (cause) {
    const failure = errorResult(cause);
    result = { ok: false, ...failure, attemptedAt };
  } finally {
    inFlight = false;
  }
  await saveLastResult(result);
  return result;
}

chrome.runtime.onInstalled.addListener(() => void registerConfiguredContentScript());
chrome.runtime.onStartup.addListener(() => void registerConfiguredContentScript());

chrome.runtime.onMessage.addListener((message: ExtensionMessage, sender, sendResponse) => {
  if (message.type === 'canvasPageReady') {
    if (sender.tab?.id !== undefined) void runSync(sender.tab.id, false);
    return false;
  }
  if (message.type === 'configurationChanged') {
    void registerConfiguredContentScript()
      .then(() => sendResponse({ ok: true }))
      .catch((cause: unknown) => sendResponse({ error: errorResult(cause) }));
    return true;
  }
  if (message.type === 'syncNow') {
    void runSync(undefined, true).then((result) => sendResponse({ result }));
    return true;
  }
  if (message.type === 'getPopupState') {
    void Promise.all([readConfiguration(), readLastResult()])
      .then(([configuration, lastResult]) => sendResponse({ state: { configuration, lastResult } satisfies PopupState }));
    return true;
  }
  return false;
});

void registerConfiguredContentScript();
