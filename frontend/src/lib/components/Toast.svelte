<script lang="ts">
  import { toastMessage } from '$lib/ui/toast';
  import { CheckIcon as Check } from 'phosphor-svelte';
</script>

<div class="toast" data-visible={$toastMessage ? 'true' : undefined} role="status" aria-live="polite">
  {#if $toastMessage}<Check size={15} />{$toastMessage}{/if}
</div>
