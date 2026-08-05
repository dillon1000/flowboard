<script lang="ts">
  import type {
    SemesterAssignmentContext,
    SemesterPageContext,
    SemesterWeekContext,
  } from '$lib/types';
  import {
    ArrowRightIcon as ArrowRight,
    CalendarDotsIcon as CalendarDays,
    ClockIcon as Clock,
    WarningIcon as Warning,
  } from 'phosphor-svelte';

  let { semester } = $props<{ semester: SemesterPageContext }>();

  const assignments: SemesterAssignmentContext[] = $derived(
    semester.weeks.flatMap((week: SemesterWeekContext) => week.assignments),
  );
  const nextAssignment = $derived(assignments[0]);
  const followingAssignments = $derived(assignments.slice(1, 5));
  const openWeeks = $derived(
    semester.weeks.filter((week: SemesterWeekContext) => week.assignmentCount === 0).length,
  );
  const estimatedCount = $derived(
    assignments.filter((assignment) => assignment.hasEstimate).length,
  );
  const plannedMinutes = $derived(
    assignments.reduce((total, assignment) => total + (assignment.estimatedMinutes ?? 0), 0),
  );
  const plannedTime = $derived(
    plannedMinutes === 0
      ? '—'
      : plannedMinutes < 60
        ? `${plannedMinutes}m`
        : plannedMinutes % 60 === 0
          ? `${plannedMinutes / 60}h`
          : `${Math.floor(plannedMinutes / 60)}h ${plannedMinutes % 60}m`,
  );
</script>

<div class="page semester-page">
  <header class="semester-page-header">
    <div>
      <span class="semester-eyebrow">Academic plan · {semester.rangeLabel}</span>
      <h1>Semester horizon</h1>
      <p>See where deadlines cluster, where work is missing estimates, and where you have room.</p>
    </div>
    <a class="button semester-week-button" href="/app"><CalendarDays size={16} />This week</a>
  </header>

  <dl class="semester-summary" aria-label="Semester planning summary">
    <div>
      <dt>Deadlines</dt>
      <dd>{semester.scheduledAssignmentCount}</dd>
      <span>Across every course</span>
    </div>
    <div>
      <dt>Planned time</dt>
      <dd>{plannedTime}</dd>
      <span>{estimatedCount} of {assignments.length} estimated</span>
    </div>
    <div>
      <dt>Open weeks</dt>
      <dd>{openWeeks}</dd>
      <span>{semester.highLoadWeekCount} high-load {semester.highLoadWeekCount === 1 ? 'week' : 'weeks'}</span>
    </div>
  </dl>

  <div class="semester-workspace">
    <main class="semester-main-pane">
      <header class="semester-section-header">
        <div>
          <span class="semester-eyebrow">Term map</span>
          <h2>Week by week</h2>
        </div>
        <p>Deadlines and estimated effort across every course.</p>
      </header>

      <section class="semester-timeline" aria-label="Sixteen-week assignment horizon">
        {#each semester.weeks as week}
          <article class:empty={!week.assignmentCount} class="semester-week" data-load={week.workloadClass}>
            <header class="semester-week-label">
              <span class="semester-week-marker" aria-hidden="true"></span>
              <div>
                <h3>{week.label}</h3>
                <span>{week.assignmentCount ? `${week.assignmentCount} deadline${week.assignmentCount === 1 ? '' : 's'}` : 'Open week'}</span>
              </div>
            </header>

            <div class="semester-week-content">
              {#if week.assignmentCount}
                <div class="semester-assignments">
                  {#each week.assignments as assignment}
                    <a class="semester-assignment" href={assignment.href}>
                      <span class="semester-assignment-course"><span class={`study-course-dot ${assignment.courseColorClass}`} aria-hidden="true"></span>{assignment.courseName}</span>
                      <strong>{assignment.title}</strong>
                      <span class="semester-assignment-meta">
                        <span>{assignment.dueLabel}</span>
                        <span class:muted={!assignment.hasEstimate}><Clock size={13} />{assignment.effortLabel}</span>
                      </span>
                    </a>
                  {/each}
                </div>
              {:else}
                <span class="semester-open-week">No deadlines scheduled</span>
              {/if}
            </div>

            <strong class="semester-workload-label">{week.workloadLabel}</strong>
          </article>
        {/each}
      </section>
    </main>

    <aside class="semester-planning-rail" aria-label="Semester planning details">
      {#if nextAssignment}
        <section class="semester-focus-card">
          <span class="semester-eyebrow">Next deadline</span>
          <span class="semester-focus-course"><span class={`study-course-dot ${nextAssignment.courseColorClass}`} aria-hidden="true"></span>{nextAssignment.courseName}</span>
          <h2>{nextAssignment.title}</h2>
          <div class="semester-focus-meta">
            <span><CalendarDays size={15} />{nextAssignment.dueLabel}</span>
            <span><Clock size={15} />{nextAssignment.effortLabel}</span>
          </div>
          <a href={nextAssignment.href}>Open assignment <ArrowRight size={15} /></a>
        </section>
      {/if}

      {#if followingAssignments.length}
        <section class="semester-upcoming" aria-labelledby="semester-upcoming-title">
          <div class="semester-rail-heading">
            <h2 id="semester-upcoming-title">Coming up</h2>
            <span>{followingAssignments.length}</span>
          </div>
          <div class="semester-upcoming-list">
            {#each followingAssignments as assignment}
              <a href={assignment.href}>
                <span class="semester-upcoming-course"><span class={`study-course-dot ${assignment.courseColorClass}`} aria-hidden="true"></span>{assignment.courseName}</span>
                <strong>{assignment.title}</strong>
                <small>{assignment.dueLabel}</small>
              </a>
            {/each}
          </div>
        </section>
      {/if}

      {#if semester.hasUndatedAssignments}
        <a class="semester-notice" href="/app/tasks">
          <Warning size={16} />
          <span><strong>{semester.undatedAssignmentCount} without a due date</strong>Schedule {semester.undatedAssignmentCount === 1 ? 'it' : 'them'} so {semester.undatedAssignmentCount === 1 ? 'it appears' : 'they appear'} in the term map.</span>
          <ArrowRight size={15} />
        </a>
      {/if}
    </aside>
  </div>
</div>
