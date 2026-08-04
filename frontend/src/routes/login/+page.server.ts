import { loadAuthConfiguration } from '$lib/server/backend';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => ({
  configuration: await loadAuthConfiguration(event)
});
