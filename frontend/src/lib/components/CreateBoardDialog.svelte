<script lang="ts">
  import { api, messageFor } from '$lib/api';
  import type { BoardResponse } from '$lib/types';
  import { goto, invalidateAll } from '$app/navigation';
  import { XIcon as X } from 'phosphor-svelte';
  import { dialogLayer } from '$lib/actions/dialogLayer';
  import { showToast } from '$lib/ui/toast';

  let { open = $bindable(false) } = $props<{ open: boolean }>();
  let pending = $state(false);
  let error = $state('');

  async function submit(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    pending = true;
    error = '';
    try {
      const board = await api<BoardResponse>('/api/v1/boards', {
        method: 'POST',
        body: JSON.stringify({
          name: String(data.get('name') ?? ''),
          description: String(data.get('description') ?? '') || null
        })
      });
      form.reset();
      open = false;
      await invalidateAll();
      showToast('Course added');
      await goto(`/app/boards/${board.id}`);
    } catch (cause) {
      error = messageFor(cause);
    } finally {
      pending = false;
    }
  }
</script>

{#if open}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="create-board-title" tabindex="-1" use:dialogLayer={{ close: () => (open = false) }}>
    <form class="dialog" onsubmit={submit}>
      <div class="dialog-header">
        <div>
          <h2 id="create-board-title">Add course</h2>
          <p>Create a course for assignments, views, and shared work.</p>
        </div>
        <button class="icon-button" type="button" onclick={() => (open = false)} aria-label="Close"><X size={16} /></button>
      </div>
      <div class="dialog-body">
        {#if error}<p class="error-message" role="alert">{error}</p>{/if}
        <div class="field">
          <label for="new-board-name">Course name</label>
          <input class="input" id="new-board-name" name="name" minlength="2" maxlength="80" required data-dialog-focus />
        </div>
        <div class="field">
          <label for="new-board-description">Description</label>
          <textarea class="textarea" id="new-board-description" name="description" maxlength="500"></textarea>
        </div>
      </div>
      <div class="dialog-footer">
        <button class="button" type="button" onclick={() => (open = false)}>Cancel</button>
        <button class="button primary" type="submit" disabled={pending}>{pending ? 'Adding…' : 'Add course'}</button>
      </div>
    </form>
  </div>
{/if}
