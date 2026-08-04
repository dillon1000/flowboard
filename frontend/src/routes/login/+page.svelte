<script lang="ts">
  import AuthPage from '$lib/components/AuthPage.svelte';
  let { data, form } = $props();
</script>

<AuthPage mode="login" configuration={data.configuration} {form} />
