<script lang="ts">
  import { api, messageFor, refreshAll } from '$lib/api';
  import type { BoardSettingsPageContext, TapActionContext, TapTaskOptionContext, TaskOptionContext } from '$lib/types';
  import { XIcon as X } from 'phosphor-svelte';
  import { dialogLayer } from '$lib/actions/dialogLayer';
  import DatePicker from './DatePicker.svelte';
  import SelectMenu, { type SelectMenuOption } from './SelectMenu.svelte';

  let {
    open = $bindable(false),
    board,
    action = null,
    onprovision
  } = $props<{
    open: boolean;
    board: BoardSettingsPageContext;
    action?: TapActionContext | null;
    onprovision: (url: string) => void;
  }>();
  let pending = $state(false);
  let requestError = $state('');
  let kind = $state<'create_task' | 'update_task'>('create_task');
  const kindOptions: SelectMenuOption[] = [
    { value: 'create_task', label: 'Create task' },
    { value: 'update_task', label: 'Update task' }
  ];
  const severityOptions = $derived<SelectMenuOption[]>(
    board.severities.map((option: TaskOptionContext) => ({ value: option.value, label: option.name }))
  );
  const statusOptions = $derived<SelectMenuOption[]>(
    board.statuses.map((option: TaskOptionContext) => ({ value: option.value, label: option.name }))
  );
  const taskOptions = $derived<SelectMenuOption[]>([
    { value: '', label: 'Select a task' },
    ...board.tapTasks.map((task: TapTaskOptionContext) => ({ value: task.id, label: task.title }))
  ]);

  $effect(() => {
    if (open) kind = action?.kind === 'update_task' ? 'update_task' : 'create_task';
  });

  function selectKind(value: string): void {
    kind = value === 'update_task' ? 'update_task' : 'create_task';
  }

  async function submit(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const targetTaskID = String(data.get('targetTaskID') ?? '');
    const expiresAt = String(data.get('expiresAt') ?? '');
    const maxUses = String(data.get('maxUses') ?? '');
    const input = {
      name: String(data.get('name') ?? ''),
      displayDescription: String(data.get('displayDescription') ?? '') || null,
      kind,
      targetTaskID: kind === 'update_task' ? targetTaskID || null : null,
      status: String(data.get('status') ?? board.defaultTapStatus),
      priority: kind === 'create_task' ? String(data.get('priority') ?? board.defaultTapSeverity) : null,
      expiresAt: expiresAt ? `${expiresAt}T23:59:59Z` : null,
      maxUses: maxUses ? Number(maxUses) : null,
      cooldownSeconds: Number(data.get('cooldownSeconds') ?? 3)
    };

    pending = true;
    requestError = '';
    try {
      const result = await api<{ url?: string }>(
        action
          ? `/api/v1/boards/${board.id}/tap-actions/${action.id}`
          : `/api/v1/boards/${board.id}/tap-actions`,
        { method: action ? 'PATCH' : 'POST', body: JSON.stringify(input) }
      );
      if (result.url) onprovision(result.url);
      open = false;
      await refreshAll();
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pending = false;
    }
  }
</script>

{#if open}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="tap-action-title" tabindex="-1" use:dialogLayer={{ close: () => (open = false) }}>
    <form class="dialog wide" onsubmit={submit}>
      <div class="dialog-header"><div><h2 id="tap-action-title">{action ? `Edit ${action.name}` : 'New Tap action'}</h2><p>A bearer link can run only this fixed action.</p></div><button class="icon-button" type="button" onclick={() => (open = false)} aria-label="Close"><X size={16} /></button></div>
      <div class="dialog-body">
        {#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}
        <div class="form-grid">
          <div class="field"><label for="tap-name">Name</label><input class="input" id="tap-name" name="name" value={action?.name ?? ''} maxlength="80" required data-dialog-focus /></div>
          <div class="field"><label for="tap-kind">Action</label><SelectMenu id="tap-kind" name="kind" value={kind} options={kindOptions} ariaLabel="Action" onchange={selectKind} /></div>
          <div class="field wide"><label for="tap-description">Phone instructions</label><input class="input" id="tap-description" name="displayDescription" value={action?.displayDescription ?? ''} maxlength="280" /></div>
          {#if kind === 'create_task'}
            <div class="field wide"><span class="field-label">Scanner input</span><span class="field-help">The person who scans this tag enters the task title, description, dates, labels, and board fields on their phone.</span></div>
            <div class="field"><label for="tap-priority">Default severity</label><SelectMenu id="tap-priority" name="priority" value={action?.severity ?? board.defaultTapSeverity} options={severityOptions} ariaLabel="Default severity" /></div>
          {:else}
            <div class="field wide"><label for="tap-target">Target task</label><SelectMenu id="tap-target" name="targetTaskID" value={action?.targetTaskID ?? ''} options={taskOptions} ariaLabel="Target task" />{#if !board.hasTapTasks}<span class="field-help">Create a task before you select this action.</span>{/if}</div>
          {/if}
          <div class="field"><label for="tap-status">Status</label><SelectMenu id="tap-status" name="status" value={action?.status ?? board.defaultTapStatus} options={statusOptions} ariaLabel="Status" /></div>
          <div class="field"><label for="tap-expiration">Expiration date</label><DatePicker id="tap-expiration" name="expiresAt" value={action?.expiresAtInput ?? ''} label="Expiration date" placeholder="Never" /></div>
          <div class="field"><label for="tap-uses">Maximum uses</label><input class="input" id="tap-uses" type="number" name="maxUses" min="1" value={action?.maxUses ?? ''} /></div>
          <div class="field"><label for="tap-cooldown">Cooldown in seconds</label><input class="input" id="tap-cooldown" type="number" name="cooldownSeconds" min="0" max="300" value={action?.cooldownSeconds ?? 3} /></div>
        </div>
      </div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (open = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>{pending ? 'Saving…' : action ? 'Save action' : 'Create action'}</button></div>
    </form>
  </div>
{/if}
