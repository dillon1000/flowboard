/**
 * Deadlines on the course page are read as distance, not as dates: a student
 * needs "two days" faster than "Aug 7, 2026". Every course view shares this
 * countdown so an assignment reads the same in a lane, a row, or a brief.
 *
 * Dates arrive as UTC calendar days from the backend, so today is measured in
 * UTC too. That keeps the server render and the client hydration agreeing on
 * the same day, and matches the dates the rest of the app already prints.
 */

export type DeadlineTone = 'none' | 'overdue' | 'today' | 'soon' | 'later';

export interface Deadline {
  /** Compact form for cards and chips: `3d late`, `Today`, `Tue`, `Aug 9`. */
  short: string;
  /** Spoken form for rows, titles, and screen readers. */
  long: string;
  tone: DeadlineTone;
  /** Whole days from today. Negative is overdue. */
  days: number;
}

const NO_DEADLINE: Deadline = {
  short: '—',
  long: 'No due date',
  tone: 'none',
  days: Number.POSITIVE_INFINITY
};

const weekdayFormat = new Intl.DateTimeFormat('en-US', { weekday: 'short', timeZone: 'UTC' });
const monthDayFormat = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  timeZone: 'UTC'
});

export function deadlineFrom(dueInput: string): Deadline {
  if (!dueInput) return NO_DEADLINE;
  const due = Date.parse(`${dueInput}T00:00:00Z`);
  if (Number.isNaN(due)) return NO_DEADLINE;

  const days = Math.round((due - startOfTodayUTC()) / 86_400_000);
  if (days < 0) {
    const late = Math.abs(days);
    return {
      short: `${late}d late`,
      long: late === 1 ? '1 day late' : `${late} days late`,
      tone: 'overdue',
      days
    };
  }
  if (days === 0) return { short: 'Today', long: 'Due today', tone: 'today', days };
  if (days === 1) return { short: 'Tomorrow', long: 'Due tomorrow', tone: 'soon', days };
  if (days < 7) {
    const weekday = weekdayFormat.format(due);
    return { short: weekday, long: `Due ${weekday}, in ${days} days`, tone: 'soon', days };
  }
  const date = monthDayFormat.format(due);
  return { short: date, long: `Due ${date}`, tone: 'later', days };
}

/** Minutes of estimated work, printed the way the backend prints an estimate. */
export function durationLabel(minutes: number): string {
  if (minutes <= 0) return '—';
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const remainder = minutes % 60;
  return remainder === 0 ? `${hours}h` : `${hours}h ${remainder}m`;
}

function startOfTodayUTC(): number {
  const now = new Date();
  return Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
}
