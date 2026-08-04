<script lang="ts">
  import WorkspacePage from '$lib/pages/WorkspacePage.svelte';
  let { data } = $props();
</script>

<WorkspacePage context={data.context} descriptionHTML={data.descriptionHTML} />
