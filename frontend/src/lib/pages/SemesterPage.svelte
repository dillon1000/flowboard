<script lang="ts">
  import type {
    SemesterAssignmentContext,
    SemesterPageContext,
    SemesterWeekContext,
  } from '$lib/types';
  import {
    ArrowCircleUpRightIcon as OpenAssignment,
    ArrowRightIcon as ArrowRight,
    CalendarDotsIcon as CalendarDays,
    ClockIcon as Clock,
    WarningIcon as Warning,
  } from 'phosphor-svelte';
  import { scrollFades } from '$lib/actions/scrollFades';
  import { durationLabel } from '$lib/ui/deadline';

  interface SemesterWeekView {
    week: SemesterWeekContext;
    index: number;
    number: number;
    plannedMinutes: number;
    unestimatedCount: number;
    barPercent: number;
  }

  let { semester } = $props<{ semester: SemesterPageContext }>();
  let weekNodes: HTMLElement[] = [];
  let scroller: HTMLElement | undefined = $state();
  let activeWeek = $state(0);

  const assignments: SemesterAssignmentContext[] = $derived(
    semester.weeks.flatMap((week: SemesterWeekContext) => week.assignments),
  );
  const nextAssignment = $derived(assignments[0]);
  const followingAssignments = $derived(assignments.slice(1, 4));
  const openWeeks = $derived(
    semester.weeks.filter((week: SemesterWeekContext) => week.assignmentCount === 0).length,
  );
  const estimatedCount = $derived(
    assignments.filter((assignment: SemesterAssignmentContext) => assignment.hasEstimate).length,
  );
  const plannedMinutes = $derived(
    assignments.reduce(
      (total: number, assignment: SemesterAssignmentContext) =>
        total + (assignment.estimatedMinutes ?? 0),
      0,
    ),
  );
  const plannedTime = $derived(durationLabel(plannedMinutes));

  // The ladder is the page's spine: one row per week, scaled against the
  // busiest week, so the shape of the term reads before any single deadline.
  const ladder = $derived.by<SemesterWeekView[]>(() => {
    const rows: SemesterWeekView[] = semester.weeks.map(
      (week: SemesterWeekContext, index: number) => ({
        week,
        index,
        number: index + 1,
        plannedMinutes: week.assignments.reduce(
          (total: number, assignment: SemesterAssignmentContext) =>
            total + (assignment.estimatedMinutes ?? 0),
          0,
        ),
        unestimatedCount: week.assignments.filter(
          (assignment: SemesterAssignmentContext) => !assignment.hasEstimate,
        ).length,
        barPercent: 0,
      }),
    );
    const busiest = Math.max(...rows.map((row) => row.plannedMinutes), 1);
    for (const row of rows) {
      if (row.week.assignmentCount === 0) continue;
      // Weeks that are still missing estimates carry no measured time, so they
      // get a fixed stub rather than a bar that reads as "nothing planned".
      row.barPercent =
        row.plannedMinutes === 0 ? 18 : Math.max(10, (row.plannedMinutes / busiest) * 100);
    }
    return rows;
  });

  $effect(() => {
    if (!scroller) return;
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          activeWeek = Number((entry.target as HTMLElement).dataset.week);
          return;
        }
      },
      { root: scroller, rootMargin: '0px 0px -78% 0px', threshold: 0 },
    );
    for (const node of weekNodes) {
      if (node) observer.observe(node);
    }
    return () => observer.disconnect();
  });

  function weekSummary(row: SemesterWeekView): string {
    if (row.week.assignmentCount === 0) return 'No deadlines';
    const deadlines = `${row.week.assignmentCount} deadline${row.week.assignmentCount === 1 ? '' : 's'}`;
    if (row.unestimatedCount > 0) return `${deadlines}, missing estimates`;
    return `${deadlines}, ${durationLabel(row.plannedMinutes)} planned`;
  }

  function goToWeek(index: number): void {
    activeWeek = index;
    weekNodes[index]?.scrollIntoView({
      block: 'start',
      behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth',
    });
  }
</script>

