import { loadWorkspacePage } from '$lib/server/backend';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => ({
  context: await loadWorkspacePage(
    event,
    `/api/v1/workspace/${event.params.path}${event.url.search}`
  )
});
