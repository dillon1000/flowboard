<script lang="ts">
  import { onMount } from 'svelte';
  import { Check, ChevronDown } from '@lucide/svelte';

  export interface SelectOption<T extends string> {
    value: T;
    label: string;
  }

  export let label: string;
  export let value: string;
  export let options: SelectOption<string>[];
  export let onchange: (value: string) => void;

  let root: HTMLDivElement;
  let open = false;

  $: selected = options.find((option) => option.value === value) ?? options[0];

  onMount(() => {
    function closeOutside(event: MouseEvent): void {
      if (open && !root.contains(event.target as Node)) {
        open = false;
      }
    }

    document.addEventListener('mousedown', closeOutside);
    return () => document.removeEventListener('mousedown', closeOutside);
  });

  function choose(nextValue: string): void {
    onchange(nextValue);
    open = false;
  }

  function keydown(event: KeyboardEvent): void {
    if (event.key === 'Escape') {
      open = false;
      return;
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      const currentIndex = options.findIndex((option) => option.value === value);
      const direction = event.key === 'ArrowDown' ? 1 : -1;
      const nextIndex = (currentIndex + direction + options.length) % options.length;
      choose(options[nextIndex].value);
    }
  }
</script>

<div class="select-field" bind:this={root}>
  <span class="field-label">{label}</span>
  <button
    type="button"
    class="select-trigger"
    aria-haspopup="listbox"
    aria-expanded={open}
    on:click={() => (open = !open)}
    on:keydown={keydown}
  >
    <span>{selected.label}</span>
    <ChevronDown size={15} strokeWidth={1.8} aria-hidden="true" />
  </button>

  {#if open}
    <div class="select-options" role="listbox" aria-label={label}>
      {#each options as option}
        <button
          type="button"
          role="option"
          aria-selected={option.value === value}
          on:click={() => choose(option.value)}
        >
          <span>{option.label}</span>
          {#if option.value === value}
            <Check size={14} strokeWidth={2} aria-hidden="true" />
          {/if}
        </button>
      {/each}
    </div>
  {/if}
</div>
