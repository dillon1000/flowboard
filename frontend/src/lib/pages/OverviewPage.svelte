<script lang="ts">
  import { invalidateAll } from '$app/navigation';
  import { api, messageFor } from '$lib/api';
  import type { OverviewPageContext, StudyCourseContext, StudyDayContext, StudyPlanCandidateContext, TaskResponse } from '$lib/types';
  import { ArrowCircleUpRightIcon as OpenAssignment, CalendarDotsIcon as CalendarDays, ClockIcon as Clock3, FileTextIcon as FileText, MinusIcon as Minus, PlusIcon as Plus, StackIcon as Layers, StrategyIcon as Strategy, XIcon as X } from 'phosphor-svelte';
  import CreateBoardDialog from '$lib/components/CreateBoardDialog.svelte';
  import { dialogLayer } from '$lib/actions/dialogLayer';
  import { previewFromAssignment, taskPreview } from '$lib/ui/taskPreview';
  import { showToast } from '$lib/ui/toast';
  import DatePicker from '$lib/components/DatePicker.svelte';
  import TimePicker from '$lib/components/TimePicker.svelte';
  import SelectMenu, { type SelectMenuOption } from '$lib/components/SelectMenu.svelte';
  import { scrollFades } from '$lib/actions/scrollFades';
  import { onMount } from 'svelte';

  const workloadPreferenceKey = 'flowboard-workload-preferences';

  let { overview } = $props<{ overview: OverviewPageContext }>();
  let createBoardOpen = $state(false);
  let createTaskOpen = $state(false);
  let planOpen = $state(false);
  let planSelection = $state('');
  let pending = $state(false);
  let requestError = $state('');
  let expandedDays = $state<Record<string, boolean>>({});
  let limitsOpen = $state(false);
  let balancedMinutes = $state(120);
  let heavyMinutes = $state(240);
  const courseOptions = $derived<SelectMenuOption[]>(
    overview.courseFilters.map((course: StudyCourseContext) => ({ value: course.id, label: course.name }))
  );
  const planOptions = $derived<SelectMenuOption[]>(
    overview.planCandidates.map((assignment: StudyPlanCandidateContext) => ({
      value: assignment.id,
      label: `${assignment.title} - ${assignment.courseName}`
    }))
  );
  const deadlineCount = $derived(
    overview.days.reduce((total: number, day: StudyDayContext) => total + day.assignmentCount, 0)
  );
  const plannedMinutes = $derived(
    overview.days.reduce((total: number, day: StudyDayContext) => total + day.workloadMinutes, 0)
  );
  const busiestDay = $derived.by<StudyDayContext | null>(() => {
    let busiest: StudyDayContext | null = null;
    for (const day of overview.days as StudyDayContext[]) {
      if (!busiest || day.workloadMinutes > busiest.workloadMinutes) busiest = day;
    }
    return busiest && busiest.workloadMinutes > 0 ? busiest : null;
  });
  // One sentence carries the week's shape. The seven rows below already draw
  // the workload, so the header states only what the rows cannot: the verdict.
  const weekState = $derived.by(() => {
    if (overview.hasUnestimatedAssignments) {
      return `${overview.unestimatedAssignmentCount} ${overview.unestimatedAssignmentCount === 1 ? 'assignment is' : 'assignments are'} missing a time estimate, so this week is not fully counted.`;
    }
    if (!busiestDay) return 'Nothing is planned yet. Add an estimate to an assignment to see the week fill in.';
    const peak = `${busiestDay.weekdayLabel} at ${durationLabel(busiestDay.workloadMinutes)}`;
    if (busiestDay.workloadMinutes >= heavyMinutes) return `A heavy week. Your busiest day is ${peak} — move work off it if you can.`;
    if (busiestDay.workloadMinutes >= balancedMinutes) return `A balanced week. Your busiest day is ${peak}.`;
    return `A light week. Your busiest day is only ${peak}, so there is room to work ahead.`;
  });
  const unplannedPreview = $derived<StudyPlanCandidateContext[]>(overview.planCandidates.slice(0, 3));

  onMount(() => {
    const saved = localStorage.getItem(workloadPreferenceKey);
    if (!saved) return;
    try {
      const preferences: unknown = JSON.parse(saved);
      if (!preferences || typeof preferences !== 'object') return;
      const values = preferences as { balancedMinutes?: unknown; heavyMinutes?: unknown };
      if (typeof values.balancedMinutes === 'number' && typeof values.heavyMinutes === 'number' && values.balancedMinutes >= 30 && values.heavyMinutes > values.balancedMinutes) {
        balancedMinutes = values.balancedMinutes;
        heavyMinutes = values.heavyMinutes;
      }
    } catch {
      localStorage.removeItem(workloadPreferenceKey);
    }
  });

  function durationLabel(minutes: number): string {
    if (minutes === 0) return '—';
    if (minutes < 60) return `${minutes}m`;
    const hours = Math.floor(minutes / 60);
    const remainder = minutes % 60;
    return remainder === 0 ? `${hours}h` : `${hours}h ${remainder}m`;
  }

  function estimateMinutes(value: FormDataEntryValue | null): number | null {
    const minutes = Number(value);
    return Number.isInteger(minutes) && minutes > 0 ? minutes : null;
  }

  function toggleDay(dateLabel: string): void {
    const update = () => {
      expandedDays[dateLabel] = expandedDays[dateLabel] === false;
    };
    const transitionDocument = document as Document & {
      startViewTransition?: (callback: () => void) => unknown;
    };

    // A view transition moves the surrounding day rows on the compositor. The
    // state still changes immediately on unsupported or reduced-motion clients.
    if (matchMedia('(prefers-reduced-motion: reduce)').matches || !transitionDocument.startViewTransition) {
      update();
      return;
    }
    transitionDocument.startViewTransition(update);
  }

  function loadClass(day: StudyDayContext): string {
    if (day.unestimatedAssignmentCount > 0) return 'needs-estimates';
    if (day.workloadMinutes >= heavyMinutes) return 'high';
    if (day.workloadMinutes > 0) return 'planned';
    return 'empty';
  }

  function loadLabel(day: StudyDayContext): string {
    if (day.unestimatedAssignmentCount > 0) return 'Needs estimates';
    if (day.workloadMinutes >= heavyMinutes) return 'Heavy';
    if (day.workloadMinutes >= balancedMinutes) return 'Balanced';
    return day.workloadMinutes > 0 ? 'Light' : 'Open';
  }

  // Each row's bar is measured against the heavy limit, so the seven gutters
  // stack into a chart of the week without a second chart anywhere on the page.
  function loadPercent(day: StudyDayContext): number {
    if (day.workloadMinutes === 0) return day.unestimatedAssignmentCount > 0 ? 22 : 0;
    return Math.max(8, Math.min(100, (day.workloadMinutes / heavyMinutes) * 100));
  }

  function openPlan(assignmentID: string): void {
    planSelection = assignmentID;
    planOpen = true;
  }

  function saveWorkloadPreferences(event: SubmitEvent): void {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const nextBalanced = Number(data.get('balancedMinutes'));
    const nextHeavy = Number(data.get('heavyMinutes'));
    if (!Number.isInteger(nextBalanced) || !Number.isInteger(nextHeavy) || nextBalanced < 30 || nextHeavy <= nextBalanced) {
      requestError = 'Set a heavy limit that is higher than the balanced limit.';
      return;
    }
    balancedMinutes = nextBalanced;
    heavyMinutes = nextHeavy;
    localStorage.setItem(workloadPreferenceKey, JSON.stringify({ balancedMinutes, heavyMinutes }));
    limitsOpen = false;
    requestError = '';
    showToast('Daily limits saved');
  }

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
          dueAt: dueDate ? `${dueDate}T00:00:00Z` : null,
          dueTime: dueDate ? String(data.get('dueTime') ?? '') || null : null,
          estimatedMinutes: estimateMinutes(data.get('estimatedMinutes'))
        })
      });
      form.reset();
      createTaskOpen = false;
      await invalidateAll();
      showToast('Assignment added');
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pending = false;
    }
  }

  async function planAssignment(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const taskID = String(data.get('taskID') ?? '');
    const focusDate = String(data.get('focusDate') ?? '');
    if (!taskID || !focusDate) return;
    pending = true;
    requestError = '';
    try {
      await api(`/api/v1/tasks/${taskID}`, {
        method: 'PATCH',
        body: JSON.stringify({ startAt: `${focusDate}T00:00:00Z` })
      });
      planOpen = false;
      await invalidateAll();
      showToast('Work day added');
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pending = false;
    }
  }
