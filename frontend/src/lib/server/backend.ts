import { env } from '$env/dynamic/private';
import { error, redirect } from '@sveltejs/kit';
import type { AppPageContext, AuthConfiguration } from '$lib/types';
import type { RequestEvent } from '@sveltejs/kit';

const DEFAULT_BACKEND_URL = 'http://127.0.0.1:8080';

/**
 * Builds a direct request to the private Vapor process. Browser identity stays in
 * the original cookie, while forwarded headers let Vapor create public API URLs.
 */
export async function backendFetch(
  event: RequestEvent,
  path: string,
  init: RequestInit = {}
): Promise<Response> {
  const baseURL = (env.BACKEND_URL ?? DEFAULT_BACKEND_URL).replace(/\/$/, '');
  const headers = new Headers(init.headers);
  const cookie = event.request.headers.get('cookie');

  if (cookie) headers.set('cookie', cookie);
  headers.set('x-forwarded-host', event.url.host);
  headers.set('x-forwarded-proto', event.url.protocol.replace(':', ''));

  try {
    return await fetch(`${baseURL}${path}`, {
      ...init,
      headers,
      redirect: 'manual'
    });
  } catch {
    error(503, 'The server is unavailable. Try again in a moment.');
  }
}

/** Loads one complete workspace screen and converts backend failures into SvelteKit responses. */
export async function loadWorkspacePage(event: RequestEvent, path: string): Promise<AppPageContext> {
  const response = await backendFetch(event, path);

  if (response.status === 401) {
    const returnTo = `${event.url.pathname}${event.url.search}`;
    redirect(303, `/login?returnTo=${encodeURIComponent(returnTo)}`);
  }

  if (!response.ok) {
    error(response.status, await responseReason(response));
  }

  const value: unknown = await response.json();
  if (isRedirectPayload(value)) redirect(307, value.href);
  return value as AppPageContext;
}

export async function loadAuthConfiguration(event: RequestEvent): Promise<AuthConfiguration> {
  const response = await backendFetch(event, '/api/v1/auth/config');
  if (!response.ok) error(response.status, await responseReason(response));
  return (await response.json()) as AuthConfiguration;
}

export async function responseReason(response: Response): Promise<string> {
  const fallback = response.statusText || 'The request failed.';
  const contentType = response.headers.get('content-type') ?? '';
  if (!contentType.includes('application/json')) return fallback;

  const payload: unknown = await response.json().catch(() => null);
  if (payload && typeof payload === 'object' && 'reason' in payload) {
    const reason = (payload as { reason?: unknown }).reason;
    if (typeof reason === 'string') return reason;
  }
  return fallback;
}

function isRedirectPayload(value: unknown): value is { href: string } {
  return Boolean(
    value &&
      typeof value === 'object' &&
      'href' in value &&
      typeof (value as { href?: unknown }).href === 'string' &&
      !('common' in value)
  );
}
