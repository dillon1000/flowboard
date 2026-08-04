<script lang="ts">
  import type { TaskOptionContext } from '$lib/types';
  import { ArrowUpRight, ChevronDown } from '@lucide/svelte';
  import { tick } from 'svelte';

  let {
    value,
    options,
    disabled = false,
    onchange
  } = $props<{
    value: string;
    options: TaskOptionContext[];
    disabled?: boolean;
    onchange: (value: string) => void;
  }>();

  let root: HTMLDivElement;
  let trigger: HTMLButtonElement;
  let open = $state(false);
  let optionButtons: HTMLButtonElement[] = [];

  async function showMenu(): Promise<void> {
    if (disabled) return;
    open = true;
    await tick();
    const selectedIndex = Math.max(0, options.findIndex((option: TaskOptionContext) => option.value === value));
    optionButtons[selectedIndex]?.focus();
  }

  function hideMenu(restoreFocus = false): void {
    if (!open) return;
    open = false;
    if (restoreFocus) trigger.focus();
  }

  function choose(option: TaskOptionContext): void {
    hideMenu(true);
    if (option.value !== value) onchange(option.value);
  }

  function handleOutsideClick(event: MouseEvent): void {
    if (open && !root.contains(event.target as Node)) hideMenu();
  }

  function handleWindowKeydown(event: KeyboardEvent): void {
    if (event.key === 'Escape' && open) {
      event.preventDefault();
      hideMenu(true);
    }
  }

  function handleOptionKeydown(event: KeyboardEvent, index: number): void {
    if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return;
    event.preventDefault();
    const delta = event.key === 'ArrowDown' ? 1 : -1;
    optionButtons[(index + delta + options.length) % options.length]?.focus();
  }
</script>

<svelte:window onclick={handleOutsideClick} onkeydown={handleWindowKeydown} />

<div class="menu promote-menu" bind:this={root}>
  <button
    bind:this={trigger}
    class="button primary"
    type="button"
    {disabled}
    aria-haspopup="listbox"
    aria-expanded={open}
    onclick={() => (open ? hideMenu() : void showMenu())}
  >
    <ArrowUpRight size={15} /><span>Promote</span><ChevronDown size={14} />
  </button>
  {#if open}
    <div class="menu-panel right" role="listbox" aria-label="Change task status">
      {#each options as option, index (option.value)}
        <button
          bind:this={optionButtons[index]}
          class="menu-option"
          type="button"
          role="option"
          aria-selected={option.value === value}
          onclick={() => choose(option)}
          onkeydown={(event) => handleOptionKeydown(event, index)}
        >
          <span class={`badge status ${option.colorClass}`} style={option.colorStyle}>{option.name}</span>
        </button>
      {/each}
    </div>
  {/if}
</div>
