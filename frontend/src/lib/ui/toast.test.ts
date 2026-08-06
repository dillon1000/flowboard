import { get } from 'svelte/store';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { dismissToast, showToast, toastQueue } from './toast';

describe('toast actions', () => {
  afterEach(() => {
    for (const notice of get(toastQueue)) dismissToast(notice.id);
    vi.useRealTimers();
  });

  it('keeps an actionable notice visible long enough to undo', () => {
    vi.useFakeTimers();
    const onclick = vi.fn();

    showToast('Study session removed', { action: { label: 'Undo', onclick } });

    expect(get(toastQueue)[0]?.action).toEqual({ label: 'Undo', onclick });
    vi.advanceTimersByTime(2_800);
    expect(get(toastQueue)).toHaveLength(1);
    vi.advanceTimersByTime(3_200);
    expect(get(toastQueue)).toHaveLength(0);
  });
});
