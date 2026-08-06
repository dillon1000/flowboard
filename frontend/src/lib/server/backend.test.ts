import type { RequestEvent } from '@sveltejs/kit';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { backendFetch } from './backend';

function eventFor(url: string): RequestEvent {
  const request = new Request(url);
  return { request, url: new URL(url) } as unknown as RequestEvent;
}

describe('server backend', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('converts a backend connection failure into a retryable service error', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('fetch failed')));

    await expect(backendFetch(eventFor('https://app.example/app'), '/api/v1/app')).rejects
      .toMatchObject({
        status: 503,
        body: { message: 'The server is unavailable. Try again in a moment.' }
      });
  });
});
