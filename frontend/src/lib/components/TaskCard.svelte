<script lang="ts">
  import { Calendar, GripVertical } from '@lucide/svelte';
  import type { Task } from '../types';

  export let task: Task;
  export let dragging = false;
  export let onopen: (task: Task) => void;
  export let ondragstart: (event: DragEvent, task: Task) => void;
  export let ondragend: () => void;

  const priorityLabels = {
    low: 'Low priority',
    medium: 'Medium priority',
    high: 'High priority',
    urgent: 'Urgent priority'
  };

  function formatDate(value: string): string {
    return new Intl.DateTimeFormat('en', { month: 'short', day: 'numeric' }).format(new Date(value));
  }
</script>

<button
  type="button"
  class:dragging
  class="task-card"
  draggable={true}
  on:click={() => onopen(task)}
  on:dragstart={(event) => ondragstart(event, task)}
  on:dragend={ondragend}
  aria-label={`Open ${task.title}`}
>
  <span class="drag-handle" aria-hidden="true">
    <GripVertical size={14} strokeWidth={1.7} />
  </span>

  <span class="task-title">{task.title}</span>

  {#if task.description}
    <span class="task-description">{task.description}</span>
  {/if}

  <span class="task-meta">
    <span class={`priority priority-${task.priority}`}>
      <span class="priority-dot"></span>
      {priorityLabels[task.priority]}
    </span>

    {#if task.dueAt}
      <span class="due-date">
        <Calendar size={13} strokeWidth={1.8} />
        {formatDate(task.dueAt)}
      </span>
    {/if}
  </span>

  {#if task.labels.length}
    <span class="task-labels">
      {#each task.labels as label}
        <span class="task-label">{label}</span>
      {/each}
    </span>
  {/if}
</button>
