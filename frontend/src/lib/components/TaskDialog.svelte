<script lang="ts">
  import { onMount } from 'svelte';
  import { Trash2, X } from '@lucide/svelte';
  import SelectMenu from './SelectMenu.svelte';
  import type { Task, TaskDraft, TaskPriority, TaskStatus } from '../types';

  export let task: Task | null = null;
  export let defaultStatus: TaskStatus = 'backlog';
  export let saving = false;
  export let onclose: () => void;
  export let onsave: (draft: TaskDraft) => void;
  export let onrequestdelete: ((task: Task) => void) | null = null;

  const statusOptions = [
    { value: 'backlog', label: 'Backlog' },
    { value: 'in_progress', label: 'In Progress' },
    { value: 'review', label: 'Review' },
    { value: 'done', label: 'Done' }
  ];
  const priorityOptions = [
    { value: 'low', label: 'Low' },
    { value: 'medium', label: 'Medium' },
    { value: 'high', label: 'High' },
    { value: 'urgent', label: 'Urgent' }
  ];

  let panel: HTMLDivElement;
  let titleInput: HTMLInputElement;
  let title = task?.title ?? '';
  let description = task?.description ?? '';
  let status: TaskStatus = task?.status ?? defaultStatus;
  let priority: TaskPriority = task?.priority ?? 'medium';
  let labels = task?.labels.join(', ') ?? '';
  let dueAt = task?.dueAt ? task.dueAt.slice(0, 10) : '';
  let formError = '';

  onMount(() => {
    panel.focus();
    titleInput.focus();
  });

  function submit(): void {
    formError = '';
    let dueISO: string | null = null;
    if (dueAt.trim()) {
      const parsed = new Date(`${dueAt.trim()}T12:00:00Z`);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(dueAt.trim()) || Number.isNaN(parsed.getTime())) {
        formError = 'Use a due date in YYYY-MM-DD format.';
        return;
      }
      dueISO = parsed.toISOString();
    }

    onsave({
      title: title.trim(),
      description: description.trim() || null,
      status,
      priority,
      labels: labels.split(',').map((label) => label.trim()).filter(Boolean).slice(0, 6),
      dueAt: dueISO
    });
  }

  function keydown(event: KeyboardEvent): void {
    if (event.key === 'Escape' && !saving) {
      onclose();
    }
    if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') {
      event.preventDefault();
      submit();
    }
  }
</script>

<div class="modal-backdrop" role="presentation" on:mousedown={(event) => {
  if (event.target === event.currentTarget && !saving) onclose();
}}>
  <div
    class="modal-panel task-dialog"
    role="dialog"
    aria-modal="true"
    aria-labelledby="task-dialog-title"
    tabindex="-1"
    bind:this={panel}
    on:keydown={keydown}
  >
    <form on:submit={(event) => {
      event.preventDefault();
      submit();
    }}>
      <header class="modal-header">
        <h2 id="task-dialog-title">{task ? 'Edit Task' : 'Create Task'}</h2>
        <button type="button" class="icon-button" on:click={onclose} disabled={saving} aria-label="Close">
          <X size={17} />
        </button>
      </header>

      <div class="modal-body task-form">
        <label class="field field-wide">
          <span>Title</span>
          <input
            bind:this={titleInput}
            bind:value={title}
            name="task-title"
            autocomplete="off"
            maxlength="120"
            placeholder="What needs to be done?…"
            required
          />
        </label>

        <label class="field field-wide">
          <span>Description</span>
          <textarea
            bind:value={description}
            name="task-description"
            maxlength="2000"
            rows="4"
            placeholder="Add details…"
          ></textarea>
        </label>

        <SelectMenu
          label="Status"
          value={status}
          options={statusOptions}
          onchange={(value) => (status = value as TaskStatus)}
        />

        <SelectMenu
          label="Priority"
          value={priority}
          options={priorityOptions}
          onchange={(value) => (priority = value as TaskPriority)}
        />

        <label class="field">
          <span>Due Date</span>
          <input
            bind:value={dueAt}
            name="due-date"
            autocomplete="off"
            inputmode="numeric"
            placeholder="YYYY-MM-DD"
          />
        </label>

        <label class="field">
          <span>Labels</span>
          <input bind:value={labels} name="labels" autocomplete="off" placeholder="Product, API…" />
          <small>Separate up to 6 labels with commas.</small>
        </label>

        {#if formError}
          <p class="field-error field-wide" aria-live="polite">{formError}</p>
        {/if}
      </div>

      <footer class="modal-footer">
        {#if task && onrequestdelete}
          <button
            type="button"
            class="button quiet-danger-button"
            on:click={() => onrequestdelete?.(task)}
            disabled={saving}
          >
            <Trash2 size={15} strokeWidth={1.8} />
            Delete
          </button>
        {/if}
        <span class="modal-spacer"></span>
        <button type="button" class="button secondary-button" on:click={onclose} disabled={saving}>
          Cancel
        </button>
        <button type="submit" class="button primary-button" disabled={saving}>
          {saving ? 'Saving…' : task ? 'Save Changes' : 'Create Task'}
        </button>
      </footer>
    </form>
  </div>
</div>
