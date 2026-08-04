import {
  Body,
  Button,
  Container,
  Head,
  Heading,
  Hr,
  Html,
  Link,
  Preview,
  Section,
  Text
} from 'react-email';
import { render, toPlainText } from '@react-email/render';
import type { CSSProperties, ReactElement, ReactNode } from 'react';
import type { NotificationPayload } from './index';

export type NotificationTemplate = {
  subject: string;
  text: string;
  html: string;
};

type NotificationContent = {
  subject: string;
  preview: string;
  heading: string;
  greeting: string;
  body: ReactNode;
  quote?: string;
  actionLabel?: string;
  actionURL?: string;
};

const styles = {
  body: {
    backgroundColor: '#f3f5f9',
    color: '#1b2333',
    fontFamily: 'Arial, Helvetica, sans-serif',
    margin: '0',
    padding: '28px 12px'
  },
  container: {
    backgroundColor: '#ffffff',
    border: '1px solid #e2e7f0',
    borderRadius: '18px',
    margin: '0 auto',
    maxWidth: '600px',
    overflow: 'hidden'
  },
  header: {
    backgroundColor: '#1b2333',
    padding: '24px 32px'
  },
  brand: {
    color: '#ffffff',
    fontSize: '18px',
    fontWeight: '700',
    letterSpacing: '0.12em',
    lineHeight: '24px',
    margin: '0'
  },
  headerLabel: {
    color: '#aeb9cc',
    fontSize: '11px',
    fontWeight: '700',
    letterSpacing: '0.16em',
    lineHeight: '16px',
    margin: '7px 0 0',
    textTransform: 'uppercase'
  },
  content: {
    padding: '36px 40px 32px'
  },
  eyebrow: {
    color: '#6b5cff',
    fontSize: '11px',
    fontWeight: '700',
    letterSpacing: '0.14em',
    lineHeight: '16px',
    margin: '0 0 12px',
    textTransform: 'uppercase'
  },
  heading: {
    color: '#1b2333',
    fontSize: '30px',
    fontWeight: '700',
    letterSpacing: '-0.025em',
    lineHeight: '36px',
    margin: '0 0 24px'
  },
  paragraph: {
    color: '#4a5568',
    fontSize: '16px',
    lineHeight: '26px',
    margin: '0 0 18px'
  },
  quoteSection: {
    backgroundColor: '#f6f7fb',
    borderLeft: '4px solid #6b5cff',
    margin: '24px 0',
    padding: '14px 18px'
  },
  quote: {
    color: '#4a5568',
    fontSize: '15px',
    fontStyle: 'italic',
    lineHeight: '24px',
    margin: '0',
    whiteSpace: 'pre-wrap'
  },
  button: {
    backgroundColor: '#6b5cff',
    borderRadius: '10px',
    color: '#ffffff',
    display: 'inline-block',
    fontSize: '15px',
    fontWeight: '700',
    lineHeight: '20px',
    margin: '8px 0 4px',
    padding: '13px 18px',
    textDecoration: 'none'
  },
  divider: {
    borderColor: '#e2e7f0',
    margin: '0 40px'
  },
  footer: {
    padding: '22px 40px 28px'
  },
  footerText: {
    color: '#8490a3',
    fontSize: '12px',
    lineHeight: '18px',
    margin: '0 0 8px'
  },
  footerBrand: {
    color: '#a3adbd',
    fontSize: '12px',
    lineHeight: '18px',
    margin: '0'
  },
  footerLink: {
    color: '#6b5cff',
    textDecoration: 'underline'
  }
} satisfies Record<string, CSSProperties>;

export async function renderNotification(
  payload: NotificationPayload
): Promise<NotificationTemplate> {
  const content = notificationContent(payload);
  const html = await render(<NotificationEmail {...content} />);
  return {
    subject: content.subject,
    text: toPlainText(html),
    html
  };
}

