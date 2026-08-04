<script lang="ts">
  import { invalidateAll } from '$app/navigation';
  import { api, messageFor } from '$lib/api';
  import type { BoardPageContext, TaskResponse } from '$lib/types';
  import { X } from '@lucide/svelte';
  import { dialogLayer } from '$lib/actions/dialogLayer';

  let { open = $bindable(false), board } = $props<{ open: boolean; board: BoardPageContext }>();
  let pending = $state(false);
  let requestError = $state('');

  function apiDate(value: FormDataEntryValue | null): string | null {
    const date = String(value ?? '');
    return date ? `${date}T00:00:00Z` : null;
  }

  async function submit(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    pending = true;
    requestError = '';
    try {
      await api<TaskResponse>('/api/v1/tasks', {
        method: 'POST',
        body: JSON.stringify({
          boardID: board.id,
          title: String(data.get('title') ?? ''),
          description: String(data.get('description') ?? '') || null,
          status: String(data.get('status') ?? board.newTaskStatus),
          priority: String(data.get('priority') ?? board.newTaskPriority),
          labels: String(data.get('labels') ?? '').split(',').map((label) => label.trim()).filter(Boolean).slice(0, 6),
          startAt: apiDate(data.get('startAt')),
          dueAt: apiDate(data.get('dueAt'))
        })
      });
      form.reset();
      open = false;
      await invalidateAll();
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pending = false;
    }
  }
</script>

{#if open}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="new-task-title" tabindex="-1" use:dialogLayer={{ close: () => (open = false) }}>
    <form class="dialog wide" onsubmit={submit}>
      <div class="dialog-header">
        <div><h2 id="new-task-title">Create task</h2><p>{board.hasDefaultTemplate ? `Using the ${board.defaultTemplateName} template.` : 'Add the work, then refine its details.'}</p></div>
        <button class="icon-button" type="button" onclick={() => (open = false)} aria-label="Close"><X size={16} /></button>
      </div>
      <div class="dialog-body">
        {#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}
        <div class="form-grid">
          <div class="field wide"><label for="new-task-name">Title</label><input class="input" id="new-task-name" name="title" value={board.newTaskTitle} maxlength="120" required data-dialog-focus /></div>
          <div class="field wide"><label for="new-task-description">Description</label><textarea class="textarea" id="new-task-description" name="description" maxlength="2000">{board.newTaskDescription}</textarea></div>
          <div class="field"><label for="new-task-status">Status</label><select class="input" id="new-task-status" name="status" value={board.newTaskStatus}>{#each board.statusOptions as option}<option value={option.value}>{option.name}</option>{/each}</select></div>
          <div class="field"><label for="new-task-priority">Severity</label><select class="input" id="new-task-priority" name="priority" value={board.newTaskPriority}>{#each board.severityOptions as option}<option value={option.value}>{option.name}</option>{/each}</select></div>
          <div class="field"><label for="new-task-start">Start date</label><input class="input" id="new-task-start" type="date" name="startAt" /></div>
          <div class="field"><label for="new-task-due">Due date</label><input class="input" id="new-task-due" type="date" name="dueAt" /></div>
          <div class="field wide"><label for="new-task-labels">Labels</label><input class="input" id="new-task-labels" name="labels" value={board.newTaskLabels} placeholder="Design, Launch" /></div>
        </div>
      </div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (open = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>{pending ? 'Creating…' : 'Create task'}</button></div>
    </form>
  </div>
{/if}
