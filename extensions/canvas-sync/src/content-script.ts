import { collectCanvasSnapshot } from './canvas-api';
import { errorResult } from './errors';
import type { ExtensionMessage } from './types';

chrome.runtime.onMessage.addListener((message: ExtensionMessage, _sender, sendResponse) => {
  if (message.type !== 'collectCanvasSnapshot') return false;
  if (window.location.origin !== message.canvasOrigin) {
    sendResponse({ error: { code: 'CURRENT_TAB_MISMATCH', message: 'The current tab is not the configured Canvas site.' } });
    return false;
  }
  void collectCanvasSnapshot(message.canvasOrigin)
    .then((snapshot) => sendResponse({ snapshot }))
    .catch((cause: unknown) => sendResponse({ error: errorResult(cause) }));
  return true;
});

void chrome.runtime.sendMessage({ type: 'canvasPageReady' } satisfies ExtensionMessage).catch(() => undefined);
