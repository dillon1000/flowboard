import { loadAuthConfiguration } from '$lib/server/backend';
import { authenticate } from '$lib/server/auth';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => ({
  configuration: await loadAuthConfiguration(event)
});

export const actions: Actions = {
  default: (event) => authenticate(event, 'register')
};
