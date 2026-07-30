<script lang="ts">
  import { onMount } from 'svelte';
  import { Trash2, X } from '@lucide/svelte';
  import type { Task, TaskDraft, TaskPriority, TaskStatus } from '../types';

  export let task: Task | null = null;
  export let defaultStatus: TaskStatus = 'backlog';
  export let saving = false;
  export let onclose: () => void;
  export let onsave: (draft: TaskDraft) => void;
  export let ondelete: ((task: Task) => void) | null = null;

  let dialog: HTMLDialogElement;
  let titleInput: HTMLInputElement;
  let title = task?.title ?? '';
  let description = task?.description ?? '';
  let status: TaskStatus = task?.status ?? defaultStatus;
  let priority: TaskPriority = task?.priority ?? 'medium';
  let labels = task?.labels.join(', ') ?? '';
  let dueAt = task?.dueAt ? task.dueAt.slice(0, 10) : '';

  onMount(() => {
    dialog.showModal();
    titleInput.focus();
    return () => dialog.close();
  });

  function submit(): void {
    const cleanLabels = labels
      .split(',')
      .map((label) => label.trim())
      .filter(Boolean)
      .slice(0, 6);

    onsave({
      title: title.trim(),
      description: description.trim() || null,
      status,
      priority,
      labels: cleanLabels,
      dueAt: dueAt ? new Date(`${dueAt}T12:00:00Z`).toISOString() : null
    });
  }

  function clickOutside(event: MouseEvent): void {
    if (event.target === dialog) {
      onclose();
    }
  }
</script>

<dialog
  bind:this={dialog}
  class="task-dialog"
  on:click={clickOutside}
  on:cancel={(event) => {
    event.preventDefault();
    onclose();
  }}
>
  <form
    method="dialog"
    class="dialog-panel"
    on:submit={(event) => {
      event.preventDefault();
      submit();
    }}
  >
    <header class="dialog-header">
      <div>
        <span class="dialog-eyebrow">{task ? 'Task details' : 'New task'}</span>
        <h2>{task ? 'Refine the work' : 'Add work to the board'}</h2>
      </div>
      <button type="button" class="icon-button" on:click={onclose} aria-label="Close task dialog">
        <X size={18} />
      </button>
    </header>

    <div class="dialog-body">
      <label class="field field-wide">
        <span>Title</span>
        <input
          bind:this={titleInput}
          bind:value={title}
          maxlength="120"
          placeholder="What needs to move forward?"
          required
        />
      </label>

      <label class="field field-wide">
        <span>Description</span>
        <textarea
          bind:value={description}
          maxlength="2000"
          rows="4"
          placeholder="Add enough context for the next person."
        ></textarea>
      </label>

      <label class="field">
        <span>Status</span>
        <select bind:value={status}>
          <option value="backlog">Backlog</option>
          <option value="in_progress">In progress</option>
          <option value="review">Review</option>
          <option value="done">Done</option>
        </select>
      </label>

      <label class="field">
        <span>Priority</span>
        <select bind:value={priority}>
          <option value="low">Low</option>
          <option value="medium">Medium</option>
          <option value="high">High</option>
          <option value="urgent">Urgent</option>
        </select>
      </label>

      <label class="field">
        <span>Due date</span>
        <input type="date" bind:value={dueAt} />
      </label>

      <label class="field">
        <span>Labels</span>
        <input bind:value={labels} placeholder="Product, API" />
        <small>Separate up to six labels with commas.</small>
      </label>
    </div>

    <footer class="dialog-footer">
      {#if task && ondelete}
        <button type="button" class="button danger-button" on:click={() => ondelete?.(task)}>
          <Trash2 size={15} strokeWidth={1.8} />
          Delete
        </button>
      {/if}
      <span class="dialog-spacer"></span>
      <button type="button" class="button secondary-button" on:click={onclose}>Cancel</button>
      <button type="submit" class="button primary-button" disabled={saving || !title.trim()}>
        {saving ? 'Saving…' : task ? 'Save changes' : 'Create task'}
      </button>
    </footer>
  </form>
</dialog>
