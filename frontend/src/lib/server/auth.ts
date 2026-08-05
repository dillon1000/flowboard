import { backendFetch, responseReason } from '$lib/server/backend';
import { error, fail, redirect, type RequestEvent } from '@sveltejs/kit';

export interface AuthActionData {
  message: string;
  values: {
    name?: string;
    email: string;
  };
}

/** Runs password authentication on the private backend and installs its browser session. */
export async function authenticate(event: RequestEvent, mode: 'login' | 'register') {
  const data = await event.request.formData();
  const name = String(data.get('name') ?? '');
  const email = String(data.get('email') ?? '');
  const password = String(data.get('password') ?? '');
  const timeZone = String(data.get('timeZone') ?? 'UTC');
  const body: Record<string, string> = { email, password, timeZone };
  if (mode === 'register') body.name = name;

  const response = await backendFetch(event, `/api/v1/auth/${mode}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  if (!response.ok) {
    return fail(response.status, {
      message: await responseReason(response),
      values: { name: mode === 'register' ? name : undefined, email }
    } satisfies AuthActionData);
  }

  installSessionCookie(event, response);
  const requested = event.url.searchParams.get('returnTo');
  const destination = requested?.startsWith('/') && !requested.startsWith('//') ? requested : '/app';
  redirect(303, destination);
}

/** Copies the one session credential created by Vapor without exposing it to client code. */
function installSessionCookie(event: RequestEvent, response: Response): void {
  const value = response.headers.get('set-cookie')?.match(/(?:^|,\s*)flowboard-session=([^;]+)/)?.[1];
  if (!value) error(502, 'The authentication service did not create a session.');
  event.cookies.set('flowboard-session', value, {
    path: '/',
    httpOnly: true,
    sameSite: 'lax',
    secure: event.url.protocol === 'https:',
    maxAge: 60 * 60 * 24 * 14,
    // Vapor session IDs are Base64 and can end in `=`. Preserve that valid cookie
    // byte because percent-encoding it would create a different session key.
    encode: (sessionID) => sessionID
  });
}
