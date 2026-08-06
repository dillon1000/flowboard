import { goto, invalidateAll } from '$app/navigation';
import { beginActivity } from '$lib/ui/progress';
import { showToast } from '$lib/ui/toast';

export class APIError extends Error {
  constructor(
    message: string,
    readonly status: number
  ) {
    super(message);
    this.name = 'APIError';
  }
}

/** Sends a same-origin API request and returns the typed JSON body when present. */
export async function api<T = void>(path: string, init: RequestInit = {}): Promise<T> {
  const finishActivity = beginActivity();
  const headers = new Headers(init.headers);
  if (init.body && !(init.body instanceof FormData) && !headers.has('content-type')) {
    headers.set('content-type', 'application/json');
  }

  try {
    const response = await fetch(path, { ...init, headers });
    if (response.status === 401) {
      const returnTo = `${location.pathname}${location.search}${location.hash}`;
      await goto(`/login?returnTo=${encodeURIComponent(returnTo)}`);
    }
    if (!response.ok) throw new APIError(await errorMessage(response), response.status);
    if (response.status === 204 || response.headers.get('content-length') === '0') {
      return undefined as T;
    }
    return (await response.json()) as T;
  } finally {
    finishActivity();
  }
}

/** Refetches page data while the application progress line stays visible. */
export async function refreshAll(): Promise<void> {
  const finishActivity = beginActivity();
  try {
    await invalidateAll();
  } finally {
    finishActivity();
  }
}

/** Returns a useful inline error and also puts it in the persistent status stack. */
export function messageFor(error: unknown): string {
  const message = error instanceof Error ? error.message : 'The request failed.';
  showToast(message, { tone: 'error', duration: 6000 });
  return message;
}

async function errorMessage(response: Response): Promise<string> {
  const payload: unknown = await response.json().catch(() => null);
  if (payload && typeof payload === 'object' && 'reason' in payload) {
    const reason = (payload as { reason?: unknown }).reason;
    if (typeof reason === 'string') return reason;
  }
  return response.statusText || 'The request failed.';
}
