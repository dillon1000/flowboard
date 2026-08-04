const MAX_REQUEST_BYTES = 32 * 1024;
const MAX_DATA_FIELDS = 16;
const MAX_DATA_VALUE_LENGTH = 4_000;
const SIGNATURE_MAX_AGE_SECONDS = 300;

const notificationTypes = [
  'welcome',
  'board_member_added',
  'task_comment_added',
  'task_assigned'
] as const;

export type NotificationType = (typeof notificationTypes)[number];

export type EmailWorkerEnv = Env & {
  NOTIFICATION_SHARED_SECRET: string;
  SENDER_EMAIL: string;
  SENDER_NAME: string;
};

type NotificationPayload = {
  eventID: string;
  type: NotificationType;
  to: string;
  data: Record<string, string>;
};

type NotificationTemplate = {
  subject: string;
  text: string;
  html: string;
};

type WorkerError = {
  code?: unknown;
  message?: unknown;
};

export default {
  async fetch(request: Request, env: EmailWorkerEnv): Promise<Response> {
    try {
      return await handleRequest(request, env);
    } catch (error) {
      console.error(
        JSON.stringify({
          message: 'Unhandled email worker error',
          error: error instanceof Error ? error.message : String(error)
        })
      );
      return errorResponse(500, 'internal_error');
    }
  }
} satisfies ExportedHandler<EmailWorkerEnv>;

export async function handleRequest(
  request: Request,
  env: EmailWorkerEnv
): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === 'GET' && url.pathname === '/health') {
    return Response.json({ status: 'ok', service: 'flowboard-email' });
  }

  if (url.pathname !== '/v1/notifications') {
    return errorResponse(404, 'not_found');
  }
  if (request.method !== 'POST') {
    return errorResponse(405, 'method_not_allowed', { Allow: 'POST' });
  }

  const bodyLength = request.headers.get('content-length');
  if (bodyLength && Number(bodyLength) > MAX_REQUEST_BYTES) {
    return errorResponse(413, 'request_too_large');
  }

  const body = await request.text();
  if (new TextEncoder().encode(body).byteLength > MAX_REQUEST_BYTES) {
    return errorResponse(413, 'request_too_large');
  }

  const timestamp = request.headers.get('x-flowboard-timestamp');
  const signature = request.headers.get('x-flowboard-signature');
  if (
    !timestamp ||
    !signature ||
    !(await verifySignature(env.NOTIFICATION_SHARED_SECRET, timestamp, signature, body))
  ) {
    return errorResponse(401, 'invalid_signature');
  }

  let payload: NotificationPayload;
  try {
    payload = parseNotificationPayload(JSON.parse(body) as unknown);
  } catch {
    return errorResponse(400, 'invalid_payload');
  }

  const template = renderNotification(payload);
  try {
    const result = await env.EMAIL.send({
      to: payload.to,
      from: { email: env.SENDER_EMAIL, name: env.SENDER_NAME },
      subject: template.subject,
      text: template.text,
      html: template.html,
      headers: { 'X-Flowboard-Event-ID': payload.eventID }
    });

    return Response.json({ eventID: payload.eventID, messageID: result.messageId });
  } catch (error) {
    const details = errorDetails(error);
    console.error(
      JSON.stringify({
        message: 'Email send failed',
        code: details.code,
        eventID: payload.eventID,
        type: payload.type
      })
    );
    return errorResponse(details.code === 'E_RATE_LIMIT_EXCEEDED' ? 429 : 502, 'email_send_failed');
  }
}

