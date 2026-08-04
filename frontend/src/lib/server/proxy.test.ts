import type { RequestEvent } from '@sveltejs/kit';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { backendFetch } from './backend';
import { proxy } from './proxy';

vi.mock('./backend', () => ({ backendFetch: vi.fn() }));

function eventFor(request: Request): RequestEvent {
  return {
    request,
    params: { path: 'v1/boards' },
    url: new URL(request.url)
  } as unknown as RequestEvent;
}

describe('server proxy', () => {
  const backendFetchMock = vi.mocked(backendFetch);

  beforeEach(() => {
    backendFetchMock.mockReset();
  });

  it('forwards bearer credentials to the backend', async () => {
    backendFetchMock.mockResolvedValue(new Response('ok'));
    const request = new Request('https://public.example/api/v1/boards?archived=false', {
      headers: {
        accept: 'application/json',
        authorization: 'Bearer fbk_test-key'
      }
    });

    const response = await proxy('/api')(eventFor(request));
    const call = backendFetchMock.mock.calls[0];
    const init = call?.[2];

    expect(response.status).toBe(200);
    expect(call?.[1]).toBe('/api/v1/boards?archived=false');
    expect(new Headers(init?.headers).get('authorization')).toBe('Bearer fbk_test-key');
  });
});
