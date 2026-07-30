<script lang="ts">
  import { onMount } from 'svelte';
  import { X } from '@lucide/svelte';

  export let initialName = '';
  export let title = 'Create Board';
  export let submitLabel = 'Create Board';
  export let saving = false;
  export let onclose: () => void;
  export let onsave: (name: string) => void;

  let panel: HTMLDivElement;
  let nameInput: HTMLInputElement;
  let name = initialName;

  onMount(() => {
    panel.focus();
    nameInput.focus();
    nameInput.select();
  });

  function keydown(event: KeyboardEvent): void {
    if (event.key === 'Escape' && !saving) {
      onclose();
    }
  }
</script>

<div class="modal-backdrop" role="presentation" on:mousedown={(event) => {
  if (event.target === event.currentTarget && !saving) onclose();
}}>
  <div
    class="modal-panel board-dialog"
    role="dialog"
    aria-modal="true"
    aria-labelledby="board-dialog-title"
    tabindex="-1"
    bind:this={panel}
    on:keydown={keydown}
  >
    <form on:submit={(event) => {
      event.preventDefault();
      if (name.trim()) onsave(name.trim());
    }}>
      <header class="modal-header">
        <h2 id="board-dialog-title">{title}</h2>
        <button type="button" class="icon-button" on:click={onclose} disabled={saving} aria-label="Close">
          <X size={17} />
        </button>
      </header>
      <div class="modal-body">
        <label class="field field-wide">
          <span>Board Name</span>
          <input
            bind:this={nameInput}
            bind:value={name}
            name="board-name"
            autocomplete="off"
            maxlength="80"
            placeholder="Product roadmap…"
            required
          />
        </label>
      </div>
      <footer class="modal-footer">
        <button type="button" class="button secondary-button" on:click={onclose} disabled={saving}>
          Cancel
        </button>
        <button type="submit" class="button primary-button" disabled={saving}>
          {saving ? 'Saving…' : submitLabel}
        </button>
      </footer>
    </form>
  </div>
</div>
