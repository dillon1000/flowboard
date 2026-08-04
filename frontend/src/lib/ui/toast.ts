import { writable } from 'svelte/store';

export const toastMessage = writable('');

let clearTimer: ReturnType<typeof setTimeout> | undefined;

/** Announces one short success message, replacing any toast that is still open. */
export function showToast(message: string, duration = 2800): void {
  clearTimeout(clearTimer);
  toastMessage.set(message);
  clearTimer = setTimeout(() => toastMessage.set(''), duration);
}
