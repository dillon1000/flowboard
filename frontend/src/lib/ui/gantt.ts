import type { TaskCardContext } from '$lib/types';

export type GanttTaskDates = Pick<TaskCardContext, 'startInput' | 'dueInput'>;

export interface GanttSegment {
  label: string;
  offsetDays: number;
  spanDays: number;
}

export interface GanttScale {
  startInput: string;
  endInput: string;
  startDay: number;
  dayCount: number;
  months: GanttSegment[];
  weeks: GanttSegment[];
  todayOffset: number | null;
}

export interface GanttPlacement {
  offsetDays: number;
  spanDays: number;
  isMilestone: boolean;
}

const dayMilliseconds = 86_400_000;
const minimumDayCount = 28;
const monthFormat = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  year: 'numeric',
  timeZone: 'UTC'
});
const weekFormat = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  timeZone: 'UTC'
});

/**
 * Builds one Sunday-to-Saturday scale for the course. The scale includes every
 * saved-view assignment and stays stable while temporary filters hide rows.
 * An empty course opens on four weeks around the current UTC day.
 */
export function buildGanttScale(tasks: readonly GanttTaskDates[], now = new Date()): GanttScale {
  const datedDays = tasks.flatMap((task) => [inputDay(task.startInput), inputDay(task.dueInput)])
    .filter((day): day is number => day !== null);
  const today = utcDay(now);
  const firstDatedDay = datedDays.length ? Math.min(...datedDays) : today;
  const lastDatedDay = datedDays.length ? Math.max(...datedDays) : today;
  const startDay = startOfWeek(firstDatedDay);
  const naturalEndDay = endOfWeek(lastDatedDay);
  const endDay = Math.max(naturalEndDay, startDay + minimumDayCount - 1);
  const dayCount = endDay - startDay + 1;
  const todayOffset = today >= startDay && today <= endDay ? today - startDay : null;

  return {
    startInput: dayInput(startDay),
    endInput: dayInput(endDay),
    startDay,
    dayCount,
    months: monthSegments(startDay, dayCount),
    weeks: weekSegments(startDay, dayCount),
    todayOffset
  };
}

/** Returns the task bar on a scale, or null when neither planning date is set. */
export function ganttPlacement(task: GanttTaskDates, scale: GanttScale): GanttPlacement | null {
  const start = inputDay(task.startInput);
  const due = inputDay(task.dueInput);
  if (start === null && due === null) return null;

  const firstDay = Math.min(start ?? due ?? scale.startDay, due ?? start ?? scale.startDay);
  const lastDay = Math.max(start ?? due ?? scale.startDay, due ?? start ?? scale.startDay);
  return {
    offsetDays: firstDay - scale.startDay,
    spanDays: lastDay - firstDay + 1,
    isMilestone: start === null && due !== null
  };
}

function monthSegments(startDay: number, dayCount: number): GanttSegment[] {
  const segments: GanttSegment[] = [];
  for (let offset = 0; offset < dayCount; offset += 1) {
    const label = monthFormat.format(dayDate(startDay + offset));
    const current = segments.at(-1);
    if (current?.label === label) current.spanDays += 1;
    else segments.push({ label, offsetDays: offset, spanDays: 1 });
  }
  return segments;
}

function weekSegments(startDay: number, dayCount: number): GanttSegment[] {
  const segments: GanttSegment[] = [];
  for (let offset = 0; offset < dayCount; offset += 7) {
    segments.push({
      label: weekFormat.format(dayDate(startDay + offset)),
      offsetDays: offset,
      spanDays: Math.min(7, dayCount - offset)
    });
  }
  return segments;
}

function inputDay(value: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const [year, month, day] = value.split('-').map(Number);
  const timestamp = Date.UTC(year, month - 1, day);
  const parsed = new Date(timestamp);
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) return null;
  return Math.floor(timestamp / dayMilliseconds);
}

function utcDay(date: Date): number {
  return Math.floor(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()) / dayMilliseconds);
}

function startOfWeek(day: number): number {
  return day - dayDate(day).getUTCDay();
}

function endOfWeek(day: number): number {
  return day + (6 - dayDate(day).getUTCDay());
}

function dayDate(day: number): Date {
  return new Date(day * dayMilliseconds);
}

function dayInput(day: number): string {
  return dayDate(day).toISOString().slice(0, 10);
}
