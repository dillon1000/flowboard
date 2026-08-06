import { writable } from 'svelte/store';

export type ToastTone = 'success' | 'error';

export interface ToastNotice {
  id: number;
  message: string;
  tone: ToastTone;
}

interface ToastOptions {
  tone?: ToastTone;
  duration?: number;
}

export const toastQueue = writable<ToastNotice[]>([]);

let nextToastID = 1;
const clearTimers = new Map<number, ReturnType<typeof setTimeout>>();

/** Adds a notice without replacing work that the user has not read yet. */
export function showToast(message: string, options: ToastOptions = {}): void {
  const id = nextToastID++;
  const notice: ToastNotice = { id, message, tone: options.tone ?? 'success' };
  toastQueue.update((queue) => [...queue.slice(-3), notice]);
  clearTimers.set(id, setTimeout(() => dismissToast(id), options.duration ?? 2800));
}

export function dismissToast(id: number): void {
  const timer = clearTimers.get(id);
  if (timer) clearTimeout(timer);
  clearTimers.delete(id);
  toastQueue.update((queue) => queue.filter((notice) => notice.id !== id));
}
