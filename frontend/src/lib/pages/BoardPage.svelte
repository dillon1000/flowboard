<script lang="ts">
  import { invalidateAll } from '$app/navigation';
  import { api, messageFor } from '$lib/api';
  import type { BoardPageContext, CalendarDayContext, TaskCardContext, TaskColumnContext } from '$lib/types';
  import confetti from 'canvas-confetti';
  import { ArrowRightIcon as ArrowRight, CalendarDotsIcon as CalendarDays, CaretLeftIcon as ChevronLeft, CaretRightIcon as ChevronRight, CheckCircleIcon as CheckCircle, ClockIcon as Clock, ColumnsIcon as Columns3, ImagesSquareIcon as GalleryHorizontalEnd, PlusIcon as Plus, GearIcon as Settings, SlidersHorizontalIcon as Sliders, TableIcon as Table2 } from 'phosphor-svelte';
  import NewTaskDialog from '$lib/components/NewTaskDialog.svelte';
  import TaskCard from '$lib/components/TaskCard.svelte';
  import { deadlineFrom, durationLabel } from '$lib/ui/deadline';
  import { plainSummary } from '$lib/ui/summary';
  import { previewFromTask, taskPreview } from '$lib/ui/taskPreview';
  import { showToast } from '$lib/ui/toast';

  let { board } = $props<{ board: BoardPageContext }>();
  let createTaskOpen = $state(false);
  let requestError = $state('');
  let columns = $state<TaskColumnContext[]>([]);
  let draggedTask = $state<{ id: string; status: string; index: number } | null>(null);
  let dropTarget = $state<{ taskID: string | null; position: 'before' | 'after'; status: string; index: number } | null>(null);
  let movingTaskID = $state<string | null>(null);

  $effect(() => {
    columns = cloneColumns(board.columns);
  });

  // The grade ledger totals the scores already returned for this course. It is
  // the one number a course page exists to answer, and nothing else totals it.
  const gradedTasks = $derived<TaskCardContext[]>(
    board.tasks.filter((task: TaskCardContext) => task.hasGrade && task.gradePossible > 0)
  );
  const pointsEarned = $derived(
    gradedTasks.reduce((total: number, task: TaskCardContext) => total + task.gradeEarned, 0)
  );
  const pointsPossible = $derived(
    gradedTasks.reduce((total: number, task: TaskCardContext) => total + task.gradePossible, 0)
  );
  const gradePercent = $derived(pointsPossible > 0 ? Math.round((pointsEarned / pointsPossible) * 100) : 0);
  const remainingCount = $derived(board.assignmentCount - board.completedAssignmentCount);

  // The stage census reads off the optimistic columns, so a dragged card moves
  // the bars at the same moment it moves on the board.
  const busiestStage = $derived(Math.max(...columns.map((column) => column.tasks.length), 1));

  const viewSummary = $derived.by(() => {
    const parts: string[] = [];
    if (board.activeView.isBoard) parts.push(`Grouped by ${board.groupByName}`);
    if (board.hasFilters) parts.push(board.filterSummary);
    if (board.hasSorts) parts.push(board.sortSummary);
    return parts.length ? parts.join(' · ') : 'No filters or sorting';
  });

  function cloneColumns(source: TaskColumnContext[]): TaskColumnContext[] {
    return source.map((column) => ({ ...column, tasks: column.tasks.map((task) => ({ ...task })) }));
  }

  function scoreLabel(points: number): string {
    return Number.isInteger(points) ? String(points) : points.toFixed(1);
  }

  // The month reads as workload, not just dates: each day carries the estimated
  // time that lands on it, which is the same measure the planner and the term
  // map already draw.
  function dayMinutes(day: CalendarDayContext): number {
    return day.tasks.reduce((total: number, task: TaskCardContext) => total + task.estimatedMinutes, 0);
  }

  function viewIcon(type: string): typeof Columns3 {
    if (type === 'table') return Table2;
    if (type === 'calendar') return CalendarDays;
    if (type === 'gallery') return GalleryHorizontalEnd;
    return Columns3;
  }

  function startDrag(taskID: string, status: string, index: number, event: DragEvent): void {
    if (!board.canDrag || movingTaskID) return;
    draggedTask = { id: taskID, status, index };
    event.dataTransfer?.setData('text/plain', taskID);
    if (event.dataTransfer) event.dataTransfer.effectAllowed = 'move';
  }

  function dragOverTask(event: DragEvent, status: string, index: number, taskID: string): void {
    if (!draggedTask) return;
    event.preventDefault();
    event.stopPropagation();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
    const bounds = (event.currentTarget as HTMLElement).getBoundingClientRect();
    const position = event.clientY < bounds.top + bounds.height / 2 ? 'before' : 'after';
    dropTarget = { taskID, position, status, index: index + (position === 'after' ? 1 : 0) };
  }

  function dragOverColumn(event: DragEvent, status: string, taskCount: number): void {
    if (!draggedTask) return;
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
    dropTarget = { taskID: null, position: 'after', status, index: taskCount };
  }

  function finishDrag(): void {
    draggedTask = null;
    dropTarget = null;
  }

  async function dropTask(event: DragEvent, status: string, rawTargetIndex: number): Promise<void> {
    event.preventDefault();
    event.stopPropagation();
    if (!draggedTask || !board.canDrag || movingTaskID) return;
    const source = draggedTask;
    const targetIndex = source.status === status && source.index < rawTargetIndex
      ? rawTargetIndex - 1
      : rawTargetIndex;
    finishDrag();
    if (source.status === status && source.index === targetIndex) return;

    const snapshot = cloneColumns(columns);
    const sourceColumn = columns.find((column) => column.value === source.status);
    const destinationColumn = columns.find((column) => column.value === status);
    const sourceTaskIndex = sourceColumn?.tasks.findIndex((task) => task.id === source.id) ?? -1;
    if (!sourceColumn || !destinationColumn || sourceTaskIndex < 0) return;
    const sourceWasCompleted = sourceColumn.isCompleted;
    const [task] = sourceColumn.tasks.splice(sourceTaskIndex, 1);
    const movedTask = {
      ...task,
      statusValue: destinationColumn.value,
      statusName: destinationColumn.name,
      statusColorClass: destinationColumn.dotClass,
      statusColorStyle: destinationColumn.dotStyle
    };
    destinationColumn.tasks.splice(Math.min(targetIndex, destinationColumn.tasks.length), 0, movedTask);
    columns = [...columns];
    movingTaskID = source.id;
    requestError = '';
    try {
      await api(`/api/v1/tasks/${source.id}/move`, {
        method: 'POST',
        body: JSON.stringify({ status, targetIndex })
      });
      if (!sourceWasCompleted && destinationColumn.isCompleted) confetti({ particleCount: 70, spread: 65, origin: { y: 0.75 } });
      await invalidateAll();
      showToast('Task moved');
    } catch (cause) {
      columns = snapshot;
      requestError = messageFor(cause);
    } finally {
      movingTaskID = null;
    }
  }
