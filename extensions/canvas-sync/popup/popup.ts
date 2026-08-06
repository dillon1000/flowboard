import { canonicalHTTPSOrigin, originPattern } from '../src/origins';
import { popupErrorMessage } from '../src/popup-errors';
import { readConfiguration, saveConfiguration } from '../src/storage';
import type { ExtensionMessage, PopupState, SyncResult } from '../src/types';

const form = document.querySelector<HTMLFormElement>('#configuration-form')!;
const canvasOriginInput = document.querySelector<HTMLInputElement>('#canvas-origin')!;
const focalpointOriginInput = document.querySelector<HTMLInputElement>('#focalpoint-origin')!;
const syncKeyInput = document.querySelector<HTMLInputElement>('#sync-key')!;
const saveButton = document.querySelector<HTMLButtonElement>('#save-button')!;
const syncButton = document.querySelector<HTMLButtonElement>('#sync-button')!;
const status = document.querySelector<HTMLElement>('#status')!;
const error = document.querySelector<HTMLElement>('#error')!;

function showError(message: string): void {
  error.textContent = message;
  error.hidden = false;
}

function clearError(): void {
  error.textContent = '';
  error.hidden = true;
}

function showResult(result: SyncResult | null): void {
  if (!result) {
    status.textContent = 'No sync attempt yet.';
    return;
  }
  status.textContent = `${result.message} ${new Date(result.attemptedAt).toLocaleString()}`;
  if (!result.ok) showError(popupErrorMessage(result.code === 'OK' ? 'RESPONSE_INVALID' : result.code, result.message));
}

async function loadState(): Promise<void> {
  const response = await chrome.runtime.sendMessage({ type: 'getPopupState' } satisfies ExtensionMessage) as { state: PopupState };
  const configuration = response.state.configuration;
  if (configuration) {
    canvasOriginInput.value = configuration.canvasOrigin;
    focalpointOriginInput.value = configuration.focalpointOrigin;
    syncKeyInput.value = configuration.syncKey;
  }
  showResult(response.state.lastResult);
  syncButton.disabled = configuration === null;
}

form.addEventListener('submit', (event) => {
  event.preventDefault();
  clearError();
  saveButton.disabled = true;
  void (async () => {
    try {
      const previous = await readConfiguration();
      const canvasOrigin = canonicalHTTPSOrigin(canvasOriginInput.value);
      const focalpointOrigin = canonicalHTTPSOrigin(focalpointOriginInput.value);
      if (!/^fcs_[a-f0-9]{64}$/.test(syncKeyInput.value.trim())) {
        throw new Error('Enter the complete fcs_ Canvas sync key.');
      }
      const requestedOrigins = [...new Set([originPattern(canvasOrigin), originPattern(focalpointOrigin)])];
      const granted = await chrome.permissions.request({ origins: requestedOrigins });
      if (!granted) throw new Error('Chrome did not grant access to both configured origins.');
      await saveConfiguration({ canvasOrigin, focalpointOrigin, syncKey: syncKeyInput.value });
      await chrome.runtime.sendMessage({ type: 'configurationChanged' } satisfies ExtensionMessage);
      if (previous) {
        const oldOrigins = [originPattern(previous.canvasOrigin), originPattern(previous.focalpointOrigin)]
          .filter((origin) => !requestedOrigins.includes(origin));
        if (oldOrigins.length) await chrome.permissions.remove({ origins: oldOrigins });
      }
      status.textContent = 'Configuration saved. Open the configured Canvas site to sync.';
      syncButton.disabled = false;
    } catch (cause) {
      showError(cause instanceof Error ? cause.message : 'The configuration could not be saved.');
    } finally {
      saveButton.disabled = false;
    }
  })();
});

syncButton.addEventListener('click', () => {
  clearError();
  syncButton.disabled = true;
  status.textContent = 'Reading a complete Canvas snapshot…';
  void chrome.runtime.sendMessage({ type: 'syncNow' } satisfies ExtensionMessage)
    .then((response: { result: SyncResult }) => showResult(response.result))
    .catch(() => showError('The extension service worker is unavailable. Reopen the popup and try again.'))
    .finally(() => { syncButton.disabled = false; });
});

void loadState().catch(() => showError('The extension configuration could not be loaded.'));
