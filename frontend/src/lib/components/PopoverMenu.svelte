<script lang="ts">
  import { tick, type Snippet } from 'svelte';

  interface TriggerControl {
    open: boolean;
    toggle: () => void;
  }

  let {
    panelLabel,
    panelRole = 'menu',
    align = 'left',
    trigger,
    children
  } = $props<{
    panelLabel: string;
    panelRole?: 'menu' | 'listbox';
    align?: 'left' | 'right';
    trigger: Snippet<[TriggerControl]>;
    children: Snippet<[() => void]>;
  }>();

  let root: HTMLDivElement;
  let panel = $state<HTMLDivElement | undefined>();
  let open = $state(false);

  const itemSelector = '[role="option"], [role="menuitem"]';

  function options(): HTMLElement[] {
    return panel ? Array.from(panel.querySelectorAll<HTMLElement>(itemSelector)) : [];
  }

  async function showMenu(): Promise<void> {
    open = true;
    await tick();
    const items = options();
    (items.find((item) => item.getAttribute('aria-selected') === 'true') ?? items[0])?.focus();
  }

  function hideMenu(restoreFocus = false): void {
    if (!open) return;
    open = false;
    if (restoreFocus) root?.querySelector('button')?.focus();
  }

  function toggle(): void {
    if (open) hideMenu();
    else void showMenu();
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

  /** Arrow keys wrap through the panel so the menu is usable without a mouse. */
  function handlePanelKeydown(event: KeyboardEvent): void {
    if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return;
    event.preventDefault();
    const items = options();
    const index = items.indexOf(event.target as HTMLElement);
    const delta = event.key === 'ArrowDown' ? 1 : -1;
    items[(Math.max(0, index) + delta + items.length) % items.length]?.focus();
  }
</script>

<svelte:window onclick={handleOutsideClick} onkeydown={handleWindowKeydown} />

<div class="menu" bind:this={root}>
  {@render trigger({ open, toggle })}
  {#if open}
    <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
    <div
      bind:this={panel}
      class:right={align === 'right'}
      class="menu-panel"
      role={panelRole}
      aria-label={panelLabel}
      onkeydown={handlePanelKeydown}
    >
      {@render children(() => hideMenu(true))}
    </div>
  {/if}
</div>
