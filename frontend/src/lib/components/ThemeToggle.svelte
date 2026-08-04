<script lang="ts">
  import { Moon, Sun } from '@lucide/svelte';
  import { onMount } from 'svelte';

  let theme = $state<'light' | 'dark'>('light');

  onMount(() => {
    theme = document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light';
  });

  function toggle(): void {
    theme = theme === 'dark' ? 'light' : 'dark';
    document.documentElement.dataset.theme = theme;
    localStorage.setItem('flowboard-theme', theme);
  }
</script>

<button class="icon-button theme-button" type="button" onclick={toggle} aria-label="Change color theme" title="Change color theme">
  {#if theme === 'dark'}<Sun size={16} />{:else}<Moon size={16} />{/if}
  <span class="sr-only">Use {theme === 'dark' ? 'light' : 'dark'} theme</span>
</button>
