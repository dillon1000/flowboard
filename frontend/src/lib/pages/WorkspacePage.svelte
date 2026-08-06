<script lang="ts">
  import type { AppPageContext } from '$lib/types';
  import AppShell from '$lib/components/AppShell.svelte';
  import APIKeysPage from './APIKeysPage.svelte';
  import BoardPage from './BoardPage.svelte';
  import BoardSettingsPage from './BoardSettingsPage.svelte';
  import IntegrationsPage from './IntegrationsPage.svelte';
  import OverviewPage from './OverviewPage.svelte';
  import SemesterPage from './SemesterPage.svelte';
  import SettingsPage from './SettingsPage.svelte';
  import TaskDetailPage from './TaskDetailPage.svelte';
  import TasksPage from './TasksPage.svelte';

  let { context, descriptionHTML = '' } = $props<{
    context: AppPageContext;
    descriptionHTML?: string;
  }>();
</script>

<svelte:head><title>{context.documentTitle}</title></svelte:head>

<AppShell {context}>
  {#if context.isOverview && context.overview}
    <OverviewPage overview={context.overview} common={context.common} />
  {:else if context.isSemester && context.semester}
    <SemesterPage semester={context.semester} />
  {:else if context.isTasks && context.tasks}
    <TasksPage tasks={context.tasks} archived={context.isArchivedTasks} />
  {:else if context.isBoard && context.board}
    <BoardPage board={context.board} />
  {:else if context.isTaskDetail && context.taskDetail}
    <TaskDetailPage detail={context.taskDetail} currentUserEmail={context.common.userEmail} {descriptionHTML} />
  {:else if context.isProfileSettings && context.settings}
    <SettingsPage common={context.common} settings={context.settings} />
  {:else if context.isAPIKeys && context.apiKeys}
    <APIKeysPage keys={context.apiKeys} />
  {:else if context.isIntegrations && context.integrations}
    <IntegrationsPage integrations={context.integrations} />
  {:else if context.isBoardSettings && context.boardSettings}
    <BoardSettingsPage board={context.boardSettings} />
  {:else}
    <div class="page"><header class="page-header"><div class="page-title"><h1>{context.pageTitle}</h1></div></header></div>
  {/if}
</AppShell>
