<script lang="ts">
  import type { Instance as FlatpickrInstance } from 'flatpickr/dist/types/instance';
  import { onMount } from 'svelte';

  let {
    id,
    name,
    value = '',
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

  let input: HTMLInputElement;
  let picker: FlatpickrInstance | undefined;

  onMount(() => {
    let disposed = false;
    void import('flatpickr').then(({ default: flatpickr }) => {
      if (disposed) return;
      picker = flatpickr(input, {
        allowInput: false,
        altInput: true,
        altInputClass: 'input',
        altFormat: 'h:i K',
        dateFormat: 'H:i',
        defaultDate: value || undefined,
        disableMobile: true,
        enableTime: true,
        noCalendar: true,
        time_24hr: false
      });
      picker.altInput?.setAttribute('aria-label', label);
    });
    return () => {
      disposed = true;
      picker?.destroy();
    };
  });

  $effect(() => {
    if (picker && input.value !== value) picker.setDate(value || undefined, false);
  });
</script>

<input
  bind:this={input}
  class="input"
  type="text"
  {id}
  {name}
  {value}
  {placeholder}
  {disabled}
  autocomplete="off"
/>
