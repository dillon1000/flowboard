import {
  Body,
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
  greeting?: string;
  body: ReactNode;
  quote?: string;
  actionLabel?: string;
  actionURL?: string;
};

const styles = {
  body: {
    backgroundColor: '#f5f5f3',
    color: '#1d1d1b',
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif',
    margin: '0',
    padding: '0 16px'
  },
  container: {
    backgroundColor: '#ffffff',
    margin: '0 auto',
    maxWidth: '640px'
  },
  header: {
    borderBottom: '1px solid #d9d9d4',
    padding: '28px 48px 21px'
  },
  brand: {
    color: '#1d1d1b',
    fontSize: '16px',
    fontWeight: '600',
    letterSpacing: '-0.02em',
    lineHeight: '22px',
    margin: '0'
  },
  content: {
    padding: '48px 48px 52px'
  },
  heading: {
    color: '#1d1d1b',
    fontSize: '24px',
    fontWeight: '700',
    letterSpacing: '-0.02em',
    lineHeight: '30px',
    margin: '0 0 24px'
  },
  greeting: {
    color: '#5a5a54',
    fontSize: '14px',
    lineHeight: '22px',
    margin: '0 0 12px'
  },
  paragraph: {
    color: '#4b4b46',
    fontSize: '15px',
    lineHeight: '24px',
    margin: '0 0 20px'
  },
  task: {
    borderBottom: '1px solid #d9d9d4',
    borderTop: '1px solid #d9d9d4',
    margin: '8px 0 28px',
    padding: '14px 0 15px'
  },
  taskBoard: {
    color: '#8b8b84',
    fontSize: '12px',
    lineHeight: '18px',
    margin: '0 0 4px'
  },
  taskTitle: {
    color: '#1d1d1b',
    fontSize: '18px',
    fontWeight: '700',
    lineHeight: '24px',
    margin: '0'
  },
  quoteSection: {
    borderLeft: '2px solid #1d1d1b',
    margin: '0 0 28px',
    padding: '0 0 0 16px'
  },
  quote: {
    color: '#33332f',
    fontSize: '16px',
    lineHeight: '25px',
    margin: '0',
    whiteSpace: 'pre-wrap'
  },
  action: {
    color: '#604bc4',
    fontSize: '14px',
    fontWeight: '600',
    lineHeight: '20px',
    margin: '0',
    textDecoration: 'underline'
  },
  divider: {
    borderColor: '#d9d9d4',
    margin: '0'
  },
  footer: {
    padding: '18px 48px 30px'
  },
  footerText: {
    color: '#8b8b84',
    fontSize: '12px',
    lineHeight: '18px',
    margin: '0'
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
            <Text style={styles.brand}>Flowboard</Text>
          </Section>
          <Section style={styles.content}>
            <Heading style={styles.heading}>{content.heading}</Heading>
            {content.greeting ? <Text style={styles.greeting}>{content.greeting}</Text> : null}
            {content.body}
            {content.quote ? (
              <Section style={styles.quoteSection}>
                <Text style={styles.quote}>{content.quote}</Text>
              </Section>
            ) : null}
            {actionURL && content.actionLabel ? (
              <Text style={styles.action}>
                <Link href={actionURL} style={styles.action}>
                  {content.actionLabel}
                </Link>
              </Text>
            ) : null}
          </Section>
          <Hr style={styles.divider} />
          <Section style={styles.footer}>
            <Text style={styles.footerText}>
              You received this because something changed in your Flowboard workspace.
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
        heading: safeLine(`You joined ${boardName}`),
        body: (
          <Text style={styles.paragraph}>
            <strong>{actorName}</strong> added you as a <strong>{role}</strong>.
          </Text>
        ),
        actionURL: appURL,
        actionLabel: 'View board'
      };
    }
    case 'task_comment_added': {
      const taskTitle = dataValue(payload.data, 'taskTitle') || 'your task';
      const boardName = dataValue(payload.data, 'boardName');
      const commentPreview = dataValue(payload.data, 'commentPreview');
      return {
        subject: safeLine(`${actorName} commented on ${taskTitle}`),
        preview: safeLine(`${actorName} commented on ${taskTitle}.`),
        heading: safeLine(`${actorName} commented on`),
        body: taskDetails(taskTitle, boardName),
        quote: commentPreview || undefined,
        actionURL: appURL,
        actionLabel: 'View task'
      };
    }
    case 'task_assigned': {
      const taskTitle = dataValue(payload.data, 'taskTitle') || 'a task';
      const boardName = dataValue(payload.data, 'boardName');
      return {
        subject: safeLine(`You were assigned ${taskTitle}`),
        preview: safeLine(`${actorName} assigned you ${taskTitle}.`),
        heading: 'You have a new assignment',
        body: (
          <>
            <Text style={styles.paragraph}>Assigned by <strong>{actorName}</strong>:</Text>
            {taskDetails(taskTitle, boardName)}
          </>
        ),
        actionURL: appURL,
        actionLabel: 'View task'
      };
    }
    case 'task_reminder': {
      const taskTitle = dataValue(payload.data, 'taskTitle') || 'your task';
      const boardName = dataValue(payload.data, 'boardName');
      const reminderTime = dataValue(payload.data, 'reminderTime');
      const taskDue = dataValue(payload.data, 'taskDue');
      return {
        subject: safeLine(`Reminder: ${taskTitle}`),
        preview: safeLine(`Your reminder for ${taskTitle}.`),
        heading: 'Assignment reminder',
        greeting: `Hi ${recipientName},`,
        body: (
          <>
            <Text style={styles.paragraph}>
              {reminderTime ? `You set this reminder for ${reminderTime}.` : 'Your reminder is due.'}
            </Text>
            {taskDetails(taskTitle, boardName)}
            {taskDue ? <Text style={styles.paragraph}>Due {taskDue}</Text> : null}
          </>
        ),
        actionURL: appURL,
        actionLabel: 'View task'
      };
    }
  }
}

function taskDetails(taskTitle: string, boardName: string | undefined): ReactElement {
  return (
    <Section style={styles.task}>
      {boardName ? <Text style={styles.taskBoard}>{boardName}</Text> : null}
      <Text style={styles.taskTitle}>{taskTitle}</Text>
    </Section>
  );
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
