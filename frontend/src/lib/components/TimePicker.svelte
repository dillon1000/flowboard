<script lang="ts">
  import { CaretDownIcon as ChevronDown, ClockIcon as Clock } from 'phosphor-svelte';
  import { onMount, tick } from 'svelte';

  let {
    id,
    name,
    value = $bindable(''),
    label,
    placeholder = 'Choose a time',
    disabled = false
  } = $props<{
    id: string;
    name: string;
    value?: string;
    label: string;
    placeholder?: string;
    disabled?: boolean;
  }>();

  let root: HTMLDivElement;
  let trigger: HTMLButtonElement;
  let hourInput = $state<HTMLInputElement>();
  let open = $state(false);
  let draftHour = $state(12);
  let draftMinute = $state(0);
  let draftPeriod = $state<'AM' | 'PM'>('PM');
  const displayValue = $derived(formatTime(value));

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

  async function showPicker(): Promise<void> {
    if (disabled) return;
    const draft = parseTime(value);
    draftHour = draft.hour;
    draftMinute = draft.minute;
    draftPeriod = draft.period;
    open = true;
    await tick();
    hourInput?.focus();
    hourInput?.select();
  }

  function hidePicker(restoreFocus = false): void {
    if (!open) return;
    open = false;
    if (restoreFocus) trigger.focus();
  }

  function applyCustomTime(): void {
    const hour = Math.min(12, Math.max(1, Math.round(Number(draftHour) || 12)));
    const minute = Math.min(59, Math.max(0, Math.round(Number(draftMinute) || 0)));
    const hour24 = draftPeriod === 'AM' ? (hour === 12 ? 0 : hour) : (hour === 12 ? 12 : hour + 12);
    value = `${String(hour24).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
    hidePicker(true);
  }

  function choosePreset(nextValue: string): void {
    value = nextValue;
    hidePicker(true);
  }

  function clearTime(): void {
    value = '';
    hidePicker(true);
  }

  function handleOutsideClick(event: MouseEvent): void {
    if (open && !root.contains(event.target as Node)) hidePicker();
  }

  function handleWindowKeydown(event: KeyboardEvent): void {
    if (event.key !== 'Escape' || !open) return;
    event.preventDefault();
    hidePicker(true);
  }

  function parseTime(rawValue: string): { hour: number; minute: number; period: 'AM' | 'PM' } {
    const [rawHour = '12', rawMinute = '0'] = rawValue.split(':');
    const hour24 = Math.min(23, Math.max(0, Number(rawHour) || 0));
    return {
      hour: hour24 % 12 || 12,
      minute: Math.min(59, Math.max(0, Number(rawMinute) || 0)),
      period: hour24 >= 12 ? 'PM' : 'AM'
    };
  }

  function formatTime(rawValue: string): string {
    if (!rawValue) return '';
    const time = parseTime(rawValue);
    return `${time.hour}:${String(time.minute).padStart(2, '0')} ${time.period}`;
  }
</script>

<svelte:window onclick={handleOutsideClick} onkeydown={handleWindowKeydown} />

<div class="time-picker" bind:this={root}>
  <input type="hidden" {name} {value} />
  <button bind:this={trigger} class="time-picker-trigger" type="button" {id} {disabled} aria-label={label} aria-haspopup="dialog" aria-expanded={open} onclick={() => (open ? hidePicker() : void showPicker())}>
    <span class:placeholder={!displayValue}><Clock size={14} />{displayValue || placeholder}</span><ChevronDown size={13} />
  </button>
  {#if open}
    <div class="time-picker-panel" role="dialog" aria-label={label}>
      <div class="time-picker-heading"><strong>{label}</strong><span>Local time</span></div>
      <div class="time-picker-presets" aria-label="Common times"><button type="button" onclick={() => choosePreset('09:00')}><strong>9:00</strong><span>Morning</span></button><button type="button" onclick={() => choosePreset('12:00')}><strong>12:00</strong><span>Noon</span></button><button type="button" onclick={() => choosePreset('15:00')}><strong>3:00</strong><span>Afternoon</span></button><button type="button" onclick={() => choosePreset('18:00')}><strong>6:00</strong><span>Evening</span></button></div>
      <div class="time-picker-custom"><label><span>Hour</span><input bind:this={hourInput} bind:value={draftHour} type="number" min="1" max="12" inputmode="numeric" /></label><span class="time-picker-separator">:</span><label><span>Minute</span><input bind:value={draftMinute} type="number" min="0" max="59" step="5" inputmode="numeric" /></label><div class="time-picker-period" aria-label="Period"><button class:active={draftPeriod === 'AM'} type="button" onclick={() => (draftPeriod = 'AM')}>AM</button><button class:active={draftPeriod === 'PM'} type="button" onclick={() => (draftPeriod = 'PM')}>PM</button></div></div>
      <div class="time-picker-footer"><button class="button ghost small" type="button" onclick={clearTime}>Clear</button><button class="button primary small" type="button" onclick={applyCustomTime}>Use time</button></div>
    </div>
  {/if}
</div>
