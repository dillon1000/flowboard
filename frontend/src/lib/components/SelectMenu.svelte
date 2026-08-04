<script module lang="ts">
  export interface SelectMenuOption {
    value: string;
    label: string;
    disabled?: boolean;
  }
</script>

<script lang="ts">
  import { ChevronDown } from '@lucide/svelte';
  import { onMount, tick } from 'svelte';

  let {
    id,
    name,
    value = $bindable(''),
    options,
    ariaLabel,
    disabled = false,
    align = 'left',
    initialFocus = false,
    onchange
  } = $props<{
    id?: string;
    name: string;
    value?: string;
    options: SelectMenuOption[];
    ariaLabel?: string;
    disabled?: boolean;
    align?: 'left' | 'right';
    initialFocus?: boolean;
    onchange?: (value: string) => void;
  }>();

  let root: HTMLDivElement;
  let trigger: HTMLButtonElement;
  let open = $state(false);
  let optionButtons = $state<HTMLButtonElement[]>([]);
  const selectedOption = $derived(options.find((option: SelectMenuOption) => option.value === value));

  onMount(() => {
    const initialValue = value;
    const form = root.closest('form');
    const reset = (): void => {
      queueMicrotask(() => {
        value = initialValue;
        open = false;
      });
    };
    form?.addEventListener('reset', reset);
    return () => form?.removeEventListener('reset', reset);
  });

  async function showMenu(index?: number): Promise<void> {
    if (disabled) return;
    open = true;
    await tick();
    const selectedIndex = Math.max(0, options.findIndex((option: SelectMenuOption) => option.value === value));
    optionButtons[index ?? selectedIndex]?.focus();
  }

  function hideMenu(restoreFocus = false): void {
    if (!open) return;
    open = false;
    if (restoreFocus) trigger.focus();
  }

  function choose(option: SelectMenuOption): void {
    if (option.disabled) return;
    value = option.value;
    hideMenu(true);
    onchange?.(option.value);
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

  function handleTriggerKeydown(event: KeyboardEvent): void {
    if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return;
    event.preventDefault();
    void showMenu(event.key === 'ArrowDown' ? 0 : options.length - 1);
  }

  function handleOptionKeydown(event: KeyboardEvent, index: number): void {
    let nextIndex: number | null = null;
    if (event.key === 'ArrowDown') nextIndex = (index + 1) % options.length;
    if (event.key === 'ArrowUp') nextIndex = (index - 1 + options.length) % options.length;
    if (event.key === 'Home') nextIndex = 0;
    if (event.key === 'End') nextIndex = options.length - 1;
    if (nextIndex === null) return;
    event.preventDefault();
    optionButtons[nextIndex]?.focus();
  }
</script>

<svelte:window onclick={handleOutsideClick} onkeydown={handleWindowKeydown} />

<div class="menu" bind:this={root}>
  <input type="hidden" {name} {value} />
  <button
    bind:this={trigger}
    class="select-trigger"
    type="button"
    {id}
    {disabled}
    aria-label={ariaLabel}
    aria-haspopup="listbox"
    aria-expanded={open}
    data-dialog-focus={initialFocus ? '' : undefined}
    onclick={() => (open ? hideMenu() : void showMenu())}
    onkeydown={handleTriggerKeydown}
  >
    <span>{selectedOption?.label ?? 'Select an option'}</span><ChevronDown size={14} />
  </button>
  {#if open}
    <div class:right={align === 'right'} class="menu-panel" role="listbox" aria-label={ariaLabel}>
      {#each options as option, index (option.value)}
        <button
          bind:this={optionButtons[index]}
          class="menu-option"
          type="button"
          role="option"
          disabled={option.disabled}
          aria-selected={option.value === value}
          onclick={() => choose(option)}
          onkeydown={(event) => handleOptionKeydown(event, index)}
        >{option.label}</button>
      {/each}
    </div>
  {/if}
</div>
