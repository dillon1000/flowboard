import { canonicalHTTPSOrigin } from './origins';
import type { CanvasSyncConfiguration, SyncResult } from './types';

const configurationKey = 'canvasSyncConfiguration';
const lastResultKey = 'canvasSyncLastResult';
const lastAutomaticAttemptKey = 'canvasSyncLastAutomaticAttempt';

export async function readConfiguration(): Promise<CanvasSyncConfiguration | null> {
  const stored = await chrome.storage.local.get(configurationKey);
  const value = stored[configurationKey] as Partial<CanvasSyncConfiguration> | undefined;
  if (!value?.canvasOrigin || !value.focalpointOrigin || !value.syncKey) return null;
  try {
    return {
      canvasOrigin: canonicalHTTPSOrigin(value.canvasOrigin),
      focalpointOrigin: canonicalHTTPSOrigin(value.focalpointOrigin),
      syncKey: value.syncKey
    };
  } catch {
    return null;
  }
}

export async function saveConfiguration(configuration: CanvasSyncConfiguration): Promise<CanvasSyncConfiguration> {
  const canonical = {
    canvasOrigin: canonicalHTTPSOrigin(configuration.canvasOrigin),
    focalpointOrigin: canonicalHTTPSOrigin(configuration.focalpointOrigin),
    syncKey: configuration.syncKey.trim()
  };
  if (!/^fcs_[a-f0-9]{64}$/.test(canonical.syncKey)) {
    throw new Error('Enter the complete fcs_ Canvas sync key.');
  }
  await chrome.storage.local.set({ [configurationKey]: canonical });
  return canonical;
}

export async function readLastResult(): Promise<SyncResult | null> {
  const stored = await chrome.storage.local.get(lastResultKey);
  return (stored[lastResultKey] as SyncResult | undefined) ?? null;
}

export async function saveLastResult(result: SyncResult): Promise<void> {
  await chrome.storage.local.set({ [lastResultKey]: result });
}

export async function readLastAutomaticAttempt(): Promise<number> {
  const stored = await chrome.storage.local.get(lastAutomaticAttemptKey);
  return Number(stored[lastAutomaticAttemptKey] ?? 0);
}

export async function saveLastAutomaticAttempt(value: number): Promise<void> {
  await chrome.storage.local.set({ [lastAutomaticAttemptKey]: value });
}
