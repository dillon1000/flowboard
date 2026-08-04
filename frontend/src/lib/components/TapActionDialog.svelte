<script lang="ts">
  import { invalidateAll } from '$app/navigation';
  import { api, messageFor } from '$lib/api';
  import type { BoardSettingsPageContext, TapActionContext } from '$lib/types';
  import { X } from '@lucide/svelte';
  import { dialogLayer } from '$lib/actions/dialogLayer';

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

  $effect(() => {
    if (open) kind = action?.kind === 'update_task' ? 'update_task' : 'create_task';
  });

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
      await invalidateAll();
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
          <div class="field"><label for="tap-kind">Action</label><select class="input" id="tap-kind" name="kind" bind:value={kind}><option value="create_task">Create task</option><option value="update_task">Update task</option></select></div>
          <div class="field wide"><label for="tap-description">Phone instructions</label><input class="input" id="tap-description" name="displayDescription" value={action?.displayDescription ?? ''} maxlength="280" /></div>
          {#if kind === 'create_task'}
            <div class="field wide"><span class="field-label">Scanner input</span><span class="field-help">The person who scans this tag enters the task title, description, dates, labels, and board fields on their phone.</span></div>
            <div class="field"><label for="tap-priority">Default severity</label><select class="input" id="tap-priority" name="priority" value={action?.severity ?? board.defaultTapSeverity}>{#each board.severities as option}<option value={option.value}>{option.name}</option>{/each}</select></div>
          {:else}
            <div class="field wide"><label for="tap-target">Target task</label><select class="input" id="tap-target" name="targetTaskID" value={action?.targetTaskID ?? ''} required><option value="">Select a task</option>{#each board.tapTasks as task}<option value={task.id}>{task.title}</option>{/each}</select>{#if !board.hasTapTasks}<span class="field-help">Create a task before you select this action.</span>{/if}</div>
          {/if}
          <div class="field"><label for="tap-status">Status</label><select class="input" id="tap-status" name="status" value={action?.status ?? board.defaultTapStatus}>{#each board.statuses as option}<option value={option.value}>{option.name}</option>{/each}</select></div>
          <div class="field"><label for="tap-expiration">Expiration date</label><input class="input" id="tap-expiration" type="date" name="expiresAt" value={action?.expiresAtInput ?? ''} /></div>
          <div class="field"><label for="tap-uses">Maximum uses</label><input class="input" id="tap-uses" type="number" name="maxUses" min="1" value={action?.maxUses ?? ''} /></div>
          <div class="field"><label for="tap-cooldown">Cooldown in seconds</label><input class="input" id="tap-cooldown" type="number" name="cooldownSeconds" min="0" max="300" value={action?.cooldownSeconds ?? 3} /></div>
        </div>
      </div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (open = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>{pending ? 'Saving…' : action ? 'Save action' : 'Create action'}</button></div>
    </form>
  </div>
{/if}
