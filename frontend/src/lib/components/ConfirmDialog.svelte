<script lang="ts">
  import { onMount } from 'svelte';
  import { X } from '@lucide/svelte';

  export let title: string;
  export let message: string;
  export let confirmLabel = 'Delete';
  export let busy = false;
  export let oncancel: () => void;
  export let onconfirm: () => void;

  let panel: HTMLDivElement;

  onMount(() => {
    panel.focus();
  });

  function keydown(event: KeyboardEvent): void {
    if (event.key === 'Escape' && !busy) {
      oncancel();
    }
  }
</script>

<div class="modal-backdrop" role="presentation" on:mousedown={(event) => {
  if (event.target === event.currentTarget && !busy) oncancel();
}}>
  <div
    class="modal-panel confirm-panel"
    role="dialog"
    aria-modal="true"
    aria-labelledby="confirm-title"
    tabindex="-1"
    bind:this={panel}
    on:keydown={keydown}
  >
    <header class="modal-header">
      <h2 id="confirm-title">{title}</h2>
      <button type="button" class="icon-button" on:click={oncancel} disabled={busy} aria-label="Close">
        <X size={17} />
      </button>
    </header>
    <div class="confirm-body">
      <p>{message}</p>
    </div>
    <footer class="modal-footer">
      <button type="button" class="button secondary-button" on:click={oncancel} disabled={busy}>
        Cancel
      </button>
      <button type="button" class="button danger-button" on:click={onconfirm} disabled={busy}>
        {busy ? 'Deleting…' : confirmLabel}
      </button>
    </footer>
  </div>
</div>
