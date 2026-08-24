import { proxy } from '$lib/server/proxy';

const handler = proxy('/mcp');

export const GET = handler;
export const POST = handler;
export const DELETE = handler;
