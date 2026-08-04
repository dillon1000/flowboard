<script lang="ts">
  import { invalidateAll } from '$app/navigation';
  import { api, messageFor } from '$lib/api';
  import type { BoardPageContext, TaskColumnContext } from '$lib/types';
  import confetti from 'canvas-confetti';
  import { ArrowDownUp, CalendarDays, ChevronLeft, ChevronRight, Columns3, Filter, GalleryHorizontalEnd, Plus, Settings, Table2 } from '@lucide/svelte';
  import NewTaskDialog from '$lib/components/NewTaskDialog.svelte';
  import TaskCard from '$lib/components/TaskCard.svelte';
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

  function cloneColumns(source: TaskColumnContext[]): TaskColumnContext[] {
    return source.map((column) => ({ ...column, tasks: column.tasks.map((task) => ({ ...task })) }));
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

<div class="page framed">
  <div class="board-bar">
    <header class="page-header">
      <div class="page-title"><h1>{board.name}</h1><p>{board.description || `Shared as ${board.role}.`}</p></div>
      <div class="page-actions">
        {#if board.canAdmin}<a class="button" href={`/app/boards/${board.id}/settings`}><Settings size={15} />Board settings</a>{/if}
        {#if board.canEdit}<button class="button primary" type="button" onclick={() => (createTaskOpen = true)}><Plus size={15} />New task</button>{/if}
      </div>
    </header>

    <nav class="board-toolbar" aria-label="Board views">
      {#each board.views as view (view.id)}
        {@const Icon = viewIcon(view.type)}
        <a class:active={view.isActive} class="view-tab" href={view.href}><Icon size={15} />{view.name}</a>
      {/each}
      <span class="toolbar-spacer"></span><span class="badge subtle">Group: {board.groupByName}</span>
      {#if board.hasFilters}<span class="badge subtle"><Filter size={12} />{board.filterSummary}</span>{/if}
      {#if board.hasSorts}<span class="badge subtle"><ArrowDownUp size={12} />{board.sortSummary}</span>{/if}
      {#if board.canAdmin}<a class="button ghost small" href={`/app/boards/${board.id}/settings`}><Settings size={14} />Configure</a>{/if}
    </nav>
  </div>

  {#if requestError}<p class="error-message board-error" role="alert">{requestError}</p>{/if}
  <div class:flush={board.activeView.isBoard} class="board-canvas" aria-busy={movingTaskID ? 'true' : 'false'}>
    {#if board.activeView.isBoard}
      <div class="kanban">
        {#each columns as column (column.value)}
          <section class="kanban-column">
            <header class="column-header"><span class={`column-dot ${column.dotClass}`} style={column.dotStyle} aria-hidden="true"></span><strong>{column.name}</strong><span class="count">{column.tasks.length}</span></header>
            <div class="column-tasks" role="list" data-drop-target={dropTarget?.status === column.value && dropTarget.taskID === null ? 'true' : undefined} ondragover={(event) => dragOverColumn(event, column.value, column.tasks.length)} ondrop={(event) => dropTask(event, column.value, column.tasks.length)}>
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
            </div>
          </section>
        {/each}
      </div>
    {:else if board.activeView.isTable}
      {#if board.hasTasks}
        <div class="table-wrap"><table class="data-table"><thead><tr><th>Task</th><th>Status</th><th>Severity</th><th>Assignee</th><th>Start</th><th>Due</th></tr></thead><tbody>
          {#each board.tasks as task (task.id)}<tr><td><a href={task.href} use:taskPreview={previewFromTask(task)}>{task.title}</a></td><td><span class={`badge status ${task.statusColorClass}`} style={task.statusColorStyle}>{task.statusName}</span></td><td><span class={`badge ${task.priorityColorClass}`} style={task.priorityColorStyle}>{task.priorityName}</span></td><td class:muted={!task.hasAssignee}>{task.assigneeName}</td><td class="muted">{task.startDisplay}</td><td class:muted={!task.hasDueDate}>{task.dueDisplay}</td></tr>{/each}
        </tbody></table></div>
      {:else}{@render EmptyView('table')}{/if}
    {:else if board.activeView.isCalendar}
      <div class="calendar-shell">
        <div class="calendar-toolbar"><div class="calendar-navigation"><a class="icon-button" href={board.previousMonthHref} aria-label="Previous month"><ChevronLeft size={16} /></a><h2>{board.calendarMonthLabel}</h2><a class="icon-button" href={board.nextMonthHref} aria-label="Next month"><ChevronRight size={16} /></a></div><a class="button small" href={board.todayMonthHref}>Today</a></div>
        <div class="calendar-weekdays"><div>Sun</div><div>Mon</div><div>Tue</div><div>Wed</div><div>Thu</div><div>Fri</div><div>Sat</div></div>
        <div class="calendar-grid">{#each board.calendarDays as day}<div class:muted={day.isMuted} class:today={day.isToday} class="calendar-day"><span class="calendar-date">{day.day}</span>{#each day.tasks as task}<a class={`calendar-task ${task.statusColorClass}`} style={task.statusColorStyle} href={task.href} use:taskPreview={previewFromTask(task)}><span>{task.title}</span></a>{/each}</div>{/each}</div>
      </div>
    {:else if board.activeView.isGallery}
      {#if board.hasTasks}<div class="gallery">{#each board.tasks as task (task.id)}<a class="gallery-card" href={task.href} use:taskPreview={previewFromTask(task)}><h3>{task.title}</h3><p>{task.description || 'No description.'}</p><div class="task-meta"><span class={`badge status ${task.statusColorClass}`} style={task.statusColorStyle}>{task.statusName}</span><span class={`badge ${task.priorityColorClass}`} style={task.priorityColorStyle}>{task.priorityName}</span></div></a>{/each}</div>{:else}{@render EmptyView('gallery')}{/if}
    {/if}
  </div>
</div>

<NewTaskDialog bind:open={createTaskOpen} {board} />

{#snippet EmptyView(icon: 'table' | 'gallery')}
  <div class="empty-state"><div><span class="empty-state-icon" aria-hidden="true">{#if icon === 'table'}<Table2 size={22} />{:else}<GalleryHorizontalEnd size={22} />{/if}</span><h2>No tasks in this view</h2><p>Create a task, or loosen this view’s filters in board settings.</p></div></div>
{/snippet}