<div class="page semester-page">
  <div class="semester-planner">
    <aside class="semester-term-panel" aria-label="Term overview">
      <div class="semester-term-heading">
        <h1>Term</h1>
        <span>{semester.rangeLabel}</span>
      </div>

      <dl class="semester-term-stats">
        <div>
          <dt>Deadlines</dt>
          <dd>{semester.scheduledAssignmentCount}</dd>
        </div>
        <div>
          <dt>Planned</dt>
          <dd>{plannedTime}</dd>
        </div>
        <div>
          <dt>Open weeks</dt>
          <dd>{openWeeks}</dd>
        </div>
      </dl>

      <nav class="semester-ladder" aria-label="Jump to a week">
        {#each ladder as row (row.index)}
          <button
            class:active={activeWeek === row.index}
            class="semester-ladder-row"
            type="button"
            data-load={row.week.workloadClass}
            aria-current={activeWeek === row.index ? 'true' : undefined}
            onclick={() => goToWeek(row.index)}
          >
            <span class="semester-ladder-week">{row.number}</span>
            <span class="semester-ladder-label">{row.week.label}</span>
            <span class="semester-ladder-track" aria-hidden="true">
              <span class="semester-ladder-bar" style={`width: ${row.barPercent}%`}></span>
            </span>
            <span class="sr-only">{weekSummary(row)}</span>
          </button>
        {/each}
      </nav>

      <p class="semester-ladder-key">Bars show planned time. Striped bars still need estimates.</p>
    </aside>

    <section class="semester-term" aria-labelledby="semester-title">
      <header class="semester-term-header">
        <div class="semester-term-title">
          <h1 id="semester-title">Semester</h1>
          <p>Sixteen weeks of deadlines, from {semester.rangeLabel}.</p>
          <div class="semester-term-actions">
            <a class="button primary large" href="/app"><CalendarDays size={16} />This week</a>
            <a class="button large" href="/app/tasks">All assignments</a>
          </div>
        </div>

        <div class="semester-insights">
          {#if nextAssignment}
            <a class={`semester-next ${nextAssignment.courseColorClass}`} href={nextAssignment.href}>
              <h2>Next deadline</h2>
              <span class="semester-next-course">{nextAssignment.courseName}</span>
              <strong>{nextAssignment.title}</strong>
              <span class="semester-next-meta">
                <span><CalendarDays size={14} />{nextAssignment.dueLabel}</span>
                <span class:muted={!nextAssignment.hasEstimate}><Clock size={14} />{nextAssignment.effortLabel}</span>
                <OpenAssignment class="semester-next-open" size={15} aria-hidden="true" />
              </span>
            </a>
          {/if}

          {#if followingAssignments.length}
            <section class="semester-upcoming" aria-labelledby="semester-upcoming-title">
              <h2 id="semester-upcoming-title">Then</h2>
              <div class="semester-upcoming-list">
                {#each followingAssignments as assignment}
                  <a href={assignment.href}>
                    <span class={`semester-course-dot ${assignment.courseColorClass}`} aria-hidden="true"></span>
                    <strong>{assignment.title}</strong>
                    <small>{assignment.dueLabel}</small>
                  </a>
                {/each}
              </div>
            </section>
          {/if}
        </div>
      </header>

      <div class="semester-weeks" bind:this={scroller} aria-label="Week by week">
        {#each ladder as row (row.index)}
          <article
            class:empty={!row.week.assignmentCount}
            class:current={row.index === 0}
            class="semester-week"
            data-load={row.week.workloadClass}
            data-week={row.index}
            bind:this={weekNodes[row.index]}
          >
            <div class="semester-week-date">
              <span>Week {row.number}</span>
              <strong>{row.week.label}</strong>
              {#if row.index === 0}<small>This week</small>{/if}
            </div>

            <div class="semester-week-content">
              {#if row.week.assignmentCount}
                <div class="semester-assignment-scroller" use:scrollFades>
                  <div class="semester-assignment-track">
                    {#each row.week.assignments as assignment}
                      <a class={`semester-assignment ${assignment.courseColorClass}`} href={assignment.href}>
                        <span class="semester-assignment-course">{assignment.courseName}</span>
                        <strong title={assignment.title}>{assignment.title}</strong>
                        <span class="semester-assignment-meta">
                          <span><CalendarDays size={13} />{assignment.dueLabel}</span>
                          <span class:muted={!assignment.hasEstimate}><Clock size={13} />{assignment.effortLabel}</span>
                          <OpenAssignment class="semester-assignment-open" size={14} aria-hidden="true" />
                        </span>
                      </a>
                    {/each}
                  </div>
                </div>
              {:else}
                <span class="semester-no-assignments">No deadlines</span>
              {/if}
            </div>

            <span class="semester-week-load">{row.week.workloadLabel}</span>
          </article>
        {/each}
      </div>

      <footer class="semester-term-footer">
        {#if semester.hasUndatedAssignments}
          <a href="/app/tasks">
            <Warning size={15} />{semester.undatedAssignmentCount} assignments have no due date, so they are missing here<ArrowRight size={14} />
          </a>
        {:else if estimatedCount < assignments.length}
          <a href="/app/tasks">
            <Clock size={15} />{assignments.length - estimatedCount} deadlines still need a time estimate<ArrowRight size={14} />
          </a>
        {:else}
          <span><CalendarDays size={15} />Every scheduled assignment is on the term map</span>
        {/if}
      </footer>
    </section>
  </div>
</div>
