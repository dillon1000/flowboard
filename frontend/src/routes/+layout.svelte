<script lang="ts">
  import '@fontsource-variable/rubik';
  import '@fontsource-variable/geist-mono';
  import IconContext from 'phosphor-svelte/lib/IconContext';
  import '../app.css';

  let { children } = $props();
</script>

<!-- All Phosphor icons inherit the duotone weight unless a component explicitly overrides it. -->
<IconContext values={{ weight: 'duotone' }}>
  {@render children()}
</IconContext>
