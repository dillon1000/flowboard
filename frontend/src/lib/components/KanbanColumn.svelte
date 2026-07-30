<script lang="ts">
  import { Plus } from '@lucide/svelte';
  import TaskCard from './TaskCard.svelte';
  import type { Task, TaskStatus } from '../types';

  export let status: TaskStatus;
  export let title: string;
  export let tasks: Task[];
  export let draggingTaskID: string | null;
  export let oncreate: (status: TaskStatus) => void;
  export let onopen: (task: Task) => void;
  export let ondragstart: (event: DragEvent, task: Task) => void;
  export let ondragend: () => void;
  export let ondrop: (status: TaskStatus, targetIndex: number) => void;

  let dragDepth = 0;
  let active = false;

  function enter(event: DragEvent): void {
    event.preventDefault();
    dragDepth += 1;
    active = true;
  }

  function leave(): void {
    dragDepth -= 1;
    if (dragDepth <= 0) {
      dragDepth = 0;
      active = false;
    }
  }

  function dropAt(event: DragEvent, index: number): void {
    event.preventDefault();
    event.stopPropagation();
    dragDepth = 0;
    active = false;
    ondrop(status, index);
  }
</script>

<section
  class:drop-active={active}
  class="kanban-column"
  on:dragenter={enter}
  on:dragover={(event) => event.preventDefault()}
  on:dragleave={leave}
  on:drop={(event) => dropAt(event, tasks.length)}
  aria-labelledby={`column-${status}`}
>
  <header class="column-header">
    <div>
      <div class="column-title-row">
        <span class={`status-marker status-${status}`}></span>
        <h2 id={`column-${status}`}>{title}</h2>
        <span class="task-count">{tasks.length}</span>
      </div>
    </div>
    <button
      type="button"
      class="icon-button column-add"
      on:click={() => oncreate(status)}
      aria-label={`Add a task to ${title}`}
    >
      <Plus size={16} strokeWidth={1.9} />
    </button>
  </header>

  <div class="column-rule"></div>

  <div class="task-stack" role="list">
    {#each tasks as task, index (task.id)}
      <div
        class="card-drop-target"
        role="listitem"
        on:dragover={(event) => event.preventDefault()}
        on:drop={(event) => dropAt(event, index)}
      >
        <TaskCard
          {task}
          dragging={draggingTaskID === task.id}
          {onopen}
          {ondragstart}
          {ondragend}
        />
      </div>
    {/each}

    <button
      type="button"
      class="empty-drop"
      class:visible={active || tasks.length === 0}
      on:click={() => oncreate(status)}
      on:dragover={(event) => event.preventDefault()}
      on:drop={(event) => dropAt(event, tasks.length)}
    >
      <Plus size={14} strokeWidth={1.8} />
      {tasks.length === 0 ? 'Add the first task' : 'Drop at the end'}
    </button>
  </div>
</section>