</script>

<div class="page study-page">
  <div class="study-planner">
    <aside class="study-course-panel" aria-label="This week and courses">
      <div class="study-panel-heading">
        <h1>Week</h1>
        <span>{overview.weekLabel}</span>
      </div>

      <dl class="study-week-stats">
        <div>
          <dt>Due</dt>
          <dd>{deadlineCount}</dd>
        </div>
        <div>
          <dt>Planned</dt>
          <dd>{durationLabel(plannedMinutes)}</dd>
        </div>
        <div>
          <dt>Streak</dt>
          <dd>{overview.studyStreakDays}d</dd>
        </div>
      </dl>

      <div class="study-course-heading">
        <h2>Courses</h2>
        <button class="icon-button" type="button" aria-label="Add course" title="Add course" onclick={() => (createBoardOpen = true)}><Plus size={16} /></button>
      </div>
      <nav class="study-course-list" aria-label="Courses">
        <a class:active={overview.isAllCoursesSelected} class="study-course-link" href="/app" aria-current={overview.isAllCoursesSelected ? 'page' : undefined}>
          <Layers size={16} /><span>All courses</span>
        </a>
        {#each overview.courseFilters as course (course.id)}
          <a class:active={course.isSelected} class="study-course-link" href={course.href} aria-current={course.isSelected ? 'page' : undefined}>
            <span class={`study-course-accent ${course.colorClass}`} aria-hidden="true"></span><span>{course.name}</span><small class:muted={!course.hasGrade}>{course.gradeDisplay}</small>
          </a>
        {/each}
      </nav>

      <div class="study-limits">
        {#if limitsOpen}
          <form class="study-limits-form" onsubmit={saveWorkloadPreferences}>
            <p>A day counts as heavy once its estimates pass the heavy limit.</p>
            <label>
              <span>Balanced</span>
              <span class="study-limits-input"><input class="input" name="balancedMinutes" type="number" min="30" max="1380" step="15" value={balancedMinutes} required /><small>min</small></span>
            </label>
            <label>
              <span>Heavy</span>
              <span class="study-limits-input"><input class="input" name="heavyMinutes" type="number" min="45" max="1440" step="15" value={heavyMinutes} required /><small>min</small></span>
            </label>
            <div class="study-limits-actions">
              <button class="button small" type="button" onclick={() => (limitsOpen = false)}>Cancel</button>
              <button class="button primary small" type="submit">Save limits</button>
            </div>
          </form>
        {:else}
          <button class="study-limits-toggle" type="button" aria-expanded="false" onclick={() => (limitsOpen = true)}>
            <span>Heavy above {durationLabel(heavyMinutes)} a day</span>
            <small>Change</small>
          </button>
        {/if}
      </div>
    </aside>

    <section class="study-week" aria-labelledby="study-week-title">
      <header class="study-week-header">
        <div class="study-week-title">
          <h1 id="study-week-title">This week</h1>
          <p>{weekState}</p>
          <div class="study-week-actions">
            <button class="button primary large" type="button" disabled={!overview.hasPlanCandidates} onclick={() => openPlan(overview.planCandidates[0]?.id ?? '')}><Strategy size={16} />Plan this week</button>
            <button class="button large" type="button" disabled={!overview.hasCourses} onclick={() => (createTaskOpen = true)}><Plus size={16} />Add assignment</button>
          </div>
        </div>

        <section class="study-unplanned" aria-labelledby="study-unplanned-title">
          <h2 id="study-unplanned-title">Needs a work day</h2>
          {#if unplannedPreview.length}
            <div class="study-unplanned-list">
              {#each unplannedPreview as assignment (assignment.id)}
                <button type="button" onclick={() => openPlan(assignment.id)}>
                  <strong>{assignment.title}</strong>
                  <small>{assignment.courseName} · {assignment.dueDisplay}</small>
                </button>
              {/each}
            </div>
            {#if overview.planCandidates.length > unplannedPreview.length}
              <span class="study-unplanned-rest">{overview.planCandidates.length - unplannedPreview.length} more waiting</span>
            {/if}
          {:else}
            <p class="study-unplanned-empty">Every assignment has a day to work on it.</p>
          {/if}
        </section>
      </header>

      <div class="study-days" aria-label={`Assignments due ${overview.weekLabel}`}>
        {#each overview.days as day, index}
          <section class:today={day.isToday} class:collapsed={expandedDays[day.dateLabel] === false} class="study-day" data-load={loadClass(day)} style={`view-transition-name: study-day-${index}`}>
            <div class="study-day-date">
              <span class="study-day-weekday">{day.weekdayLabel}</span>
              <strong>{day.dateLabel}</strong>
              {#if day.isToday}<small>Today</small>{/if}
              <span class="study-day-load" title={`${loadLabel(day)} · ${durationLabel(day.workloadMinutes)} planned`}>
                <span class="study-day-track" aria-hidden="true"><span class="study-day-bar" style={`width: ${loadPercent(day)}%`}></span></span>
                <span class="study-day-load-time">{durationLabel(day.workloadMinutes)}</span>
                <span class="sr-only">{loadLabel(day)}</span>
              </span>
            </div>

            <div class="study-day-content-shell">
            {#if expandedDays[day.dateLabel] === false}
              <div class="study-day-summary">
                {#if day.hasAssignments}
                  <span class="study-day-summary-count">{day.assignmentCount} {day.assignmentCount === 1 ? 'deadline' : 'deadlines'}</span>
                  <strong>{day.assignments[0].title}</strong>
                  <span class="study-day-summary-meta">{day.assignments[0].dueTime} · {day.assignments[0].effortLabel}{#if day.assignmentCount > 1} · +{day.assignmentCount - 1} more{/if}</span>
                {:else if day.hasFocusBlocks}
                  <span class="study-day-summary-count">{day.focusBlockCount} planned</span>
                  <strong>{day.focusBlocks[0].title}</strong>
                  <span class="study-day-summary-meta">{day.focusBlocks[0].effortLabel}</span>
                {:else}
                  <span class="study-day-summary-count">Open day</span>
                  <strong>No deadlines or work planned</strong>
                {/if}
              </div>
            {:else}
              <div class="study-day-content">
              {#if day.hasAssignments}
                <div class="study-assignment-scroller" use:scrollFades>
                  <div class="study-assignment-track">
                    {#each day.assignments as assignment}
                      <a class={`study-assignment ${assignment.courseColorClass}`} href={assignment.href} use:taskPreview={previewFromAssignment(assignment)}>
                        <span class="study-assignment-header">
                          <span class="study-assignment-course">{assignment.courseName}</span>
                          <span class="study-assignment-due"><CalendarDays size={13} />{assignment.dueTime}</span>
                        </span>
                        <strong title={assignment.title}>{assignment.title}</strong>
                        <span class="study-assignment-footer">
                          <span><FileText size={14} />{assignment.typeName}</span>
                          <span><Clock3 size={14} />{assignment.effortLabel}</span>
                          <OpenAssignment class="study-assignment-open" size={14} aria-hidden="true" />
                        </span>
                      </a>
                    {/each}
                  </div>
                </div>
              {:else}
                <span class="study-no-assignments">No deadlines</span>
              {/if}
              {#if day.hasFocusBlocks}
                <div class="study-focus-blocks" aria-label={`Planned work for ${day.weekdayLabel}`}>
                  <span class="study-focus-heading">Work on</span>
                  {#each day.focusBlocks as assignment}
                    <a class="study-focus-chip" href={assignment.href} use:taskPreview={previewFromAssignment(assignment)}>
                      <span class={`study-focus-dot ${assignment.courseColorClass}`} aria-hidden="true"></span>
                      <strong>{assignment.title}</strong>
                      <small>{assignment.effortLabel}</small>
                    </a>
                  {/each}
                </div>
              {/if}
              </div>
            {/if}
            </div>

            <button
              class="study-day-toggle"
              type="button"
              aria-expanded={expandedDays[day.dateLabel] !== false}
              aria-label={`${expandedDays[day.dateLabel] !== false ? 'Collapse' : 'Expand'} ${day.weekdayLabel}. ${loadLabel(day)}, ${durationLabel(day.workloadMinutes)} planned.`}
              onclick={() => toggleDay(day.dateLabel)}
            >
              <span class="study-day-toggle-icons" aria-hidden="true"><Minus class="collapse-icon" size={13} /><Plus class="expand-icon" size={13} /></span>
            </button>
          </section>
        {/each}
      </div>

      <footer class="study-week-footer">
        {#if overview.hasUnestimatedAssignments}
          <a href="/app/tasks"><Clock3 size={15} />{overview.unestimatedAssignmentCount} assignments need time estimates</a>
        {:else if overview.hasUnscheduledAssignments}
          <a href="/app/tasks"><CalendarDays size={15} />{overview.unscheduledAssignmentCount} assignments still need a due date</a>
        {:else}
          <span><CalendarDays size={15} />Assignments without a time are due all day</span>
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
          <div class="field"><label for="assignment-course">Course</label><SelectMenu id="assignment-course" name="boardID" value={overview.defaultCourseID} options={courseOptions} ariaLabel="Course" /></div>
          <div class="field"><label for="assignment-due">Due date</label><DatePicker id="assignment-due" name="dueAt" label="Due date" /></div>
          <div class="field"><label for="assignment-time">Due time</label><TimePicker id="assignment-time" name="dueTime" label="Due time" /></div>
          <div class="field"><label for="assignment-estimate">Time estimate</label><input class="input" id="assignment-estimate" name="estimatedMinutes" type="number" min="5" max="1440" step="5" inputmode="numeric" placeholder="Minutes" /><span class="field-help">Use minutes, such as 45 or 120.</span></div>
          <div class="field wide"><label for="assignment-description">Notes</label><textarea class="textarea" id="assignment-description" name="description" maxlength="5000"></textarea></div>
          <div class="field wide"><label for="assignment-labels">Type</label><input class="input" id="assignment-labels" name="labels" maxlength="500" placeholder="Lab report, Reading, Discussion" /></div>
        </div>
      </div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (createTaskOpen = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>{pending ? 'Adding…' : 'Add assignment'}</button></div>
    </form>
  </div>
{/if}

{#if planOpen}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="plan-week-title" tabindex="-1" use:dialogLayer={{ close: () => (planOpen = false) }}>
    <form class="dialog" onsubmit={planAssignment}>
      <div class="dialog-header"><div><h2 id="plan-week-title">Plan your week</h2><p>Choose one assignment and place its work on a day. Its deadline stays unchanged.</p></div><button class="icon-button" type="button" onclick={() => (planOpen = false)} aria-label="Close"><X size={16} /></button></div>
      <div class="dialog-body">
        {#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}
        <div class="form-grid"><div class="field wide"><label for="plan-assignment">Assignment</label><SelectMenu id="plan-assignment" name="taskID" value={planSelection || (overview.planCandidates[0]?.id ?? '')} options={planOptions} ariaLabel="Assignment to plan" initialFocus /></div><div class="field wide"><label for="plan-date">Work on</label><DatePicker id="plan-date" name="focusDate" label="Work on" required /></div></div>
      </div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (planOpen = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>{pending ? 'Planning…' : 'Add work day'}</button></div>
    </form>
  </div>
{/if}
