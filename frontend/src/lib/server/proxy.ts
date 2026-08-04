import { backendFetch } from '$lib/server/backend';
import type { RequestHandler } from '@sveltejs/kit';

const REQUEST_HEADERS = [
  'accept',
  'authorization',
  'content-type',
  'origin',
  'referer',
  'user-agent'
];
const RESPONSE_HEADERS = [
  'cache-control',
  'content-disposition',
  'content-language',
  'content-type',
  'etag',
  'last-modified',
  'location',
  'referrer-policy',
  'www-authenticate',
  'x-robots-tag'
];

/**
 * Proxies public application endpoints to Vapor without exposing its loopback
 * port. Response bodies remain byte-for-byte safe for uploads and attachments.
 */
export function proxy(prefix: string): RequestHandler {
  return async (event) => {
    const path = event.params.path ? `${prefix}/${event.params.path}` : prefix;
    const headers = new Headers();
    for (const name of REQUEST_HEADERS) {
      const value = event.request.headers.get(name);
      if (value) headers.set(name, value);
    }

    const hasBody = !['GET', 'HEAD'].includes(event.request.method);
    const response = await backendFetch(event, `${path}${event.url.search}`, {
      method: event.request.method,
      headers,
      body: hasBody ? await event.request.arrayBuffer() : undefined
    });

    const responseHeaders = new Headers();
    for (const name of RESPONSE_HEADERS) {
      const value = response.headers.get(name);
      if (value) responseHeaders.set(name, value);
    }

    const cookieHeaders = response.headers as Headers & { getSetCookie?: () => string[] };
    const setCookies = cookieHeaders.getSetCookie?.() ?? [];
    for (const cookie of setCookies) responseHeaders.append('set-cookie', cookie);
    if (setCookies.length === 0) {
      const cookie = response.headers.get('set-cookie');
      if (cookie) responseHeaders.append('set-cookie', cookie);
    }

    // Fetch rejects bodies on these HTTP statuses, including a zero-byte ArrayBuffer.
    // Keep the backend status intact so successful no-content mutations stay successful.
    const responseHasBody = event.request.method !== 'HEAD' && ![204, 205, 304].includes(response.status);
    return new Response(responseHasBody ? await response.arrayBuffer() : null, {
      status: response.status,
      headers: responseHeaders
    });
  };
}
