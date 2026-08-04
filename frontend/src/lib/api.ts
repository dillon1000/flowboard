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
  const headers = new Headers(init.headers);
  if (init.body && !(init.body instanceof FormData) && !headers.has('content-type')) {
    headers.set('content-type', 'application/json');
  }

  const response = await fetch(path, { ...init, headers });
  if (!response.ok) throw new APIError(await errorMessage(response), response.status);
  if (response.status === 204 || response.headers.get('content-length') === '0') {
    return undefined as T;
  }
  return (await response.json()) as T;
}

export function messageFor(error: unknown): string {
  return error instanceof Error ? error.message : 'The request failed.';
}

async function errorMessage(response: Response): Promise<string> {
  const payload: unknown = await response.json().catch(() => null);
  if (payload && typeof payload === 'object' && 'reason' in payload) {
    const reason = (payload as { reason?: unknown }).reason;
    if (typeof reason === 'string') return reason;
  }
  return response.statusText || 'The request failed.';
}
