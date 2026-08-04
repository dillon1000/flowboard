<script lang="ts">
  import type { Instance as FlatpickrInstance } from 'flatpickr/dist/types/instance';
  import { onMount } from 'svelte';

  let {
    id,
    name,
    value = '',
    label,
    placeholder = 'Choose a date',
    required = false,
    disabled = false,
    initialFocus = false
  } = $props<{
    id: string;
    name: string;
    value?: string;
    label: string;
    placeholder?: string;
    required?: boolean;
    disabled?: boolean;
    initialFocus?: boolean;
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
        altFormat: 'M j, Y',
        dateFormat: 'Y-m-d',
        defaultDate: value || undefined,
        disableMobile: true,
        monthSelectorType: 'static',
        nextArrow: '<span aria-hidden="true">→</span>',
        prevArrow: '<span aria-hidden="true">←</span>'
      });
      picker.altInput?.setAttribute('aria-label', label);
      if (initialFocus) picker.altInput?.setAttribute('data-dialog-focus', '');
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
  {required}
  {disabled}
  autocomplete="off"
  data-dialog-focus={initialFocus ? '' : undefined}
/>
