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
  label: string;
  heading: string;
  greeting?: string;
  body: ReactNode;
  quote?: string;
  actionLabel?: string;
  actionURL?: string;
};

const styles = {
  body: {
    backgroundColor: '#f4f4f1',
    color: '#171717',
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif',
    margin: '0',
    padding: '32px 12px'
  },
  container: {
    backgroundColor: '#ffffff',
    border: '1px solid #deded8',
    borderTop: '4px solid #7257e8',
    borderRadius: '10px',
    margin: '0 auto',
    maxWidth: '560px',
    overflow: 'hidden'
  },
  header: {
    borderBottom: '1px solid #ecece7',
    padding: '22px 32px 20px'
  },
  brand: {
    color: '#171717',
    fontSize: '15px',
    fontWeight: '700',
    letterSpacing: '0.08em',
    lineHeight: '20px',
    margin: '0'
  },
  content: {
    padding: '34px 32px 32px'
  },
  eyebrow: {
    color: '#7257e8',
    fontSize: '10px',
    fontWeight: '700',
    letterSpacing: '0.14em',
    lineHeight: '16px',
    margin: '0 0 12px',
    textTransform: 'uppercase'
  },
  heading: {
    color: '#171717',
    fontSize: '26px',
    fontWeight: '700',
    letterSpacing: '-0.025em',
    lineHeight: '31px',
    margin: '0 0 20px'
  },
  greeting: {
    color: '#5e5e59',
    fontSize: '14px',
    lineHeight: '22px',
    margin: '0 0 12px'
  },
  paragraph: {
    color: '#4a4a45',
    fontSize: '15px',
    lineHeight: '23px',
    margin: '0 0 16px'
  },
  task: {
    backgroundColor: '#fafaf8',
    border: '1px solid #e6e6df',
    borderRadius: '8px',
    margin: '18px 0 22px',
    padding: '15px 16px'
  },
  taskTitle: {
    color: '#171717',
    fontSize: '16px',
    fontWeight: '700',
    lineHeight: '22px',
    margin: '0'
  },
  taskMeta: {
    color: '#8c8c83',
    fontSize: '12px',
    lineHeight: '18px',
    margin: '4px 0 0'
  },
  quoteSection: {
    borderLeft: '3px solid #7257e8',
    margin: '22px 0 24px',
    padding: '1px 0 1px 16px'
  },
  quote: {
    color: '#4a4a45',
    fontSize: '15px',
    lineHeight: '23px',
    margin: '0',
    whiteSpace: 'pre-wrap'
  },
  action: {
    color: '#171717',
    fontSize: '14px',
    fontWeight: '700',
    lineHeight: '20px',
    textDecoration: 'none'
  },
  actionArrow: {
    color: '#7257e8',
    fontSize: '18px',
    lineHeight: '20px'
  },
  divider: {
    borderColor: '#ecece7',
    margin: '0 32px'
  },
  footer: {
    backgroundColor: '#fcfcfb',
    padding: '18px 32px 24px'
  },
  footerText: {
    color: '#999990',
    fontSize: '12px',
    lineHeight: '18px',
    margin: '0 0 5px'
  },
  footerBrand: {
    color: '#c0c0b9',
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
            <Text style={styles.brand}>FLOWBOARD</Text>
          </Section>
          <Section style={styles.content}>
            <Text style={styles.eyebrow}>{content.label}</Text>
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
                  {content.actionLabel} <span style={styles.actionArrow}>→</span>
                </Link>
              </Text>
            ) : null}
          </Section>
          <Hr style={styles.divider} />
          <Section style={styles.footer}>
            <Text style={styles.footerText}>You received this because something changed in your workspace.</Text>
            <Text style={styles.footerBrand}>Flowboard · Work, in view.</Text>
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
        label: 'Welcome',
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
        label: 'Board access',
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
        label: 'New comment',
        heading: safeLine(`${actorName} commented`),
        body: (
          <>
            <Text style={styles.paragraph}>on this task:</Text>
            {taskDetails(taskTitle, boardName)}
          </>
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
        label: 'Assignment',
        heading: safeLine(`${actorName} assigned a task`),
        greeting: `Hi ${recipientName},`,
        body: (
          <>
            <Text style={styles.paragraph}>You have a new task:</Text>
            {taskDetails(taskTitle, boardName)}
          </>
        ),
        actionURL: appURL,
        actionLabel: 'Open the task'
      };
    }
  }
}

function taskDetails(taskTitle: string, boardName: string | undefined): ReactElement {
  return (
    <Section style={styles.task}>
      <Text style={styles.taskTitle}>{taskTitle}</Text>
      {boardName ? <Text style={styles.taskMeta}>{boardName}</Text> : null}
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
