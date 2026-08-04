import { describe, expect, it } from 'vitest';
import worker, {
  createSignature,
  type EmailWorkerEnv,
  renderNotification
} from '../src/index';

const secret = 'test-secret-that-is-long-enough-for-hmac';

function makeEnvironment() {
  let sentMessage: EmailMessage | EmailMessageBuilder | undefined;
  const email = {
    async send(message: EmailMessage | EmailMessageBuilder): Promise<EmailSendResult> {
      sentMessage = message;
      return { messageId: 'message-123' };
    }
  } satisfies EmailWorkerEnv['EMAIL'];
  const environment = {
    EMAIL: email,
    NOTIFICATION_SHARED_SECRET: secret,
    SENDER_EMAIL: 'notifications@mail.11011.dev',
    SENDER_NAME: 'Flowboard'
  } satisfies EmailWorkerEnv;
  return { environment, getSentMessage: () => sentMessage };
}

async function signedRequest(body: string, timestamp = String(Math.floor(Date.now() / 1_000))) {
  const signature = await createSignature(secret, timestamp, body);
  return new Request('https://email.example/v1/notifications', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-flowboard-timestamp': timestamp,
      'x-flowboard-signature': `sha256=${signature}`
    },
    body
  });
}

describe('flowboard email worker', () => {
  it('sends a validated notification through the restricted binding', async () => {
    const { environment, getSentMessage } = makeEnvironment();
    const body = JSON.stringify({
      eventID: 'event-1',
      type: 'task_assigned',
      to: 'person@example.com',
      data: {
        recipientName: 'Person',
        actorName: 'Alex',
        taskTitle: 'Finish the report',
        boardName: 'Launch',
        taskURL: 'https://app.example/tasks/finish-the-report-abc123'
      }
    });

    const response = await worker.fetch(await signedRequest(body), environment);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ eventID: 'event-1', messageID: 'message-123' });
    expect(getSentMessage()).toMatchObject({
      to: 'person@example.com',
      from: { email: 'notifications@mail.11011.dev', name: 'Flowboard' },
      subject: 'You were assigned Finish the report'
    });
  });

  it('rejects stale signatures before parsing the payload', async () => {
    const { environment } = makeEnvironment();
    const body = JSON.stringify({
      eventID: 'event-1',
      type: 'welcome',
      to: 'person@example.com',
      data: {}
    });
    const request = await signedRequest(body, String(Math.floor(Date.now() / 1_000) - 301));

    const response = await worker.fetch(request, environment);
    expect(response.status).toBe(401);
  });

  it('escapes user content in HTML templates', () => {
    const result = renderNotification({
      eventID: 'event-1',
      type: 'task_comment_added',
      to: 'person@example.com',
      data: {
        recipientName: 'Person',
        actorName: '<Alex>',
        taskTitle: '<script>alert(1)</script>',
        commentPreview: 'Use <strong>plain text</strong>.',
        taskURL: 'https://app.example/tasks/example-abc123'
      }
    });

    expect(result.html).toContain('&lt;script&gt;alert(1)&lt;/script&gt;');
    expect(result.html).not.toContain('<script>alert(1)</script>');
  });
});
