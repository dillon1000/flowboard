import { SyncError } from './errors';

export function parseCanvasLinkHeader(value: string | null): Record<string, string> {
  if (!value) return {};
  const links: Record<string, string> = {};
  for (const part of value.split(/,(?=\s*<)/)) {
    const match = part.trim().match(/^<([^>]+)>;\s*rel="([^"]+)"$/);
    if (!match?.[1] || !match[2]) {
      throw new SyncError('PAGINATION_FAILED', 'Canvas returned an invalid pagination link.');
    }
    links[match[2]] = match[1];
  }
  return links;
}

/** Reads every Canvas page and fails the full operation when any page is invalid. */
export async function fetchAllCanvasPages<T>(
  initialURL: string,
  fetchPage: typeof fetch = fetch
): Promise<T[]> {
  const items: T[] = [];
  const seen = new Set<string>();
  let nextURL: string | undefined = initialURL;
  while (nextURL) {
    if (seen.has(nextURL) || seen.size >= 1_000) {
      throw new SyncError('PAGINATION_FAILED', 'Canvas pagination did not finish safely.');
    }
    seen.add(nextURL);
    let response: Response;
    try {
      response = await fetchPage(nextURL, { method: 'GET', credentials: 'include' });
    } catch {
      throw new SyncError('CANVAS_REQUEST_FAILED', 'Canvas could not be reached from this signed-in page.');
    }
    if (response.status === 401) throw new SyncError('SESSION_EXPIRED', 'Your Canvas session has expired. Sign in and try again.');
    if (response.status === 403) throw new SyncError('CANVAS_DENIED', 'Canvas denied an API request.');
    if (!response.ok) throw new SyncError('CANVAS_REQUEST_FAILED', `Canvas returned HTTP ${response.status}.`);
    let page: unknown;
    try {
      page = await response.json();
    } catch {
      throw new SyncError('RESPONSE_INVALID', 'Canvas returned an invalid JSON response.');
    }
    if (!Array.isArray(page)) throw new SyncError('RESPONSE_INVALID', 'Canvas returned an unexpected page response.');
    items.push(...page as T[]);
    nextURL = parseCanvasLinkHeader(response.headers.get('Link')).next;
  }
  return items;
}
