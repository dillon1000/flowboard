<script lang="ts">
  import type { SemesterPageContext, SemesterWeekContext } from '$lib/types';
  import { CalendarDotsIcon as CalendarDays, ClockIcon as Clock, WarningIcon as Warning } from 'phosphor-svelte';

  let { semester } = $props<{ semester: SemesterPageContext }>();
  const nextAssignments = $derived(semester.weeks.flatMap((week: SemesterWeekContext) => week.assignments).slice(0, 5));
  const openWeeks = $derived(semester.weeks.filter((week: SemesterWeekContext) => week.assignmentCount === 0).length);
</script>

<div class="page semester-page">
  <div class="semester-shell">
    <aside class="semester-overview-pane" aria-label="Semester overview">
      <header class="semester-header">
        <span class="semester-eyebrow">Academic plan</span>
        <h1>Semester horizon</h1>
        <p>{semester.rangeLabel}</p>
        <a class="button" href="/app"><CalendarDays size={15} />This week</a>
      </header>

      <dl class="semester-metrics" aria-label="Semester planning summary">
        <div><dt><CalendarDays size={14} />Deadlines</dt><dd>{semester.scheduledAssignmentCount}</dd></div>
        <div><dt><Warning size={14} />High-load weeks</dt><dd>{semester.highLoadWeekCount}</dd></div>
        <div><dt><Clock size={14} />Open weeks</dt><dd>{openWeeks}</dd></div>
      </dl>

      {#if semester.hasUndatedAssignments}
        <p class="semester-notice"><Warning size={15} /><span><strong>{semester.undatedAssignmentCount} without a due date</strong>These assignments stay outside the horizon until scheduled.</span></p>
      {/if}

      <section class="semester-next" aria-labelledby="semester-next-title">
        <div class="semester-section-heading"><h2 id="semester-next-title">Up next</h2><span>{nextAssignments.length}</span></div>
        {#if nextAssignments.length}<div class="semester-next-list">{#each nextAssignments as assignment}<a href={assignment.href}><span><span class={`study-course-dot ${assignment.courseColorClass}`} aria-hidden="true"></span>{assignment.courseName}</span><strong>{assignment.title}</strong><small>{assignment.dueLabel}</small></a>{/each}</div>{:else}<p>No scheduled deadlines yet.</p>{/if}
      </section>
    </aside>

    <main class="semester-main-pane">
      <header class="semester-main-header"><div><span class="semester-eyebrow">16-week view</span><h2>Week by week</h2></div><p>Deadlines and estimated effort across every course.</p></header>
      <section class="semester-timeline" aria-label="Sixteen-week assignment horizon">
        {#each semester.weeks as week}
          <article class:empty={!week.assignmentCount} class="semester-week" data-load={week.workloadClass}>
            <header><div><h3>{week.label}</h3><span>{week.assignmentCount ? `${week.assignmentCount} deadline${week.assignmentCount === 1 ? '' : 's'}` : 'No deadlines'}</span></div><strong>{week.workloadLabel}</strong></header>
            {#if week.assignmentCount}
              <div class="semester-assignments">
                {#each week.assignments as assignment}
                  <a class="semester-assignment" href={assignment.href}><span class="semester-assignment-course"><span class={`study-course-dot ${assignment.courseColorClass}`} aria-hidden="true"></span>{assignment.courseName}</span><strong>{assignment.title}</strong><span class="semester-assignment-meta"><span>{assignment.dueLabel}</span><span class:muted={!assignment.hasEstimate}><Clock size={13} />{assignment.effortLabel}</span></span></a>
                {/each}
              </div>
            {/if}
          </article>
        {/each}
      </section>
    </main>
  </div>
</div>
