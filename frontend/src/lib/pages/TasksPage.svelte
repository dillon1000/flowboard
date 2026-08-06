<script lang="ts">
  import { api, messageFor, refreshAll } from '$lib/api';
  import type { TaskCardContext, TasksPageContext } from '$lib/types';
  import { ArchiveIcon as Archive, CalendarDotsIcon as CalendarDays, CheckSquareIcon as CheckSquare, ClockIcon as Clock, MagnifyingGlassIcon as Search } from 'phosphor-svelte';
  import { previewFromTask, taskPreview } from '$lib/ui/taskPreview';
  import { showToast } from '$lib/ui/toast';

  let { tasks, archived } = $props<{ tasks: TasksPageContext; archived: boolean }>();
  let requestError = $state('');
  type TaskSortField = 'title' | 'course' | 'status' | 'priority' | 'effort' | 'due';
  let sortField = $state<TaskSortField | null>(null);
  let sortAscending = $state(true);
  const sortedTasks = $derived(sortField ? [...tasks.tasks].sort(compareTasks) : tasks.tasks);

  function sortBy(field: TaskSortField): void {
    if (sortField === field) sortAscending = !sortAscending;
    else {
      sortField = field;
      sortAscending = true;
    }
  }

  function ariaSort(field: TaskSortField): 'ascending' | 'descending' | 'none' {
    if (sortField !== field) return 'none';
    return sortAscending ? 'ascending' : 'descending';
  }

  /** Missing estimates and dates stay below useful values in both directions. */
  function compareTasks(left: TaskCardContext, right: TaskCardContext): number {
    if (!sortField) return 0;
    const direction = sortAscending ? 1 : -1;
    if (sortField === 'title') return direction * left.title.localeCompare(right.title);
    if (sortField === 'course') return direction * left.boardName.localeCompare(right.boardName);
    if (sortField === 'status') return direction * left.statusName.localeCompare(right.statusName);
    if (sortField === 'priority') return direction * left.priorityName.localeCompare(right.priorityName);
    const leftValue = sortField === 'effort' ? (left.hasEstimate ? left.estimatedMinutes : null) : (left.hasDueDate ? Date.parse(`${left.dueInput}T00:00:00`) : null);
    const rightValue = sortField === 'effort' ? (right.hasEstimate ? right.estimatedMinutes : null) : (right.hasDueDate ? Date.parse(`${right.dueInput}T00:00:00`) : null);
    if (leftValue === null || rightValue === null) return leftValue === rightValue ? 0 : leftValue === null ? 1 : -1;
    return direction * (leftValue - rightValue);
  }

  async function restore(taskID: string): Promise<void> {
    requestError = '';
    try {
      await api(`/api/v1/tasks/${taskID}`, { method: 'PATCH', body: JSON.stringify({ isArchived: false }) });
      await refreshAll();
      showToast('Assignment restored');
    } catch (cause) {
      requestError = messageFor(cause);
    }
  }
</script>

<div class="page">
  <header class="page-header">
    <div class="page-title">
      <h1>{archived ? 'Archived assignments' : tasks.query ? 'Search results' : 'All assignments'}</h1>
      <p>{archived ? 'Restore assignments that you want to plan again.' : tasks.query ? `Assignments matching “${tasks.query}”.` : 'Every active assignment across your courses.'}</p>
    </div>
    <div class="page-actions">
      {#if archived}<a class="button" href="/app/tasks"><CheckSquare size={15} />All assignments</a>{:else}<a class="button" href="/app/tasks/archived"><Archive size={15} />Archived assignments</a>{/if}
    </div>
  </header>
  {#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}
  {#if tasks.hasTasks}
    {#if !archived && !tasks.query}
      <section class="stats task-stats" aria-label="Assignment planning summary">
        <div class="stat"><span><CheckSquare size={14} />Active assignments</span><strong>{tasks.tasks.length - tasks.completedAssignmentCount}</strong></div>
        <div class="stat"><span><CalendarDays size={14} />Need a due date</span><strong>{tasks.undatedAssignmentCount}</strong></div>
        <div class="stat"><span><Clock size={14} />Need an estimate</span><strong>{tasks.unestimatedAssignmentCount}</strong></div>
      </section>
    {/if}
    <div class="table-wrap">
      <table class="data-table">
        <thead><tr>
          <th scope="col" aria-sort={ariaSort('title')}><button class="table-sort" type="button" onclick={() => sortBy('title')}>Assignment<span aria-hidden="true">{sortField === 'title' ? sortAscending ? '↑' : '↓' : '↕'}</span></button></th>
          <th scope="col" aria-sort={ariaSort('course')}><button class="table-sort" type="button" onclick={() => sortBy('course')}>Course<span aria-hidden="true">{sortField === 'course' ? sortAscending ? '↑' : '↓' : '↕'}</span></button></th>
          <th scope="col" aria-sort={ariaSort('status')}><button class="table-sort" type="button" onclick={() => sortBy('status')}>Status<span aria-hidden="true">{sortField === 'status' ? sortAscending ? '↑' : '↓' : '↕'}</span></button></th>
          <th scope="col" aria-sort={ariaSort('priority')}><button class="table-sort" type="button" onclick={() => sortBy('priority')}>Priority<span aria-hidden="true">{sortField === 'priority' ? sortAscending ? '↑' : '↓' : '↕'}</span></button></th>
          <th scope="col" aria-sort={ariaSort('effort')}><button class="table-sort" type="button" onclick={() => sortBy('effort')}>Plan<span aria-hidden="true">{sortField === 'effort' ? sortAscending ? '↑' : '↓' : '↕'}</span></button></th>
          <th scope="col" aria-sort={ariaSort('due')}><button class="table-sort" type="button" onclick={() => sortBy('due')}>Due<span aria-hidden="true">{sortField === 'due' ? sortAscending ? '↑' : '↓' : '↕'}</span></button></th>
          {#if archived}<th scope="col">Action</th>{/if}
        </tr></thead>
        <tbody>
          {#each sortedTasks as task (task.id)}
            <tr>
              <td><a href={task.href} use:taskPreview={previewFromTask(task)}>{task.title}</a></td><td>{task.boardName}</td>
              <td><span class={`badge status ${task.statusColorClass}`} style={task.statusColorStyle}>{task.statusName}</span></td>
              <td><span class={`badge ${task.priorityColorClass}`} style={task.priorityColorStyle}>{task.priorityName}</span></td>
              <td class:muted={!task.hasEstimate}>{task.estimatedDisplay}</td><td class:muted={!task.hasDueDate} class="due-cell"><span>{task.dueDisplay}</span>{#if task.hasDueDate}<span class="due-time">{task.dueTimeDisplay}</span>{/if}</td>
              {#if archived}<td>{#if task.canEdit}<button class="button small" type="button" onclick={() => restore(task.id)}>Restore</button>{:else}<span class="muted">View only</span>{/if}</td>{/if}
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {:else}
    <div class="empty-state"><div><span class="empty-state-icon" aria-hidden="true">{#if archived}<Archive size={22} />{:else}<Search size={22} />{/if}</span><h2>{archived ? 'No archived assignments' : 'No assignments found'}</h2><p>{archived ? 'Assignments that you archive will appear here.' : 'Try a different search, or add an assignment from this week.'}</p></div></div>
  {/if}
</div>
