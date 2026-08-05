import { describe, expect, it } from 'vitest';
import { buildGanttScale, ganttPlacement, type GanttTaskDates } from './gantt';

const undated: GanttTaskDates = { startInput: '', dueInput: '' };

describe('buildGanttScale', () => {
  it('opens an empty course on four complete weeks', () => {
    const scale = buildGanttScale([], new Date('2026-08-05T12:00:00Z'));

    expect(scale.startInput).toBe('2026-08-02');
    expect(scale.endInput).toBe('2026-08-29');
    expect(scale.dayCount).toBe(28);
    expect(scale.todayOffset).toBe(3);
    expect(scale.months).toEqual([{ label: 'Aug 2026', offsetDays: 0, spanDays: 28 }]);
    expect(scale.weeks.map((week) => week.label)).toEqual(['Aug 2', 'Aug 9', 'Aug 16', 'Aug 23']);
  });

  it('covers every dated assignment with full boundary weeks', () => {
    const tasks: GanttTaskDates[] = [
      { startInput: '2026-07-30', dueInput: '2026-08-04' },
      { startInput: '', dueInput: '2026-08-18' }
    ];
    const scale = buildGanttScale(tasks, new Date('2026-08-05T12:00:00Z'));

    expect(scale.startInput).toBe('2026-07-26');
    expect(scale.endInput).toBe('2026-08-22');
    expect(scale.months).toEqual([
      { label: 'Jul 2026', offsetDays: 0, spanDays: 6 },
      { label: 'Aug 2026', offsetDays: 6, spanDays: 22 }
    ]);
  });
});

describe('ganttPlacement', () => {
  const scale = buildGanttScale(
    [{ startInput: '2026-07-30', dueInput: '2026-08-04' }],
    new Date('2026-08-05T12:00:00Z')
  );

  it('places an assignment across each inclusive planning day', () => {
    expect(ganttPlacement({ startInput: '2026-07-30', dueInput: '2026-08-04' }, scale)).toEqual({
      offsetDays: 4,
      spanDays: 6,
      isMilestone: false
    });
  });

  it('uses a due-only assignment as a milestone', () => {
    expect(ganttPlacement({ startInput: '', dueInput: '2026-08-18' }, scale)).toEqual({
      offsetDays: 23,
      spanDays: 1,
      isMilestone: true
    });
  });

  it('normalizes dates entered in reverse order', () => {
    expect(ganttPlacement({ startInput: '2026-08-04', dueInput: '2026-07-30' }, scale)).toEqual({
      offsetDays: 4,
      spanDays: 6,
      isMilestone: false
    });
  });

  it('leaves undated assignments unscheduled', () => {
    expect(ganttPlacement(undated, scale)).toBeNull();
  });
});