function NotificationEmail(content: NotificationContent): ReactElement {
  const actionURL = safeURL(content.actionURL);
  return (
    <Html lang="en">
      <Head />
      <Preview>{content.preview}</Preview>
      <Body style={styles.body}>
        <Container style={styles.container}>
          <Section style={styles.header}>
            <Text style={styles.brand}>FLOWBOARD</Text>
            <Text style={styles.headerLabel}>Workspace notification</Text>
          </Section>
          <Section style={styles.content}>
            <Text style={styles.eyebrow}>Flowboard</Text>
            <Heading style={styles.heading}>{content.heading}</Heading>
            <Text style={styles.paragraph}>{content.greeting}</Text>
            {content.body}
            {content.quote ? (
              <Section style={styles.quoteSection}>
                <Text style={styles.quote}>{content.quote}</Text>
              </Section>
            ) : null}
            {actionURL && content.actionLabel ? (
              <Button href={actionURL} style={styles.button}>
                {content.actionLabel}
              </Button>
            ) : null}
          </Section>
          <Hr style={styles.divider} />
          <Section style={styles.footer}>
            <Text style={styles.footerText}>
              You received this because something changed in your Flowboard workspace.
            </Text>
            <Text style={styles.footerBrand}>
              Flowboard · Work, in view.
              {actionURL ? (
                <>
                  {' '}
                  <Link href={actionURL} style={styles.footerLink}>
                    Open workspace
                  </Link>
                </>
              ) : null}
            </Text>
          </Section>
        </Container>
      </Body>
    </Html>
  );
}

function notificationContent(payload: NotificationPayload): NotificationContent {
  const recipientName = dataValue(payload.data, 'recipientName') || 'there';
  const actorName = dataValue(payload.data, 'actorName') || 'A Flowboard user';
  const appURL = dataValue(payload.data, 'appURL') || dataValue(payload.data, 'taskURL');

  switch (payload.type) {
    case 'welcome':
      return {
        subject: 'Welcome to Flowboard',
        preview: 'Your Flowboard account is ready.',
        heading: 'Welcome to Flowboard',
        greeting: `Hi ${recipientName},`,
        body: <Text style={styles.paragraph}>Your Flowboard account is ready.</Text>,
        actionURL: appURL,
        actionLabel: 'Open Flowboard'
      };
    case 'board_member_added': {
      const boardName = dataValue(payload.data, 'boardName') || 'a board';
      const role = dataValue(payload.data, 'role') || 'member';
      return {
        subject: safeLine(`You joined ${boardName}`),
        preview: safeLine(`${actorName} added you to ${boardName} as a ${role}.`),
        heading: 'You joined a board',
        greeting: `Hi ${recipientName},`,
        body: (
          <Text style={styles.paragraph}>
            <strong>{actorName}</strong> added you to <strong>{boardName}</strong> as a{' '}
            <strong>{role}</strong>.
          </Text>
        ),
        actionURL: appURL,
        actionLabel: 'Open the board'
      };
    }
    case 'task_comment_added': {
      const taskTitle = dataValue(payload.data, 'taskTitle') || 'your task';
      const boardName = dataValue(payload.data, 'boardName');
      const commentPreview = dataValue(payload.data, 'commentPreview');
      return {
        subject: safeLine(`${actorName} commented on ${taskTitle}`),
        preview: safeLine(`${actorName} commented on ${taskTitle}.`),
        heading: 'A task has a new comment',
        greeting: `Hi ${recipientName},`,
        body: (
          <Text style={styles.paragraph}>
            <strong>{actorName}</strong> commented on <strong>{taskTitle}</strong>
            {boardName ? <> in <strong>{boardName}</strong></> : null}.
          </Text>
        ),
        quote: commentPreview || undefined,
        actionURL: appURL,
        actionLabel: 'Open the task'
      };
    }
    case 'task_assigned': {
      const taskTitle = dataValue(payload.data, 'taskTitle') || 'a task';
      const boardName = dataValue(payload.data, 'boardName');
      return {
        subject: safeLine(`You were assigned ${taskTitle}`),
        preview: safeLine(`${actorName} assigned you ${taskTitle}.`),
        heading: 'You have a new assignment',
        greeting: `Hi ${recipientName},`,
        body: (
          <Text style={styles.paragraph}>
            <strong>{actorName}</strong> assigned you <strong>{taskTitle}</strong>
            {boardName ? <> in <strong>{boardName}</strong></> : null}.
          </Text>
        ),
        actionURL: appURL,
        actionLabel: 'Open the task'
      };
    }
  }
}

function safeLine(value: string): string {
  return value.replace(/[\r\n]+/g, ' ').trim().slice(0, 200);
}

function safeURL(value: string | undefined): string | undefined {
  if (!value) {
    return undefined;
  }
  try {
    const url = new URL(value);
    return url.protocol === 'http:' || url.protocol === 'https:' ? value : undefined;
  } catch {
    return undefined;
  }
}

function dataValue(data: Record<string, string>, key: string): string {
  return data[key] ?? '';
}