</script>

<div class="page course-page">
  <div class="course-workspace">
    <aside class="course-panel" aria-label="Course standing">
      <section class="course-grade" aria-labelledby="course-grade-title">
        <h2 id="course-grade-title">Grade</h2>
        {#if pointsPossible > 0}
          <strong class="course-grade-score">{gradePercent}<small>%</small></strong>
          <span class="course-grade-track" aria-hidden="true">
            <span class="course-grade-fill" style={`width: ${Math.min(gradePercent, 100)}%`}></span>
          </span>
          <span class="course-grade-detail">
            {scoreLabel(pointsEarned)} of {scoreLabel(pointsPossible)} points across {gradedTasks.length}
            {gradedTasks.length === 1 ? 'graded assignment' : 'graded assignments'}
          </span>
        {:else}
          <strong class="course-grade-score empty">—</strong>
          <span class="course-grade-track" aria-hidden="true"></span>
          <span class="course-grade-detail">No scores yet. Add one to an assignment when work comes back.</span>
        {/if}
      </section>

      <dl class="course-stats">
        <div><dt>Assignments</dt><dd>{board.assignmentCount}</dd></div>
        <div><dt>Done</dt><dd>{board.completedAssignmentCount}</dd></div>
        <div><dt>Left</dt><dd>{remainingCount}</dd></div>
      </dl>

      <section class="course-ladder" aria-labelledby="course-ladder-title">
        <h2 id="course-ladder-title">Stages</h2>
        <div class="course-ladder-rows">
          {#each columns as column (column.value)}
            <div class="course-ladder-row">
              <span class={`column-dot stage-tint ${column.dotClass}`} style={column.dotStyle} aria-hidden="true"></span>
              <span class="course-ladder-label">{column.name}</span>
              <span class="course-ladder-track" aria-hidden="true">
                <span
                  class:complete={column.isCompleted}
                  class="course-ladder-bar"
                  style={`width: ${(column.tasks.length / busiestStage) * 100}%`}
                ></span>
              </span>
              <span class="course-ladder-count">{column.tasks.length}</span>
            </div>
          {/each}
        </div>
      </section>

      <p class="course-ladder-key">Bars compare how many assignments sit in each stage.</p>
    </aside>

    <section class="course-main" aria-labelledby="course-title">
      <header class="course-header">
        <div class="course-title">
          <h1 id="course-title">{board.name}</h1>
          <p>{board.description || (board.canAdmin ? 'Add a course description in Course settings.' : 'Keep assignments, notes, and course material together.')}</p>
        </div>
        <div class="course-actions">
          {#if board.canEdit}<button class="button primary large" type="button" onclick={() => (createTaskOpen = true)}><Plus size={16} />Add assignment</button>{/if}
          {#if board.canAdmin}<a class="button large" href={`/app/boards/${board.id}/settings`}><Settings size={16} />Course settings</a>{/if}
        </div>
      </header>

      <nav class="course-views" aria-label="Course views">
        {#each board.views as view (view.id)}
          {@const Icon = viewIcon(view.type)}
          <a class:active={view.isActive} class="view-tab" href={view.href} aria-current={view.isActive ? 'page' : undefined}><Icon size={15} />{view.name}</a>
        {/each}
      </nav>

      {#if requestError}<p class="error-message course-error" role="alert">{requestError}</p>{/if}
      <div class:flush={board.activeView.isBoard} class="course-canvas" aria-busy={movingTaskID ? 'true' : 'false'}>
        {#if board.activeView.isBoard}
          <div class="stage-board">
            {#each columns as column (column.value)}
              <section class="stage-lane" aria-label={`${column.name}, ${column.tasks.length} ${column.tasks.length === 1 ? 'assignment' : 'assignments'}`}>
                <header class={`stage-lane-header stage-tint ${column.dotClass}`} style={column.dotStyle}>
                  <strong>{column.name}</strong>
                  <span class="stage-lane-count">{column.tasks.length}</span>
                </header>
                <div
                  class="stage-lane-body"
                  role="list"
                  data-drop-target={dropTarget?.status === column.value && dropTarget.taskID === null ? 'true' : undefined}
                  ondragover={(event) => dragOverColumn(event, column.value, column.tasks.length)}
                  ondrop={(event) => dropTask(event, column.value, column.tasks.length)}
                >
                  {#each column.tasks as task, index (task.id)}
                    <TaskCard
                      {task}
                      draggable={board.canDrag && !movingTaskID}
                      moving={movingTaskID === task.id}
                      dropPosition={dropTarget?.taskID === task.id ? dropTarget.position : null}
                      ondragstart={(event) => startDrag(task.id, column.value, index, event)}
                      ondragend={finishDrag}
                      ondragover={(event) => dragOverTask(event, column.value, index, task.id)}
                      ondrop={(event) => dropTask(event, column.value, dropTarget?.taskID === task.id ? dropTarget.index : index)}
                    />
                  {/each}
                  {#if !column.tasks.length}
                    <p class="stage-lane-empty">{draggedTask ? 'Drop here' : 'Nothing here'}</p>
                  {/if}
                </div>
              </section>
            {/each}
          </div>
        {:else if board.activeView.isTable}
          {#if board.hasTasks}
            <table class="ledger">
              <thead>
                <tr>
                  <th>Assignment</th>
                  <th>Stage</th>
                  <th>Severity</th>
                  <th class="numeric">Effort</th>
                  <th class="numeric">Due</th>
                  <th class="numeric">Score</th>
                </tr>
              </thead>
              <tbody>
                {#each board.tasks as task (task.id)}
                  {@const deadline = deadlineFrom(task.dueInput)}
                  <tr class={`stage-tint ${task.statusColorClass}`} style={task.statusColorStyle}>
                    <td class="ledger-assignment">
                      <a href={task.href} use:taskPreview={previewFromTask(task)}>{task.title}</a>
                      {#if task.hasLabels}<small>{task.labelsJoined}</small>{/if}
                    </td>
                    <td><span class="ledger-stage">{task.statusName}</span></td>
                    <td>
                      <span class={`ledger-severity stage-tint ${task.priorityColorClass}`} style={task.priorityColorStyle}>{task.priorityName}</span>
                    </td>
                    <td class:missing={!task.hasEstimate} class="numeric">{task.hasEstimate ? task.estimatedDisplay : '—'}</td>
                    <td class="numeric ledger-due">
                      <span class="measure-due" data-tone={deadline.tone}>{deadline.short}</span>
                      {#if task.hasDueDate}<small>{task.dueDisplay} · {task.dueTimeDisplay}</small>{/if}
                    </td>
                    <td class:missing={!task.hasGrade} class="numeric">{task.hasGrade ? task.gradeDisplay : '—'}</td>
                  </tr>
                {/each}
              </tbody>
            </table>
          {:else}{@render EmptyView()}{/if}
        {:else if board.activeView.isCalendar}
          <section class="month" aria-label={`${board.calendarMonthLabel} deadlines`}>
            <header class="month-toolbar">
              <div class="month-nav">
                <a class="icon-button" href={board.previousMonthHref} aria-label="Previous month"><ChevronLeft size={16} /></a>
                <h2>{board.calendarMonthLabel}</h2>
                <a class="icon-button" href={board.nextMonthHref} aria-label="Next month"><ChevronRight size={16} /></a>
              </div>
              <a class="button small" href={board.todayMonthHref}>Today</a>
            </header>
            <div class="month-sheet">
              <div class="month-weekdays">
                <div>Sun</div><div>Mon</div><div>Tue</div><div>Wed</div><div>Thu</div><div>Fri</div><div>Sat</div>
              </div>
              <div class="month-grid">
                {#each board.calendarDays as day}
                  {@const minutes = dayMinutes(day)}
                  <div class:muted={day.isMuted} class:today={day.isToday} class="month-day">
                    <span class="month-day-head">
                      <span class="month-day-date">{day.day}</span>
                      {#if minutes > 0}<span class="month-day-load" title={`${durationLabel(minutes)} of estimated work due`}>{durationLabel(minutes)}</span>{/if}
                    </span>
                    {#each day.tasks as task}
                      <a
                        class={`month-task stage-tint ${task.statusColorClass}`}
                        style={task.statusColorStyle}
                        href={task.href}
                        use:taskPreview={previewFromTask(task)}
                      >{task.title}</a>
                    {/each}
                  </div>
                {/each}
              </div>
            </div>
          </section>
        {:else if board.activeView.isGallery}
          {#if board.hasTasks}
            <div class="briefs">
              {#each board.tasks as task (task.id)}
                {@const deadline = deadlineFrom(task.dueInput)}
                <a
                  class={`brief stage-tint ${task.statusColorClass}`}
                  style={task.statusColorStyle}
                  href={task.href}
                  use:taskPreview={previewFromTask(task)}
                >
                  <span class="brief-stage">{task.statusName}</span>
                  <h3>{task.title}</h3>
                  <p class:missing={!task.hasDescription}>
                    {task.hasDescription ? plainSummary(task.description) : 'No description yet.'}
                  </p>
                  <span class="measures">
                    <span class="measure-due" data-tone={deadline.tone} title={deadline.long}>{deadline.short}</span>
                    <span class:missing={!task.hasEstimate} class="measure-effort">
                      {task.hasEstimate ? task.estimatedDisplay : 'No estimate'}
                    </span>
                    {#if task.hasGrade}<span class="measure-grade">{task.gradeDisplay}</span>{/if}
                  </span>
                </a>
              {/each}
            </div>
          {:else}{@render EmptyView()}{/if}
        {/if}
      </div>

      <footer class="course-footer">
        <span class="course-view-summary">
          {viewSummary}
          {#if board.canAdmin}<a href={`/app/boards/${board.id}/settings`}><Sliders size={14} />Configure view</a>{/if}
        </span>
        {#if board.undatedAssignmentCount > 0}
          <a class="course-gap" href="/app/tasks">
            <CalendarDays size={15} />{board.undatedAssignmentCount} {board.undatedAssignmentCount === 1 ? 'assignment needs' : 'assignments need'} a due date<ArrowRight size={14} />
          </a>
        {:else if board.unestimatedAssignmentCount > 0}
          <a class="course-gap" href="/app/tasks">
            <Clock size={15} />{board.unestimatedAssignmentCount} {board.unestimatedAssignmentCount === 1 ? 'assignment needs' : 'assignments need'} a time estimate<ArrowRight size={14} />
          </a>
        {:else if board.hasTasks}
          <span class="course-gap"><CheckCircle size={15} />Every assignment has a date and an estimate</span>
        {/if}
      </footer>
    </section>
  </div>
</div>

<NewTaskDialog bind:open={createTaskOpen} {board} />

{#snippet EmptyView()}
  <div class="course-empty">
    <span>Nothing to show</span>
    <h2>No assignments in this view</h2>
    <p>Add an assignment, or widen this view’s filters in Course settings.</p>
  </div>
{/snippet}
