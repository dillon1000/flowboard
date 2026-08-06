<script lang="ts">
  import { dismissToast, toastQueue } from '$lib/ui/toast';
  import { CheckIcon as Check, WarningCircleIcon as WarningCircle, XIcon as X } from 'phosphor-svelte';
</script>

<div class="toast-stack" aria-label="Notifications">
  {#each $toastQueue as notice (notice.id)}
    <div class:error={notice.tone === 'error'} class="toast" role={notice.tone === 'error' ? 'alert' : 'status'} aria-live={notice.tone === 'error' ? 'assertive' : 'polite'}>
      {#if notice.tone === 'error'}<WarningCircle size={16} />{:else}<Check size={15} />{/if}
      <span>{notice.message}</span>
      <button type="button" onclick={() => dismissToast(notice.id)} aria-label="Dismiss notification"><X size={13} /></button>
    </div>
  {/each}
</div>
