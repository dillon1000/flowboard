<script lang="ts">
  import { SidebarSimpleIcon as PanelIcon } from 'phosphor-svelte';
  import { onMount } from 'svelte';

  let { label } = $props<{ label: string }>();
  let open = $state(true);

  onMount(() => {
    open = document.documentElement.dataset.panel !== 'collapsed';
    const sync = (event: StorageEvent): void => {
      if (event.key !== 'flowboard-panel') return;
      open = event.newValue !== 'collapsed';
      document.documentElement.dataset.panel = open ? 'expanded' : 'collapsed';
    };
    window.addEventListener('storage', sync);
    return () => window.removeEventListener('storage', sync);
  });

  function toggle(): void {
    open = !open;
    const value = open ? 'expanded' : 'collapsed';
    document.documentElement.dataset.panel = value;
    localStorage.setItem('flowboard-panel', value);
  }
</script>

<button
  class="icon-button context-panel-toggle"
  type="button"
  aria-pressed={open}
  aria-label={open ? `Hide ${label}` : `Show ${label}`}
  title={open ? `Hide ${label}` : `Show ${label}`}
  onclick={toggle}
>
  <PanelIcon size={16} />
</button>
