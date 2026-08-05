<script lang="ts">
  import { CheckIcon as Check, CaretDownIcon as ChevronDown } from 'phosphor-svelte';
  import { onMount } from 'svelte';

  type ColorPickerElement = HTMLElement & { color: string };

  let { value = 'gray' } = $props<{ value?: string }>();
  let root: HTMLDivElement;
  let trigger: HTMLButtonElement;
  let picker = $state<ColorPickerElement | undefined>();
  let pickerReady = false;
  let open = $state(false);
  let selection = $state('gray');
  let customColor = $state('#3b82f6');
  const color = $derived(selection === 'custom' ? customColor : selection);
  const presets = [
    { value: 'gray', label: 'Gray' },
    { value: 'blue', label: 'Blue' },
    { value: 'purple', label: 'Purple' },
    { value: 'green', label: 'Green' },
    { value: 'amber', label: 'Amber' },
    { value: 'orange', label: 'Orange' },
    { value: 'red', label: 'Red' }
  ];
  const selectionLabel = $derived(
    selection === 'custom'
      ? customColor.toUpperCase()
      : presets.find((preset) => preset.value === selection)?.label ?? 'Gray'
  );

  onMount(() => {
    selection = value.startsWith('#') ? 'custom' : value;
    customColor = value.startsWith('#') ? value : '#3b82f6';
    const form = root.closest('form');
    const reset = (): void => {
      queueMicrotask(() => {
        selection = value.startsWith('#') ? 'custom' : value;
        customColor = value.startsWith('#') ? value : '#3b82f6';
        open = false;
        if (pickerReady && picker) picker.color = customColor;
      });
    };
    form?.addEventListener('reset', reset);
    return () => {
      form?.removeEventListener('reset', reset);
    };
  });

  // The custom element must load in the browser for SSR. This action connects
  // each picker when its menu opens and removes its listener when it closes.
  function mountPicker(node: ColorPickerElement): { destroy: () => void } {
    let disposed = false;
    const colorChanged = (event: Event): void => {
      setCustomColor((event as CustomEvent<{ value: string }>).detail.value);
    };
    picker = node;
    void import('vanilla-colorful').then(() => {
      if (disposed) return;
      node.color = customColor;
      node.addEventListener('color-changed', colorChanged);
      pickerReady = true;
    });
    return {
      destroy: () => {
        disposed = true;
        pickerReady = false;
        node.removeEventListener('color-changed', colorChanged);
        if (picker === node) picker = undefined;
      }
    };
  }

  function setPreset(value: string): void {
    selection = value;
  }

  function setCustomColor(value: string): void {
    if (!/^#[0-9a-f]{6}$/i.test(value)) return;
    customColor = value.toLowerCase();
    selection = 'custom';
    if (pickerReady && picker && picker.color !== customColor) picker.color = customColor;
  }

  function typeHex(event: Event): void {
    const value = `#${(event.currentTarget as HTMLInputElement).value}`;
    if (/^#[0-9a-f]{6}$/i.test(value)) setCustomColor(value);
  }

  function handleOutsideClick(event: MouseEvent): void {
    if (open && !root.contains(event.target as Node)) open = false;
  }

  function handleKeydown(event: KeyboardEvent): void {
    if (event.key === 'Escape' && open) {
      event.preventDefault();
      open = false;
      trigger.focus();
    }
  }
</script>

<svelte:window onclick={handleOutsideClick} onkeydown={handleKeydown} />

<div class="workflow-color-field menu color-picker" bind:this={root}>
  <input type="hidden" name="color" value={color} />
  <button bind:this={trigger} class="select-trigger color-picker-trigger" type="button" aria-label="Color" aria-haspopup="dialog" aria-expanded={open} onclick={() => (open = !open)}>
    <span class="color-picker-swatch" data-color={selection} style={selection === 'custom' ? `--color-picker-value: ${customColor}` : undefined}></span>
    <span data-menu-target="value">{selectionLabel}</span><ChevronDown size={14} />
  </button>
  {#if open}
    <div class="menu-panel right color-picker-panel" role="dialog" aria-label="Choose workflow color">
      <span class="color-picker-title">Presets</span>
      <div class="color-picker-grid" role="listbox" aria-label="Preset colors">
        {#each presets as preset (preset.value)}
          <button class="color-picker-option" type="button" role="option" data-color={preset.value} aria-selected={selection === preset.value} onclick={() => setPreset(preset.value)}>
            <span class="color-picker-swatch" data-color={preset.value}></span><span>{preset.label}</span><Check size={14} />
          </button>
        {/each}
      </div>
      <div class="color-picker-custom">
        <span class="color-picker-title">Custom</span>
        <hex-color-picker class="color-picker-spectrum" use:mountPicker></hex-color-picker>
        <label class="color-picker-hex"><span>#</span><input aria-label="Custom color hex value" value={customColor.slice(1)} maxlength="6" pattern="[0-9A-Fa-f]{6}" oninput={typeHex} /></label>
      </div>
    </div>
  {/if}
</div>
