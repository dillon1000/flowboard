<script lang="ts">
  import { dialogLayer } from '$lib/actions/dialogLayer';

  let {
    open,
    title,
    description,
    confirmLabel,
    pendingLabel = 'Working…',
    tone = 'danger',
    oncancel,
    onconfirm
  } = $props<{
    open: boolean;
    title: string;
    description: string;
    confirmLabel: string;
    pendingLabel?: string;
    tone?: 'danger' | 'primary';
    oncancel: () => void;
    onconfirm: () => boolean | void | Promise<boolean | void>;
  }>();

  let pending = $state(false);

  function cancel(): void {
    if (!pending) oncancel();
  }

  /** Runs one state-changing action and keeps the dialog open after a failure. */
  async function confirm(): Promise<void> {
    if (pending) return;
    pending = true;
    try {
      const succeeded = await onconfirm();
      if (succeeded !== false) oncancel();
    } finally {
      pending = false;
    }
  }
</script>

{#if open}
  <div class="dialog-layer" role="alertdialog" aria-modal="true" aria-label={title} tabindex="-1" use:dialogLayer={{ close: cancel, closeOnBackdrop: false }}>
    <div class="dialog compact confirm-dialog">
      <div class="dialog-header"><div><h2>{title}</h2><p>{description}</p></div></div>
      <div class="dialog-footer"><button class="button" type="button" onclick={cancel} disabled={pending} data-dialog-focus>Cancel</button><button class:danger={tone === 'danger'} class:primary={tone === 'primary'} class="button" type="button" onclick={confirm} disabled={pending}>{pending ? pendingLabel : confirmLabel}</button></div>
    </div>
  </div>
{/if}
