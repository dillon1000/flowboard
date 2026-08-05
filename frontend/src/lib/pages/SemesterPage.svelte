<script lang="ts">
  import type { SemesterPageContext } from '$lib/types';
  import { CalendarDotsIcon as CalendarDays, ClockIcon as Clock, WarningIcon as Warning } from 'phosphor-svelte';

  let { semester } = $props<{ semester: SemesterPageContext }>();
</script>

<div class="page semester-page">
  <header class="page-header semester-header">
    <div class="page-title"><h1>Semester horizon</h1><p>{semester.rangeLabel}. This view shows saved deadlines and estimates across every course.</p></div>
    <div class="page-actions"><a class="button" href="/app"><CalendarDays size={15} />This week</a></div>
  </header>

  <section class="stats" aria-label="Semester planning summary">
    <div class="stat"><span><CalendarDays size={14} />Scheduled deadlines</span><strong>{semester.scheduledAssignmentCount}</strong></div>
    <div class="stat"><span><Warning size={14} />High-load weeks</span><strong>{semester.highLoadWeekCount}</strong></div>
    <div class="stat"><span><Clock size={14} />Need a due date</span><strong>{semester.undatedAssignmentCount}</strong></div>
  </section>

  {#if semester.hasUndatedAssignments}
    <p class="semester-notice"><Warning size={15} />{semester.undatedAssignmentCount} assignments have no due date, so they cannot appear in this horizon.</p>
  {/if}

  <section class="semester-timeline" aria-label="Sixteen-week assignment horizon">
    {#each semester.weeks as week}
      <article class="semester-week" data-load={week.workloadClass}>
        <header><div><h2>{week.label}</h2><span>{week.assignmentCount ? `${week.assignmentCount} deadline${week.assignmentCount === 1 ? '' : 's'}` : 'No deadlines'}</span></div><strong>{week.workloadLabel}</strong></header>
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
</div>
