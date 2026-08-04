<script lang="ts">
  import AuthPage from '$lib/components/AuthPage.svelte';
  let { data } = $props();
</script>

<AuthPage mode="register" configuration={data.configuration} />
