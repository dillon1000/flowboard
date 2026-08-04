<script lang="ts">
  import type { AppPageContext } from '$lib/types';
  import AppShell from '$lib/components/AppShell.svelte';
  import APIKeysPage from './APIKeysPage.svelte';
  import BoardPage from './BoardPage.svelte';
  import OverviewPage from './OverviewPage.svelte';
  import SettingsPage from './SettingsPage.svelte';
  import TaskDetailPage from './TaskDetailPage.svelte';
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
  {:else if context.isTaskDetail && context.taskDetail}
    <TaskDetailPage detail={context.taskDetail} currentUserAvatar={context.common.userAvatar} />
  {:else if context.isProfileSettings}
    <SettingsPage common={context.common} />
  {:else if context.isAPIKeys && context.apiKeys}
    <APIKeysPage keys={context.apiKeys} />
  {:else}
    <div class="page"><header class="page-header"><div class="page-title"><h1>{context.pageTitle}</h1></div></header></div>
  {/if}
</AppShell>
