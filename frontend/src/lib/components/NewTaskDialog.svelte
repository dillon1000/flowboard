<script lang="ts">
  import { invalidateAll } from '$app/navigation';
  import { api, messageFor } from '$lib/api';
  import type { BoardPageContext, TaskOptionContext, TaskResponse } from '$lib/types';
  import { XIcon as X } from 'phosphor-svelte';
  import { dialogLayer } from '$lib/actions/dialogLayer';
  import { showToast } from '$lib/ui/toast';
  import DatePicker from './DatePicker.svelte';
  import TimePicker from './TimePicker.svelte';
  import SelectMenu, { type SelectMenuOption } from './SelectMenu.svelte';

  let { open = $bindable(false), board } = $props<{ open: boolean; board: BoardPageContext }>();
  let pending = $state(false);
  let requestError = $state('');
  const statusOptions = $derived<SelectMenuOption[]>(
    board.statusOptions.map((option: TaskOptionContext) => ({ value: option.value, label: option.name }))
  );
  const severityOptions = $derived<SelectMenuOption[]>(
    board.severityOptions.map((option: TaskOptionContext) => ({ value: option.value, label: option.name }))
  );

  function apiDate(value: FormDataEntryValue | null): string | null {
    const date = String(value ?? '');
    return date ? `${date}T00:00:00Z` : null;
  }

  function estimateMinutes(value: FormDataEntryValue | null): number | null {
    const minutes = Number(value);
    return Number.isInteger(minutes) && minutes > 0 ? minutes : null;
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
          dueAt: apiDate(data.get('dueAt')),
          dueTime: data.get('dueAt') ? String(data.get('dueTime') ?? '') || null : null,
          estimatedMinutes: estimateMinutes(data.get('estimatedMinutes'))
        })
      });
      form.reset();
      open = false;
      await invalidateAll();
      showToast('Task created');
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
          <div class="field wide"><label for="new-task-description">Description</label><textarea class="textarea" id="new-task-description" name="description" maxlength="5000">{board.newTaskDescription}</textarea></div>
          <div class="field"><label for="new-task-status">Status</label><SelectMenu id="new-task-status" name="status" value={board.newTaskStatus} options={statusOptions} ariaLabel="Status" /></div>
          <div class="field"><label for="new-task-priority">Severity</label><SelectMenu id="new-task-priority" name="priority" value={board.newTaskPriority} options={severityOptions} ariaLabel="Severity" /></div>
          <div class="field"><label for="new-task-start">Start date</label><DatePicker id="new-task-start" name="startAt" label="Start date" /></div>
          <div class="field"><label for="new-task-due">Due date</label><DatePicker id="new-task-due" name="dueAt" label="Due date" /></div>
          <div class="field"><label for="new-task-time">Due time</label><TimePicker id="new-task-time" name="dueTime" label="Due time" /></div>
          <div class="field"><label for="new-task-estimate">Time estimate</label><input class="input" id="new-task-estimate" name="estimatedMinutes" type="number" min="5" max="1440" step="5" inputmode="numeric" placeholder="Minutes" /><span class="field-help">Use minutes, such as 45 or 120.</span></div>
          <div class="field wide"><label for="new-task-labels">Labels</label><input class="input" id="new-task-labels" name="labels" value={board.newTaskLabels} maxlength="500" placeholder="Design, Launch" /></div>
        </div>
      </div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (open = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>{pending ? 'Creating…' : 'Create task'}</button></div>
    </form>
  </div>
{/if}