export async function createSignature(
  secret: string,
  timestamp: string,
  body: string
): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const input = new TextEncoder().encode(`${timestamp}.${body}`);
  const signature = new Uint8Array(await crypto.subtle.sign('HMAC', key, input));
  return Array.from(signature, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

export function renderNotification(payload: NotificationPayload): NotificationTemplate {
  const recipientName = dataValue(payload.data, 'recipientName') || 'there';
  const actorName = dataValue(payload.data, 'actorName') || 'A Flowboard user';
  const appURL = dataValue(payload.data, 'appURL') || dataValue(payload.data, 'taskURL');

  switch (payload.type) {
    case 'welcome': {
      const subject = 'Welcome to Flowboard';
      const text = `Hi ${recipientName},\n\nYour Flowboard account is ready.`;
      return template(subject, text, [
        `<p>Hi ${escapeHTML(recipientName)},</p>`,
        '<p>Your Flowboard account is ready.</p>',
        linkParagraph(appURL, 'Open Flowboard')
      ]);
    }
    case 'board_member_added': {
      const boardName = dataValue(payload.data, 'boardName') || 'a board';
      const role = dataValue(payload.data, 'role') || 'member';
      const subject = safeLine(`You joined ${boardName}`);
      const text = `Hi ${recipientName},\n\n${actorName} added you to ${boardName} as a ${role}.`;
      return template(subject, text, [
        `<p>Hi ${escapeHTML(recipientName)},</p>`,
        `<p>${escapeHTML(actorName)} added you to <strong>${escapeHTML(boardName)}</strong> as a ${escapeHTML(role)}.</p>`,
        linkParagraph(appURL, 'Open the board')
      ]);
    }
    case 'task_comment_added': {
      const taskTitle = dataValue(payload.data, 'taskTitle') || 'your task';
      const boardName = dataValue(payload.data, 'boardName');
      const commentPreview = dataValue(payload.data, 'commentPreview');
      const subject = safeLine(`${actorName} commented on ${taskTitle}`);
      const text = [
        `Hi ${recipientName},`,
        '',
        `${actorName} commented on ${taskTitle}${boardName ? ` in ${boardName}` : ''}:`,
        '',
        commentPreview,
        '',
        appURL ? `Open the task: ${appURL}` : ''
      ].join('\n');
      return template(subject, text, [
        `<p>Hi ${escapeHTML(recipientName)},</p>`,
        `<p>${escapeHTML(actorName)} commented on <strong>${escapeHTML(taskTitle)}</strong>${boardName ? ` in ${escapeHTML(boardName)}` : ''}:</p>`,
        `<blockquote>${escapeHTML(commentPreview)}</blockquote>`,
        linkParagraph(appURL, 'Open the task')
      ]);
    }
    case 'task_assigned': {
      const taskTitle = dataValue(payload.data, 'taskTitle') || 'a task';
      const boardName = dataValue(payload.data, 'boardName');
      const subject = safeLine(`You were assigned ${taskTitle}`);
      const text = `Hi ${recipientName},\n\n${actorName} assigned you ${taskTitle}${boardName ? ` in ${boardName}` : ''}.${appURL ? `\n\nOpen the task: ${appURL}` : ''}`;
      return template(subject, text, [
        `<p>Hi ${escapeHTML(recipientName)},</p>`,
        `<p>${escapeHTML(actorName)} assigned you <strong>${escapeHTML(taskTitle)}</strong>${boardName ? ` in ${escapeHTML(boardName)}` : ''}.</p>`,
        linkParagraph(appURL, 'Open the task')
      ]);
    }
  }
}

async function verifySignature(
  secret: string,
  timestamp: string,
  suppliedSignature: string,
  body: string
): Promise<boolean> {
  if (!/^\d{1,12}$/.test(timestamp)) {
    return false;
  }

  const age = Math.abs(Math.floor(Date.now() / 1_000) - Number(timestamp));
  if (age > SIGNATURE_MAX_AGE_SECONDS) {
    return false;
  }

  const normalized = suppliedSignature.replace(/^sha256=/i, '').toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(normalized)) {
    return false;
  }

  const expected = await createSignature(secret, timestamp, body);
  return timingSafeEqual(normalized, expected);
}

function timingSafeEqual(left: string, right: string): boolean {
  let difference = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    difference |= (left.charCodeAt(index) || 0) ^ (right.charCodeAt(index) || 0);
  }
  return difference === 0;
}

function parseNotificationPayload(input: unknown): NotificationPayload {
  if (!isRecord(input)) {
    throw new Error('Notification payload must be an object.');
  }

  const eventID = input.eventID;
  const type = input.type;
  const to = input.to;
  const data = input.data;
  if (
    typeof eventID !== 'string' ||
    eventID.length < 1 ||
    eventID.length > 80 ||
    typeof type !== 'string' ||
    !isNotificationType(type) ||
    typeof to !== 'string' ||
    !isEmail(to) ||
    !isRecord(data)
  ) {
    throw new Error('Notification payload fields are invalid.');
  }

  const normalizedData: Record<string, string> = {};
  const entries = Object.entries(data);
  if (entries.length > MAX_DATA_FIELDS) {
    throw new Error('Notification payload has too many data fields.');
  }
  for (const [key, value] of entries) {
    if (
      key.length < 1 ||
      key.length > 80 ||
      typeof value !== 'string' ||
      value.length > MAX_DATA_VALUE_LENGTH
    ) {
      throw new Error('Notification data is invalid.');
    }
    normalizedData[key] = value;
  }

  return { eventID, type, to: to.trim(), data: normalizedData };
}

function template(subject: string, text: string, paragraphs: string[]): NotificationTemplate {
  const body = paragraphs.filter(Boolean).join('');
  return {
    subject,
    text,
    html: `<!doctype html><html><body style="font-family:Arial,sans-serif;line-height:1.5;color:#202124"><main style="max-width:600px;margin:24px auto">${body}</main></body></html>`
  };
}

function linkParagraph(url: string, label: string): string {
  if (!/^https?:\/\//i.test(url)) {
    return '';
  }
  return `<p><a href="${escapeHTML(url)}">${escapeHTML(label)}</a></p>`;
}

function escapeHTML(value: string): string {
  return value.replace(/[&<>'"]/g, (character) => {
    const entities: Record<string, string> = {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      "'": '&#39;',
      '"': '&quot;'
    };
    return entities[character] ?? character;
  });
}

function safeLine(value: string): string {
  return value.replace(/[\r\n]+/g, ' ').trim().slice(0, 200);
}

function dataValue(data: Record<string, string>, key: string): string {
  return data[key] ?? '';
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isNotificationType(value: string): value is NotificationType {
  return notificationTypes.includes(value as NotificationType);
}

function isEmail(value: string): boolean {
  return value.length <= 320 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function errorDetails(error: unknown): { code: string; message: string } {
  if (typeof error === 'object' && error !== null) {
    const candidate = error as WorkerError;
    return {
      code: typeof candidate.code === 'string' ? candidate.code : 'unknown',
      message: typeof candidate.message === 'string' ? candidate.message : 'unknown'
    };
  }
  return { code: 'unknown', message: String(error) };
}

function errorResponse(
  status: number,
  code: string,
  headers: Record<string, string> = {}
): Response {
  return Response.json(
    { error: code },
    { status, headers: { ...headers, 'cache-control': 'no-store' } }
  );
}
