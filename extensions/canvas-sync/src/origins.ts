import { SyncError } from './errors';

/** Returns one canonical HTTPS origin and rejects credentials, paths, and URL extras. */
export function canonicalHTTPSOrigin(value: string): string {
  let url: URL;
  try {
    url = new URL(value.trim());
  } catch {
    throw new SyncError('RESPONSE_INVALID', 'Enter a valid HTTPS origin.');
  }
  if (
    url.protocol !== 'https:'
    || url.username
    || url.password
    || (url.pathname !== '/' && url.pathname !== '')
    || url.search
    || url.hash
  ) {
    throw new SyncError('RESPONSE_INVALID', 'Use an HTTPS origin with no credentials, path, query, or fragment.');
  }
  return url.origin;
}

export function originPattern(origin: string): string {
  return `${canonicalHTTPSOrigin(origin)}/*`;
}
