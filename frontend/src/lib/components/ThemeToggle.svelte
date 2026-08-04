<script lang="ts">
  import { MoonIcon as Moon, SunIcon as Sun } from 'phosphor-svelte';
  import { onMount } from 'svelte';

  let theme = $state<'light' | 'dark'>('light');

  function preferredTheme(): 'light' | 'dark' {
    const saved = localStorage.getItem('flowboard-theme');
    if (saved === 'light' || saved === 'dark') return saved;
    return matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  function applyTheme(nextTheme: 'light' | 'dark'): void {
    theme = nextTheme;
    document.documentElement.dataset.theme = nextTheme;
    document.querySelector<HTMLMetaElement>('meta[name="theme-color"]')?.setAttribute(
      'content',
      nextTheme === 'dark' ? '#0a0a0a' : '#ffffff'
    );
  }

  onMount(() => {
    applyTheme(preferredTheme());
    const colorScheme = matchMedia('(prefers-color-scheme: dark)');
    const syncSystemTheme = (): void => {
      if (!localStorage.getItem('flowboard-theme')) applyTheme(colorScheme.matches ? 'dark' : 'light');
    };
    const syncStoredTheme = (event: StorageEvent): void => {
      if (event.key === 'flowboard-theme') applyTheme(preferredTheme());
    };
    colorScheme.addEventListener('change', syncSystemTheme);
    window.addEventListener('storage', syncStoredTheme);
    return () => {
      colorScheme.removeEventListener('change', syncSystemTheme);
      window.removeEventListener('storage', syncStoredTheme);
    };
  });

  function toggle(): void {
    const nextTheme = theme === 'dark' ? 'light' : 'dark';
    applyTheme(nextTheme);
    localStorage.setItem('flowboard-theme', nextTheme);
  }
</script>

<button class="icon-button theme-button" type="button" onclick={toggle} aria-label="Change color theme" title="Change color theme">
  {#if theme === 'dark'}<Sun size={16} />{:else}<Moon size={16} />{/if}
  <span class="sr-only">Use {theme === 'dark' ? 'light' : 'dark'} theme</span>
</button>
