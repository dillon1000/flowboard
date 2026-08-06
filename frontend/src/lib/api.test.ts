import { goto } from '$app/navigation';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from './api';

vi.mock('$app/navigation', () => ({
  goto: vi.fn().mockResolvedValue(undefined),
  invalidateAll: vi.fn()
}));

vi.mock('$lib/ui/progress', () => ({ beginActivity: () => vi.fn() }));
vi.mock('$lib/ui/toast', () => ({ showToast: vi.fn() }));

describe('client api', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it('sends an expired session to login with the current location', async () => {
    vi.stubGlobal('location', {
      pathname: '/app/tasks/assignment-1',
      search: '?panel=notes',
      hash: '#editor'
    });
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(
      JSON.stringify({ reason: 'Session expired' }),
      { status: 401, headers: { 'content-type': 'application/json' } }
    )));

    await expect(api('/api/v1/tasks/assignment-1')).rejects.toMatchObject({ status: 401 });
    expect(goto).toHaveBeenCalledWith(
      '/login?returnTo=%2Fapp%2Ftasks%2Fassignment-1%3Fpanel%3Dnotes%23editor'
    );
  });
});
