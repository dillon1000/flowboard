<script lang="ts">
  import { onMount } from 'svelte';

  let root: HTMLDivElement;
  let selection = $state('gray');
  let customColor = $state('#3b82f6');
  const color = $derived(selection === 'custom' ? customColor : selection);

  onMount(() => {
    const form = root.closest('form');
    const reset = (): void => {
      queueMicrotask(() => {
        selection = 'gray';
        customColor = '#3b82f6';
      });
    };
    form?.addEventListener('reset', reset);
    return () => form?.removeEventListener('reset', reset);
  });
</script>

<div class="workflow-color-field" bind:this={root}>
  <input type="hidden" name="color" value={color} />
  <select class="input" bind:value={selection} aria-label="Color">
    <option value="gray">Gray</option>
    <option value="blue">Blue</option>
    <option value="purple">Purple</option>
    <option value="green">Green</option>
    <option value="amber">Amber</option>
    <option value="orange">Orange</option>
    <option value="red">Red</option>
    <option value="custom">Custom color</option>
  </select>
  {#if selection === 'custom'}
    <span class="workflow-custom-color">
      <input type="color" bind:value={customColor} aria-label="Choose custom color" />
      <input class="input" bind:value={customColor} aria-label="Custom color hex value" pattern={'#[0-9A-Fa-f]{6}'} maxlength="7" required />
    </span>
  {/if}
</div>
