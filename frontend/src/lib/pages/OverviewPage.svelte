<script lang="ts">
  import { invalidateAll } from '$app/navigation';
  import { api, messageFor } from '$lib/api';
  import type { OverviewPageContext, TaskResponse } from '$lib/types';
  import { CalendarDays, CheckSquare, ChevronDown, Clock3, FileText, Info, Layers, Plus, X } from '@lucide/svelte';
  import CreateBoardDialog from '$lib/components/CreateBoardDialog.svelte';
  import { dialogLayer } from '$lib/actions/dialogLayer';

  let { overview } = $props<{ overview: OverviewPageContext }>();
  let createBoardOpen = $state(false);
  let createTaskOpen = $state(false);
  let pending = $state(false);
  let requestError = $state('');

  async function createAssignment(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    const dueDate = String(data.get('dueAt') ?? '');
    pending = true;
    requestError = '';
    try {
      await api<TaskResponse>('/api/v1/tasks', {
        method: 'POST',
        body: JSON.stringify({
          boardID: String(data.get('boardID') ?? overview.defaultCourseID),
          title: String(data.get('title') ?? ''),
          description: String(data.get('description') ?? '') || null,
          labels: String(data.get('labels') ?? '').split(',').map((label) => label.trim()).filter(Boolean).slice(0, 6),
          dueAt: dueDate ? `${dueDate}T00:00:00Z` : null
        })
      });
      form.reset();
      createTaskOpen = false;
      await invalidateAll();
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pending = false;
    }
  }
</script>

<div class="page study-page">
  <div class="study-planner">
    <aside class="study-course-panel" aria-label="Course filters">
      <div class="study-course-heading">
        <h1>Courses</h1>
        <button class="icon-button" type="button" aria-label="Add course" title="Add course" onclick={() => (createBoardOpen = true)}><Plus size={16} /></button>
      </div>
      <nav class="study-course-list" aria-label="Courses">
        <a class:active={overview.isAllCoursesSelected} class="study-course-link" href="/app" aria-current={overview.isAllCoursesSelected ? 'page' : undefined}>
          <Layers size={16} /><span>All courses</span>
        </a>
        {#each overview.courseFilters as course (course.id)}
          <a class:active={course.isSelected} class="study-course-link" href={course.href} aria-current={course.isSelected ? 'page' : undefined}>
            <span class={`study-course-dot ${course.colorClass}`} aria-hidden="true"></span><span>{course.name}</span>
          </a>
        {/each}
      </nav>
    </aside>

    <section class="study-week" aria-labelledby="study-week-title">
      <header class="study-week-header">
        <div class="study-week-title">
          <h1 id="study-week-title">This week</h1>
          <p>{overview.weekLabel}</p>
          <div class="study-week-actions">
            <a class="button primary large" href="/app/tasks"><CalendarDays size={16} />Plan this week</a>
            <button class="button large" type="button" disabled={!overview.hasCourses} onclick={() => (createTaskOpen = true)}><Plus size={16} />Add assignment</button>
          </div>
        </div>

        <section class="study-workload" aria-labelledby="study-workload-title">
          <div class="study-workload-chart">
            <h2 id="study-workload-title">Workload <Info size={13} /></h2>
            <div class="study-workload-bars">
              {#each overview.workloadDays as day}
                <span class="study-workload-column"><span class={`study-workload-bar ${day.barClass}`} role="img" aria-label={day.accessibilityLabel}></span><span>{day.dayLabel}</span></span>
              {/each}
            </div>
          </div>
          <div class="study-workload-summary"><strong>{overview.balanceName}</strong><span>{overview.balanceDescription}</span></div>
        </section>
      </header>

      <div class="study-days" aria-label={`Assignments due ${overview.weekLabel}`}>
        {#each overview.days as day}
          <section class:today={day.isToday} class="study-day">
            <div class="study-day-date"><span>{day.weekdayLabel}</span><strong>{day.dateLabel}</strong>{#if day.isToday}<small>Today</small>{/if}</div>
            <div class="study-day-content">
              {#if day.hasAssignments}
                {#each day.assignments as assignment}
                  <a class="study-assignment" href={assignment.href}>
                    <span class="study-assignment-main"><span class="study-assignment-course"><span class={`study-course-dot ${assignment.courseColorClass}`} aria-hidden="true"></span>{assignment.courseName}</span><strong>{assignment.title}</strong></span>
                    <span class="study-assignment-meta"><span>{assignment.dueTime}</span><small>Due</small></span>
                    <span class="study-assignment-type"><FileText size={15} />{assignment.typeName}</span>
                    <span class="study-assignment-meta"><span><Clock3 size={13} />{assignment.effortLabel}</span><small>Est. effort</small></span>
                  </a>
                {/each}
              {:else}
                <span class="study-no-assignments">No assignments</span>
              {/if}
            </div>
            <span class={`study-day-load ${day.workloadClass}`}><span class="study-day-load-label"><span class="study-course-dot" aria-hidden="true"></span>{day.workloadLabel}</span><ChevronDown size={14} aria-hidden="true" /></span>
          </section>
        {/each}
      </div>

      <footer class="study-week-footer">
        {#if overview.hasUnscheduledAssignments}
          <a href="/app/tasks"><CalendarDays size={15} />{overview.unscheduledAssignmentCount} assignments still need a due date</a>
        {:else}
          <span><CalendarDays size={15} />Date-only deadlines appear as 11:59 PM</span>
        {/if}
      </footer>
    </section>
  </div>
</div>

<CreateBoardDialog bind:open={createBoardOpen} />

{#if createTaskOpen}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="new-assignment-title" tabindex="-1" use:dialogLayer={{ close: () => (createTaskOpen = false) }}>
    <form class="dialog wide" onsubmit={createAssignment}>
      <div class="dialog-header"><div><h2 id="new-assignment-title">Add assignment</h2><p>Put the deadline on your week, then add details when you need them.</p></div><button class="icon-button" type="button" onclick={() => (createTaskOpen = false)} aria-label="Close"><X size={16} /></button></div>
      <div class="dialog-body">
        {#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}
        <div class="form-grid">
          <div class="field wide"><label for="assignment-title">Title</label><input class="input" id="assignment-title" name="title" maxlength="120" required data-dialog-focus /></div>
          <div class="field"><label for="assignment-course">Course</label><select class="input" id="assignment-course" name="boardID" value={overview.defaultCourseID}>{#each overview.courseFilters as course}<option value={course.id}>{course.name}</option>{/each}</select></div>
          <div class="field"><label for="assignment-due">Due date</label><input class="input" id="assignment-due" type="date" name="dueAt" /></div>
          <div class="field wide"><label for="assignment-description">Notes</label><textarea class="textarea" id="assignment-description" name="description" maxlength="2000"></textarea></div>
          <div class="field wide"><label for="assignment-labels">Type</label><input class="input" id="assignment-labels" name="labels" placeholder="Lab report, Reading, Discussion" /></div>
        </div>
      </div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (createTaskOpen = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>{pending ? 'Adding…' : 'Add assignment'}</button></div>
    </form>
  </div>
{/if}
