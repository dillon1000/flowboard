import { proxy } from '$lib/server/proxy';

const handler = proxy('/.well-known');

export const GET = handler;
