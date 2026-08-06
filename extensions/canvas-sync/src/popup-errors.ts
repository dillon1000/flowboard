import type { SyncErrorCode } from './types';

const messages: Record<SyncErrorCode, string> = {
  NOT_CONFIGURED: 'Configure both origins and the Canvas sync key.',
  CURRENT_TAB_MISMATCH: 'The current tab is not the configured Canvas site.',
  SESSION_EXPIRED: 'Your Canvas session has expired. Sign in and try again.',
  CANVAS_DENIED: 'Canvas denied an API request.',
  CANVAS_REQUEST_FAILED: 'Canvas could not complete an API request.',
  PAGINATION_FAILED: 'Canvas pagination failed, so no snapshot was sent.',
  RESPONSE_INVALID: 'Canvas returned data that the extension could not validate.',
  SYNC_KEY_INVALID: 'The Focalpoint Canvas sync key is invalid.',
  FOCALPOINT_UNAVAILABLE: 'The Focalpoint origin is unavailable.',
  FOCALPOINT_REJECTED: 'Focalpoint rejected the complete snapshot.',
  SYNC_ACTIVE: 'A Canvas sync is already active.',
  PERMISSION_DENIED: 'Chrome did not grant access to the configured origins.'
};

export function popupErrorMessage(code: SyncErrorCode, detail?: string): string {
  return messages[code] ?? detail ?? 'The sync failed.';
}
