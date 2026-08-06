<script lang="ts">
  let {
    id,
    value = $bindable(''),
    label,
    placeholder = ''
  } = $props<{
    id: string;
    value?: string;
    label: string;
    placeholder?: string;
  }>();

  let input = $state<HTMLInputElement>();
  const labelCount = $derived(
    value.split(',').map((item: string) => item.trim()).filter(Boolean).length
  );

  $effect(() => {
    input?.setCustomValidity(labelCount > 6 ? 'Use no more than six labels.' : '');
  });
</script>

<div class="field wide">
  <label for={id}>{label}</label>
  <input
    bind:this={input}
    class="input"
    {id}
    name="labels"
    bind:value
    maxlength="500"
    {placeholder}
    aria-describedby={`${id}-help`}
    aria-invalid={labelCount > 6 ? 'true' : undefined}
  />
  <span class="field-help" id={`${id}-help`}>{labelCount}/6 labels. Separate labels with commas.</span>
</div>
