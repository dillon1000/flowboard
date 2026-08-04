import { backendFetch } from '$lib/server/backend';
import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => {
  const response = await backendFetch(event, '/api/v1/auth/me');
  redirect(307, response.ok ? '/app' : '/login');
};
