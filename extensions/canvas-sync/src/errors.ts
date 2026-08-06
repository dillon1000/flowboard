import type { SyncErrorCode } from './types';

export class SyncError extends Error {
  constructor(public readonly code: SyncErrorCode, message: string) {
    super(message);
    this.name = 'SyncError';
  }
}

export function errorResult(cause: unknown): { code: SyncErrorCode; message: string } {
  if (cause instanceof SyncError) return { code: cause.code, message: cause.message };
  return { code: 'RESPONSE_INVALID', message: 'Canvas returned data that the extension could not validate.' };
}
