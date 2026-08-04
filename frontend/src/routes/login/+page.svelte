<script lang="ts">
  import AuthPage from '$lib/components/AuthPage.svelte';
  let { data } = $props();
</script>

<AuthPage mode="login" configuration={data.configuration} />
