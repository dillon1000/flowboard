import { proxy } from '$lib/server/proxy';

const handler = proxy('/oauth');

export const GET = handler;
