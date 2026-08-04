<script lang="ts">
  import type { AppPageContext } from '$lib/types';
  import AppShell from '$lib/components/AppShell.svelte';
  import BoardPage from './BoardPage.svelte';
  import OverviewPage from './OverviewPage.svelte';
  import TasksPage from './TasksPage.svelte';

  let { context } = $props<{ context: AppPageContext }>();
</script>

<svelte:head><title>{context.documentTitle}</title></svelte:head>

<AppShell {context}>
  {#if context.isOverview && context.overview}
    <OverviewPage overview={context.overview} />
  {:else if context.isTasks && context.tasks}
    <TasksPage tasks={context.tasks} archived={context.isArchivedTasks} />
  {:else if context.isBoard && context.board}
    <BoardPage board={context.board} />
  {:else}
    <div class="page"><header class="page-header"><div class="page-title"><h1>{context.pageTitle}</h1></div></header></div>
  {/if}
</AppShell>
