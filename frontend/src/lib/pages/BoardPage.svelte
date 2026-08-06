<script lang="ts">
  import { api, messageFor, refreshAll } from '$lib/api';
  import type { BoardPageContext, CalendarDayContext, TaskCardContext, TaskColumnContext, TaskOptionContext } from '$lib/types';
  import confetti from 'canvas-confetti';
  import { ArrowRightIcon as ArrowRight, ArrowSquareOutIcon as ArrowSquareOut, ArrowsDownUpIcon as ArrowsDownUp, CalendarDotsIcon as CalendarDays, CaretDownIcon as CaretDown, CaretLeftIcon as ChevronLeft, CaretRightIcon as ChevronRight, ChartBarHorizontalIcon as GanttChart, CheckCircleIcon as CheckCircle, ClockIcon as Clock, ColumnsIcon as Columns3, FunnelSimpleIcon as Funnel, ImagesSquareIcon as GalleryHorizontalEnd, MagnifyingGlassIcon as Search, PlusIcon as Plus, GearIcon as Settings, SlidersHorizontalIcon as Sliders, TableIcon as Table2, XIcon as X } from 'phosphor-svelte';
  import NewTaskDialog from '$lib/components/NewTaskDialog.svelte';
  import PopoverMenu from '$lib/components/PopoverMenu.svelte';
  import TaskCard from '$lib/components/TaskCard.svelte';
  import StudySessionPanel from '$lib/components/StudySessionPanel.svelte';
  import { deadlineFrom, durationLabel } from '$lib/ui/deadline';
  import { buildGanttScale, ganttPlacement, type GanttPlacement } from '$lib/ui/gantt';
  import { plainSummary } from '$lib/ui/summary';
  import { previewFromTask, taskPreview } from '$lib/ui/taskPreview';
  import { showToast } from '$lib/ui/toast';

  type DueFilter = 'any' | 'overdue' | 'week' | 'undated';
  type SortField = 'board' | 'due' | 'title' | 'status' | 'severity' | 'effort' | 'grade';
  type GanttScale = 'week' | 'month' | 'term';
  interface ScheduledGanttRow {
    task: TaskCardContext;
    placement: GanttPlacement;
  }

  let { board } = $props<{ board: BoardPageContext }>();
  let createTaskOpen = $state(false);
  let requestError = $state('');
  let columns = $state<TaskColumnContext[]>([]);
  let draggedTask = $state<{ id: string; status: string } | null>(null);
  let dropTarget = $state<{ taskID: string | null; position: 'before' | 'after'; status: string } | null>(null);
  let movingTaskID = $state<string | null>(null);

  // Temporary controls. The filters and sorts set in Course settings are saved
  // for everyone who opens the course; these are not saved at all. They narrow
  // what this tab is showing right now and are gone on reload, so a student can
  // ask "what is overdue" without editing the view for the whole class.
  let search = $state('');
  let stageFilter = $state<string[]>([]);
  let severityFilter = $state<string[]>([]);
  let dueFilter = $state<DueFilter>('any');
  let sortField = $state<SortField>('board');
  let sortAscending = $state(true);
  let ganttScaleName = $state<GanttScale>('month');

  const dueFilters: { value: DueFilter; name: string }[] = [
    { value: 'any', name: 'Any time' },
    { value: 'overdue', name: 'Overdue' },
    { value: 'week', name: 'Due in 7 days' },
    { value: 'undated', name: 'No due date' }
  ];

  const sortFields: { value: SortField; name: string }[] = [
    { value: 'board', name: 'Manual order' },
    { value: 'due', name: 'Due date' },
    { value: 'title', name: 'Title' },
    { value: 'status', name: 'Stage' },
    { value: 'severity', name: 'Priority' },
    { value: 'effort', name: 'Effort' },
    { value: 'grade', name: 'Score' }
  ];
  const ganttRangeFormat = new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    timeZone: 'UTC'
  });
  const ganttDayWidths: Record<GanttScale, number> = { week: 28, month: 14, term: 4 };

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

  // Severity and stage have no natural numeric order, so they are sorted by the
  // order the course itself lists them in: the workflow is the scale.
  const severityOrder = $derived(
    new Map<string, number>(board.severityOptions.map((option: TaskOptionContext, index: number) => [option.value, index]))
  );
  const statusOrder = $derived(
    new Map<string, number>(board.statusOptions.map((option: TaskOptionContext, index: number) => [option.value, index]))
  );
  const sortName = $derived(sortFields.find((option) => option.value === sortField)?.name ?? 'Manual order');
  const dueName = $derived(dueFilters.find((option) => option.value === dueFilter)?.name ?? 'Any time');

  const isFiltered = $derived(
    search.trim().length > 0 || stageFilter.length > 0 || severityFilter.length > 0 || dueFilter !== 'any'
  );
  const isSorted = $derived(sortField !== 'board');
  const isNarrowed = $derived(isFiltered || isSorted);
  const matchedCount = $derived(board.tasks.filter(matches).length);

  // Manual ordering and a temporary sort answer the same question two ways, so
  // only one of them is live: dragging returns as soon as the sort is cleared.
  const canDrag = $derived(board.canDrag && !isSorted);

  const visibleColumns = $derived(
    columns
      .filter((column) => !stageFilter.length || stageFilter.includes(column.value))
      .map((column) => ({ ...column, tasks: arrange(column.tasks) }))
  );
  const visibleTasks = $derived(arrange(board.tasks));
  const visibleDays = $derived(
    board.calendarDays.map((day: CalendarDayContext) => ({ ...day, tasks: day.tasks.filter(matches) }))
  );
  const calendarTaskCount = $derived(
    visibleDays.reduce((total: number, day: CalendarDayContext) => total + day.tasks.length, 0)
  );
  const ganttDayWidth = $derived(ganttDayWidths[ganttScaleName]);
  const ganttScale = $derived(buildGanttScale(board.tasks));
  const ganttRows = $derived.by((): { scheduled: ScheduledGanttRow[]; unscheduled: TaskCardContext[] } => {
    const scheduled: ScheduledGanttRow[] = [];
    const unscheduled: TaskCardContext[] = [];
    for (const task of visibleTasks) {
      const placement = ganttPlacement(task, ganttScale);
      if (placement) scheduled.push({ task, placement });
      else unscheduled.push(task);
    }
    return { scheduled, unscheduled };
  });

  function matches(task: TaskCardContext): boolean {
    if (stageFilter.length && !stageFilter.includes(task.statusValue)) return false;
    if (severityFilter.length && !severityFilter.includes(task.priorityValue)) return false;

    const days = deadlineFrom(task.dueInput).days;
    if (dueFilter === 'overdue' && !(days < 0)) return false;
    if (dueFilter === 'week' && !(days >= 0 && days < 7)) return false;
    if (dueFilter === 'undated' && task.hasDueDate) return false;

    const needle = search.trim().toLowerCase();
    if (needle && !`${task.title} ${task.labelsJoined}`.toLowerCase().includes(needle)) return false;
    return true;
  }

  function arrange(tasks: TaskCardContext[]): TaskCardContext[] {
    const kept = tasks.filter(matches);
    return isSorted ? [...kept].sort(compare) : kept;
  }

  /** The measure being sorted on, or null when the assignment does not carry it. */
  function measure(task: TaskCardContext): number | null {
    if (sortField === 'due') return task.hasDueDate ? deadlineFrom(task.dueInput).days : null;
    if (sortField === 'status') return statusOrder.get(task.statusValue) ?? null;
    if (sortField === 'severity') return severityOrder.get(task.priorityValue) ?? null;
    if (sortField === 'effort') return task.hasEstimate ? task.estimatedMinutes : null;
    if (sortField === 'grade') return task.hasGrade && task.gradePossible > 0 ? task.gradeEarned / task.gradePossible : null;
    return null;
  }

  // Assignments missing the measure sink to the bottom in both directions:
  // reversing a sort should not promote the rows that have nothing to say.
  function compare(left: TaskCardContext, right: TaskCardContext): number {
    const direction = sortAscending ? 1 : -1;
    if (sortField === 'title') return direction * left.title.localeCompare(right.title);
    const leftValue = measure(left);
    const rightValue = measure(right);
    if (leftValue === null || rightValue === null) return leftValue === rightValue ? 0 : leftValue === null ? 1 : -1;
    return direction * (leftValue - rightValue);
  }

  function toggleValue(values: string[], value: string): string[] {
    return values.includes(value) ? values.filter((kept) => kept !== value) : [...values, value];
  }

  /** A repeated click reverses the selected table column. */
  function sortByColumn(field: Exclude<SortField, 'board'>): void {
    if (sortField === field) sortAscending = !sortAscending;
    else {
      sortField = field;
      sortAscending = true;
    }
  }

  function ariaSort(field: Exclude<SortField, 'board'>): 'ascending' | 'descending' | 'none' {
    if (sortField !== field) return 'none';
    return sortAscending ? 'ascending' : 'descending';
  }

  function clearControls(): void {
    search = '';
    stageFilter = [];
    severityFilter = [];
    dueFilter = 'any';
    sortField = 'board';
    sortAscending = true;
  }

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
    if (type === 'gantt') return GanttChart;
    if (type === 'gallery') return GalleryHorizontalEnd;
    return Columns3;
  }

  function ganttDateLabel(task: TaskCardContext): string {
    if (task.startInput && task.dueInput) return `${task.startDisplay} – ${task.dueDisplay}`;
    if (task.startInput) return `Starts ${task.startDisplay}`;
    if (task.dueInput) return `Due ${task.dueDisplay}`;
    return 'No planning dates';
  }

  function ganttRangeDate(input: string): string {
    return ganttRangeFormat.format(Date.parse(`${input}T00:00:00Z`));
  }

  function startDrag(taskID: string, status: string, event: DragEvent): void {
    if (!canDrag || movingTaskID) return;
    draggedTask = { id: taskID, status };
    event.dataTransfer?.setData('text/plain', taskID);
    if (event.dataTransfer) event.dataTransfer.effectAllowed = 'move';
  }

  function dragOverTask(event: DragEvent, status: string, taskID: string): void {
    if (!draggedTask) return;
    event.preventDefault();
    event.stopPropagation();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
    const bounds = (event.currentTarget as HTMLElement).getBoundingClientRect();
    const position = event.clientY < bounds.top + bounds.height / 2 ? 'before' : 'after';
    dropTarget = { taskID, position, status };
  }

  function dragOverColumn(event: DragEvent, status: string): void {
    if (!draggedTask) return;
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
    dropTarget = { taskID: null, position: 'after', status };
  }

  function finishDrag(): void {
    draggedTask = null;
    dropTarget = null;
  }

  async function dropTask(event: DragEvent, status: string): Promise<void> {
    event.preventDefault();
    event.stopPropagation();
    if (!draggedTask || !canDrag || movingTaskID) return;
    const source = draggedTask;
    const target = dropTarget;
    finishDrag();

    const sourceColumn = columns.find((column) => column.value === source.status);
    const destinationColumn = columns.find((column) => column.value === status);
    const sourceTaskIndex = sourceColumn?.tasks.findIndex((task) => task.id === source.id) ?? -1;
    if (!sourceColumn || !destinationColumn || sourceTaskIndex < 0) return;

    // A filtered lane shows a subset, so the drop is read back off the full
    // column: the card it landed against, not the row it landed on.
    const anchorIndex = target?.taskID ? destinationColumn.tasks.findIndex((task) => task.id === target.taskID) : -1;
    const rawTargetIndex = anchorIndex < 0
      ? destinationColumn.tasks.length
      : anchorIndex + (target?.position === 'after' ? 1 : 0);
    const targetIndex = source.status === status && sourceTaskIndex < rawTargetIndex
      ? rawTargetIndex - 1
      : rawTargetIndex;
    await moveColumnTask(source.id, source.status, status, targetIndex);
  }

  /** Moves one card in the optimistic lane model, then saves the same order. */
  async function moveColumnTask(taskID: string, sourceStatus: string, status: string, targetIndex: number): Promise<void> {
    if (movingTaskID) return;
    const snapshot = cloneColumns(columns);
    const sourceColumn = columns.find((column) => column.value === sourceStatus);
    const destinationColumn = columns.find((column) => column.value === status);
    const sourceTaskIndex = sourceColumn?.tasks.findIndex((task) => task.id === taskID) ?? -1;
    if (!sourceColumn || !destinationColumn || sourceTaskIndex < 0) return;
    if (sourceStatus === status && sourceTaskIndex === targetIndex) return;

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
    movingTaskID = taskID;
    requestError = '';
    try {
      await api(`/api/v1/tasks/${taskID}/move`, {
        method: 'POST',
        body: JSON.stringify({ status, targetIndex })
      });
      if (!sourceWasCompleted && destinationColumn.isCompleted) confetti({ particleCount: 70, spread: 65, origin: { y: 0.75 } });
      await refreshAll();
      showToast('Assignment moved');
    } catch (cause) {
      columns = snapshot;
      requestError = messageFor(cause);
    } finally {
      movingTaskID = null;
    }
  }

  /**
   * Gives touch and keyboard users the same stage change as drag. A board that
   * is grouped by another field keeps the card in place until fresh data loads.
   */
  async function moveTaskToStage(taskID: string, status: string): Promise<void> {
    if (movingTaskID) return;
    const sourceColumn = columns.find((column) => column.tasks.some((task) => task.id === taskID));
    const task = sourceColumn?.tasks.find((candidate) => candidate.id === taskID);
    if (!sourceColumn || !task || task.statusValue === status) return;

    if (canDrag) {
      const destinationColumn = columns.find((column) => column.value === status);
      if (destinationColumn) {
        await moveColumnTask(taskID, sourceColumn.value, status, destinationColumn.tasks.length);
        return;
      }
    }

    const snapshot = cloneColumns(columns);
    const option = board.statusOptions.find((candidate: TaskOptionContext) => candidate.value === status);
    columns = columns.map((column) => ({
      ...column,
      tasks: column.tasks.map((candidate) => candidate.id === taskID && option ? {
        ...candidate,
        statusValue: option.value,
        statusName: option.name,
        statusColorClass: option.colorClass,
        statusColorStyle: option.colorStyle
      } : candidate)
    }));
    movingTaskID = taskID;
    requestError = '';
    try {
      const targetIndex = board.tasks.filter((candidate: TaskCardContext) => candidate.statusValue === status).length;
      await api(`/api/v1/tasks/${taskID}/move`, {
        method: 'POST',
        body: JSON.stringify({ status, targetIndex })
      });
      showToast('Assignment moved');
      await refreshAll();
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
        {#if board.isCanvasLinked}
          <strong class:empty={!board.canvasHasScore} class="course-grade-score">{board.canvasGradeDisplay}</strong>
          <span class="course-grade-track" aria-hidden="true">
            {#if board.canvasHasScore}<span class="course-grade-fill" style={`width: ${board.canvasScorePercent}%`}></span>{/if}
          </span>
          <span class="course-grade-detail">Published overall grade from Canvas · Last sync {board.canvasLastSyncDisplay}</span>
        {:else if pointsPossible > 0}
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
          {#if board.isCanvasLinked}<a class="canvas-source-link" href={board.canvasURL} target="_blank" rel="noopener"><span class="badge subtle">Synced from Canvas</span>{#if board.canvasCourseCode}<span>{board.canvasCourseCode}</span>{/if}{#if board.canvasTermName}<span>· {board.canvasTermName}</span>{/if}<ArrowSquareOut size={13} /></a>{/if}
          <p>{board.description || (board.canAdmin ? 'Add a course description in Course settings.' : 'Keep assignments, notes, and course material together.')}</p>
        </div>
        <div class="course-actions">
          {#if board.canEdit}<button class="button primary large" type="button" onclick={() => (createTaskOpen = true)}><Plus size={16} />Add assignment</button>{/if}
          {#if board.canAdmin}<a class="button large" href={`/app/boards/${board.id}/settings`}><Settings size={16} />Course settings</a>{/if}
        </div>
      </header>

      <StudySessionPanel sessions={board.studySessions} variant="course" courseID={board.id} />

      <nav class="course-views" aria-label="Course views">
        {#each board.views as view (view.id)}
          {@const Icon = viewIcon(view.type)}
          <a class:active={view.isActive} class="view-tab" href={view.href} aria-current={view.isActive ? 'page' : undefined}><Icon size={15} />{view.name}</a>
        {/each}
      </nav>

      <!-- Temporary controls sit under the tabs, between the view you chose and
           the assignments it holds, so it reads as "this view, narrowed". -->
      <div class="course-tools" role="group" aria-label="Temporary filters and sorting">
        <div class="course-search">
          <Search size={14} />
          <input
            class="course-search-input"
            type="search"
            placeholder="Filter by title or label"
            aria-label="Filter assignments by title or label"
            bind:value={search}
          />
          {#if search}
            <button class="course-search-clear" type="button" aria-label="Clear text filter" onclick={() => (search = '')}>
              <X size={12} />
            </button>
          {/if}
        </div>

        <PopoverMenu panelLabel="Filter by stage" panelRole="listbox">
          {#snippet trigger(control)}
            <button class:on={stageFilter.length > 0} class="tool-trigger" type="button" aria-haspopup="listbox" aria-expanded={control.open} onclick={control.toggle}>
              <Funnel size={14} />Stage
              {#if stageFilter.length}<span class="tool-badge">{stageFilter.length}</span>{/if}
              <CaretDown size={12} />
            </button>
          {/snippet}
          {#snippet children()}
            {#each columns as column (column.value)}
              <button
                class="menu-option"
                type="button"
                role="option"
                aria-selected={stageFilter.includes(column.value)}
                onclick={() => (stageFilter = toggleValue(stageFilter, column.value))}
              >
                <span class={`column-dot stage-tint ${column.dotClass}`} style={column.dotStyle} aria-hidden="true"></span>
                {column.name}<span class="tool-option-count">{column.tasks.length}</span>
              </button>
            {/each}
            {#if stageFilter.length}
              <div class="menu-separator"></div>
              <button class="menu-option" type="button" role="option" aria-selected="false" onclick={() => (stageFilter = [])}>Every stage</button>
            {/if}
          {/snippet}
        </PopoverMenu>

        <PopoverMenu panelLabel="Filter by priority" panelRole="listbox">
          {#snippet trigger(control)}
            <button class:on={severityFilter.length > 0} class="tool-trigger" type="button" aria-haspopup="listbox" aria-expanded={control.open} onclick={control.toggle}>
              Priority
              {#if severityFilter.length}<span class="tool-badge">{severityFilter.length}</span>{/if}
              <CaretDown size={12} />
            </button>
          {/snippet}
          {#snippet children()}
            {#each board.severityOptions as option (option.value)}
              <button
                class="menu-option"
                type="button"
                role="option"
                aria-selected={severityFilter.includes(option.value)}
                onclick={() => (severityFilter = toggleValue(severityFilter, option.value))}
              >
                <span class={`badge status ${option.colorClass}`} style={option.colorStyle}>{option.name}</span>
              </button>
            {/each}
            {#if severityFilter.length}
              <div class="menu-separator"></div>
              <button class="menu-option" type="button" role="option" aria-selected="false" onclick={() => (severityFilter = [])}>Every priority</button>
            {/if}
          {/snippet}
        </PopoverMenu>

        <PopoverMenu panelLabel="Filter by deadline" panelRole="listbox">
          {#snippet trigger(control)}
            <button class:on={dueFilter !== 'any'} class="tool-trigger" type="button" aria-haspopup="listbox" aria-expanded={control.open} onclick={control.toggle}>
              <CalendarDays size={14} />{dueFilter === 'any' ? 'Due' : dueName}
              <CaretDown size={12} />
            </button>
          {/snippet}
          {#snippet children(close)}
            {#each dueFilters as option (option.value)}
              <button
                class="menu-option"
                type="button"
                role="option"
                aria-selected={dueFilter === option.value}
                onclick={() => { dueFilter = option.value; close(); }}
              >{option.name}</button>
            {/each}
          {/snippet}
        </PopoverMenu>

        <PopoverMenu panelLabel="Sort assignments" panelRole="listbox">
          {#snippet trigger(control)}
            <button class:on={isSorted} class="tool-trigger" type="button" aria-haspopup="listbox" aria-expanded={control.open} onclick={control.toggle}>
              <ArrowsDownUp size={14} />{isSorted ? sortName : 'Sort'}
              {#if isSorted}<span class="tool-direction" aria-hidden="true">{sortAscending ? '↑' : '↓'}</span>{/if}
              <CaretDown size={12} />
            </button>
          {/snippet}
          {#snippet children(close)}
            {#each sortFields as option (option.value)}
              <button
                class="menu-option"
                type="button"
                role="option"
                aria-selected={sortField === option.value}
                onclick={() => { sortField = option.value; close(); }}
              >{option.name}</button>
            {/each}
            <div class="menu-separator"></div>
            <button
              class="menu-option"
              type="button"
              role="option"
              aria-selected={sortAscending}
              disabled={!isSorted}
              onclick={() => (sortAscending = true)}
            >Ascending</button>
            <button
              class="menu-option"
              type="button"
              role="option"
              aria-selected={!sortAscending}
              disabled={!isSorted}
              onclick={() => (sortAscending = false)}
            >Descending</button>
          {/snippet}
        </PopoverMenu>

        <div class="course-tools-status">
          {#if isNarrowed}
            <span class="tool-result" aria-live="polite">{matchedCount} of {board.tasks.length} shown</span>
            {#if board.activeView.isBoard && isSorted}
              <span class="tool-note">Clear the sort to drag assignments</span>
            {/if}
            <button class="tool-clear" type="button" onclick={clearControls}><X size={12} />Reset</button>
          {:else}
            <span class="tool-result">Temporary — not saved to the course</span>
          {/if}
        </div>
      </div>

      {#if requestError}<p class="error-message course-error" role="alert">{requestError}</p>{/if}
      <div class:flush={board.activeView.isBoard} class="course-canvas" aria-busy={movingTaskID ? 'true' : 'false'}>
        {#if board.activeView.isBoard}
          <div class="stage-board">
            {#each visibleColumns as column (column.value)}
              <section class="stage-lane" aria-label={`${column.name}, ${column.tasks.length} ${column.tasks.length === 1 ? 'assignment' : 'assignments'}`}>
                <header class={`stage-lane-header stage-tint ${column.dotClass}`} style={column.dotStyle}>
                  <strong>{column.name}</strong>
                  <span class="stage-lane-count">{column.tasks.length}</span>
                </header>
                <div
                  class="stage-lane-body"
                  role="list"
                  data-drop-target={dropTarget?.status === column.value && dropTarget.taskID === null ? 'true' : undefined}
                  ondragover={(event) => dragOverColumn(event, column.value)}
                  ondrop={(event) => dropTask(event, column.value)}
                >
                  {#each column.tasks as task (task.id)}
                    <TaskCard
                      {task}
                      draggable={canDrag && !movingTaskID}
                      moving={movingTaskID === task.id}
                      dropPosition={dropTarget?.taskID === task.id ? dropTarget.position : null}
                      moveOptions={board.canEdit ? board.statusOptions : []}
                      onmove={(status) => moveTaskToStage(task.id, status)}
                      ondragstart={(event) => startDrag(task.id, column.value, event)}
                      ondragend={finishDrag}
                      ondragover={(event) => dragOverTask(event, column.value, task.id)}
                      ondrop={(event) => dropTask(event, column.value)}
                    />
                  {/each}
                  {#if !column.tasks.length}
                    <p class="stage-lane-empty">{draggedTask ? 'Drop here' : isFiltered ? 'Nothing matches' : 'Nothing here'}</p>
                  {/if}
                </div>
              </section>
            {/each}
          </div>
        {:else if board.activeView.isTable}
          {#if visibleTasks.length}
            <table class="ledger">
              <thead>
                <tr>
                  <th scope="col" aria-sort={ariaSort('title')}><button class="table-sort" type="button" onclick={() => sortByColumn('title')}>Assignment<span aria-hidden="true">{sortField === 'title' ? sortAscending ? '↑' : '↓' : '↕'}</span></button></th>
                  <th scope="col" aria-sort={ariaSort('status')}><button class="table-sort" type="button" onclick={() => sortByColumn('status')}>Stage<span aria-hidden="true">{sortField === 'status' ? sortAscending ? '↑' : '↓' : '↕'}</span></button></th>
                  <th scope="col" aria-sort={ariaSort('severity')}><button class="table-sort" type="button" onclick={() => sortByColumn('severity')}>Priority<span aria-hidden="true">{sortField === 'severity' ? sortAscending ? '↑' : '↓' : '↕'}</span></button></th>
                  <th class="numeric" scope="col" aria-sort={ariaSort('effort')}><button class="table-sort end" type="button" onclick={() => sortByColumn('effort')}>Effort<span aria-hidden="true">{sortField === 'effort' ? sortAscending ? '↑' : '↓' : '↕'}</span></button></th>
                  <th class="numeric" scope="col" aria-sort={ariaSort('due')}><button class="table-sort end" type="button" onclick={() => sortByColumn('due')}>Due<span aria-hidden="true">{sortField === 'due' ? sortAscending ? '↑' : '↓' : '↕'}</span></button></th>
                  <th class="numeric" scope="col" aria-sort={ariaSort('grade')}><button class="table-sort end" type="button" onclick={() => sortByColumn('grade')}>Score<span aria-hidden="true">{sortField === 'grade' ? sortAscending ? '↑' : '↓' : '↕'}</span></button></th>
                </tr>
              </thead>
              <tbody>
                {#each visibleTasks as task (task.id)}
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
            {#if calendarTaskCount}
              <div class="month-sheet">
                <div class="month-weekdays" aria-hidden="true">
                  <div>Sun</div><div>Mon</div><div>Tue</div><div>Wed</div><div>Thu</div><div>Fri</div><div>Sat</div>
                </div>
                <div class="month-grid">
                  {#each visibleDays as day (day.dateInput)}
                    {@const minutes = dayMinutes(day)}
                    <div
                      class:muted={day.isMuted}
                      class:today={day.isToday}
                      class="month-day"
                      role="group"
                      aria-label={`${day.dateLabel}, ${day.tasks.length} ${day.tasks.length === 1 ? 'assignment' : 'assignments'}`}
                    >
                      <span class="month-day-head">
                        <time class="month-day-date" datetime={day.dateInput}>{day.day}</time>
                        {#if minutes > 0}<span class="month-day-load" title={`${durationLabel(minutes)} of estimated work due`}>{durationLabel(minutes)}</span>{/if}
                      </span>
                      {#each day.tasks.slice(0, 3) as task (task.id)}
                        <a
                          class={`month-task stage-tint ${task.statusColorClass}`}
                          style={task.statusColorStyle}
                          href={task.href}
                          use:taskPreview={previewFromTask(task)}
                        >{task.title}</a>
                      {/each}
                      {#if day.tasks.length > 3}<span class="month-more">+{day.tasks.length - 3} more</span>{/if}
                    </div>
                  {/each}
                </div>
              </div>
            {:else}
              <div class="course-empty calendar-empty">
                <span>{board.calendarMonthLabel}</span>
                <h2>{isFiltered ? 'No deadlines match these filters' : 'No deadlines this month'}</h2>
                <p>{isFiltered ? 'Widen the filters above to see more of this course.' : 'Use the month controls to check another month, or add a due date to an assignment.'}</p>
                {#if isFiltered}<button class="button small" type="button" onclick={clearControls}><X size={13} />Reset filters</button>{/if}
              </div>
            {/if}
          </section>
        {:else if board.activeView.isGantt}
          {#if visibleTasks.length}
            <section class="gantt" aria-labelledby="gantt-title" style={`--gantt-day-width: ${ganttDayWidth}px; --gantt-week-width: ${ganttDayWidth * 7}px`}>
              <header class="gantt-summary">
                <div>
                  <span>Course timeline</span>
                  <h2 id="gantt-title">{ganttRangeDate(ganttScale.startInput)} – {ganttRangeDate(ganttScale.endInput)}</h2>
                </div>
                <div class="gantt-summary-actions">
                  <p>
                    {ganttRows.scheduled.length} scheduled
                    {#if ganttRows.unscheduled.length} · {ganttRows.unscheduled.length} need dates{/if}
                  </p>
                  <div class="gantt-scale" role="group" aria-label="Timeline scale">
                    <button type="button" aria-pressed={ganttScaleName === 'week'} onclick={() => (ganttScaleName = 'week')}>Week</button>
                    <button type="button" aria-pressed={ganttScaleName === 'month'} onclick={() => (ganttScaleName = 'month')}>Month</button>
                    <button type="button" aria-pressed={ganttScaleName === 'term'} onclick={() => (ganttScaleName = 'term')}>Term</button>
                  </div>
                </div>
              </header>

              <!-- svelte-ignore a11y_no_noninteractive_tabindex (keyboard users need to scroll the timeline) -->
              <div class="gantt-scroll" role="region" tabindex="0" aria-label="Course timeline. Scroll horizontally to see more dates.">
                <div
                  class="gantt-sheet"
                  style={`--gantt-days: ${ganttScale.dayCount}; --gantt-timeline-width: ${ganttScale.dayCount * ganttDayWidth}px`}
                >
                  <div class="gantt-months" aria-hidden="true">
                    <span class="gantt-axis-label">Assignment</span>
                    {#each ganttScale.months as month}
                      <span
                        class="gantt-month"
                        style={`grid-column: ${month.offsetDays + 2} / span ${month.spanDays}`}
                      >{month.label}</span>
                    {/each}
                    {#if ganttScale.todayOffset !== null}
                      <span class="gantt-today-line" style={`grid-column: ${ganttScale.todayOffset + 2}`} title="Today"></span>
                    {/if}
                  </div>
                  <div class="gantt-weeks" aria-hidden="true">
                    <span class="gantt-axis-label">Schedule</span>
                    {#each ganttScale.weeks as week}
                      <span
                        class="gantt-week"
                        style={`grid-column: ${week.offsetDays + 2} / span ${week.spanDays}`}
                      >{week.label}</span>
                    {/each}
                    {#if ganttScale.todayOffset !== null}
                      <span class="gantt-today-line" style={`grid-column: ${ganttScale.todayOffset + 2}`} title="Today"></span>
                    {/if}
                  </div>

                  <ol class="gantt-rows" aria-label="Scheduled assignments">
                    {#each ganttRows.scheduled as row (row.task.id)}
                      <li class="gantt-row">
                        <a class="gantt-row-label" href={row.task.href} use:taskPreview={previewFromTask(row.task)}>
                          <span class={`column-dot stage-tint ${row.task.statusColorClass}`} style={row.task.statusColorStyle} aria-hidden="true"></span>
                          <span class="gantt-row-copy">
                            <strong>{row.task.title}</strong>
                            <small>{ganttDateLabel(row.task)}</small>
                          </span>
                        </a>
                        <span
                          class:milestone={row.placement.isMilestone}
                          class={`gantt-bar stage-tint ${row.task.statusColorClass}`}
                          style={`${row.task.statusColorStyle}; grid-column: ${row.placement.offsetDays + 2} / span ${row.placement.spanDays}`}
                          aria-hidden="true"
                        >
                          {#if !row.placement.isMilestone && row.placement.spanDays >= 4}<span>{row.task.statusName}</span>{/if}
                        </span>
                        {#if ganttScale.todayOffset !== null}
                          <span class="gantt-today-line" style={`grid-column: ${ganttScale.todayOffset + 2}`} aria-hidden="true"></span>
                        {/if}
                      </li>
                    {/each}
                  </ol>

                  {#if ganttRows.unscheduled.length}
                    <section class="gantt-unscheduled" aria-labelledby="gantt-unscheduled-title">
                      <h3 id="gantt-unscheduled-title">Needs dates</h3>
                      <ol class="gantt-rows">
                        {#each ganttRows.unscheduled as task (task.id)}
                          <li class="gantt-row unscheduled">
                            <a class="gantt-row-label" href={task.href} use:taskPreview={previewFromTask(task)}>
                              <span class={`column-dot stage-tint ${task.statusColorClass}`} style={task.statusColorStyle} aria-hidden="true"></span>
                              <span class="gantt-row-copy"><strong>{task.title}</strong><small>No planning dates</small></span>
                            </a>
                            <span class="gantt-placeholder">Add a start or due date to place this assignment</span>
                            {#if ganttScale.todayOffset !== null}
                              <span class="gantt-today-line" style={`grid-column: ${ganttScale.todayOffset + 2}`} aria-hidden="true"></span>
                            {/if}
                          </li>
                        {/each}
                      </ol>
                    </section>
                  {/if}
                </div>
              </div>
            </section>
          {:else}{@render EmptyView()}{/if}
        {:else if board.activeView.isGallery}
          {#if visibleTasks.length}
            <div class="briefs">
              {#each visibleTasks as task (task.id)}
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
    {#if isFiltered}
      <span>Nothing matches</span>
      <h2>No assignments match these filters</h2>
      <p>Widen the filters above to see the rest of the course.</p>
      <button class="button small" type="button" onclick={clearControls}><X size={13} />Reset filters</button>
    {:else}
      <span>Nothing to show</span>
      <h2>No assignments in this view</h2>
      <p>Add an assignment, or widen this view’s filters in Course settings.</p>
    {/if}
  </div>
{/snippet}
