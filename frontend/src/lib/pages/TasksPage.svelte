<script lang="ts">
  import { invalidateAll } from '$app/navigation';
  import { api, messageFor } from '$lib/api';
  import type { TasksPageContext } from '$lib/types';
  import { ArchiveIcon as Archive, CalendarDotsIcon as CalendarDays, CheckSquareIcon as CheckSquare, ClockIcon as Clock, MagnifyingGlassIcon as Search } from 'phosphor-svelte';
  import { previewFromTask, taskPreview } from '$lib/ui/taskPreview';
  import { showToast } from '$lib/ui/toast';

  let { tasks, archived } = $props<{ tasks: TasksPageContext; archived: boolean }>();
  let requestError = $state('');

  async function restore(taskID: string): Promise<void> {
    requestError = '';
    try {
      await api(`/api/v1/tasks/${taskID}`, { method: 'PATCH', body: JSON.stringify({ isArchived: false }) });
      await invalidateAll();
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
        <thead><tr><th>Assignment</th><th>Course</th><th>Status</th><th>Severity</th><th>Plan</th><th>Due</th>{#if archived}<th>Action</th>{/if}</tr></thead>
        <tbody>
          {#each tasks.tasks as task (task.id)}
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
