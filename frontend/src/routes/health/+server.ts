import { backendFetch } from '$lib/server/backend';
import type { RequestHandler } from './$types';

/** Confirms that the public SvelteKit server can reach the private Vapor API. */
export const GET: RequestHandler = async (event) => {
  try {
    const response = await backendFetch(event, '/health');
    if (!response.ok) {
      return Response.json({ status: 'unavailable' }, { status: 503 });
    }
    return Response.json(
      { status: 'ok', service: 'flowboard-web' },
      { headers: { 'cache-control': 'no-store' } }
    );
  } catch {
    return Response.json({ status: 'unavailable' }, { status: 503 });
  }
};
