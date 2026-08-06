import { writable } from 'svelte/store';

export const activityCount = writable(0);

/**
 * Starts one global request or refresh and returns an idempotent finish callback.
 * Concurrent work increments the shared count, so one fast request cannot hide
 * progress while another request is still active.
 */
export function beginActivity(): () => void {
  let active = true;
  activityCount.update((count) => count + 1);
  return () => {
    if (!active) return;
    active = false;
    activityCount.update((count) => Math.max(0, count - 1));
  };
}
