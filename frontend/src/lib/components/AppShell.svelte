<script lang="ts">
  import type { AppPageContext, BoardNavigationContext } from '$lib/types';
  import type { Snippet } from 'svelte';
  import { onMount } from 'svelte';
  import { ArchiveIcon as Archive, CalendarDotsIcon as CalendarDays, CheckSquareIcon as CheckSquare, FolderIcon as Folder, SidebarSimpleIcon as PanelLeft, PlusIcon as Plus, MagnifyingGlassIcon as Search, GearIcon as Settings } from 'phosphor-svelte';
  import Avatar from './Avatar.svelte';
  import BuildSignature from './BuildSignature.svelte';
  import CreateBoardDialog from './CreateBoardDialog.svelte';
  import ThemeToggle from './ThemeToggle.svelte';
  import TaskPreview from './TaskPreview.svelte';
  import Toast from './Toast.svelte';

  let { context, children } = $props<{ context: AppPageContext; children: Snippet }>();
  let createBoardOpen = $state(false);
  let sidebarOpen = $state(false);
  let collapsed = $state(false);
  let hydrated = $state(false);
  let searchInput: HTMLInputElement;
  const activeBoards = $derived(
    context.common.boards.filter((board: BoardNavigationContext) => !board.isArchived)
  );

  onMount(() => {
    hydrated = true;
    collapsed = document.documentElement.dataset.sidebar === 'collapsed';
    const syncSidebar = (event: StorageEvent): void => {
      if (event.key !== 'flowboard-sidebar') return;
      collapsed = event.newValue === 'collapsed';
      document.documentElement.dataset.sidebar = collapsed ? 'collapsed' : 'expanded';
    };
    window.addEventListener('storage', syncSidebar);
    return () => window.removeEventListener('storage', syncSidebar);
  });

  function toggleSidebar(): void {
    if (matchMedia('(max-width: 900px)').matches) {
      sidebarOpen = !sidebarOpen;
      return;
    }
    collapsed = !collapsed;
    const value = collapsed ? 'collapsed' : 'expanded';
    document.documentElement.dataset.sidebar = value;
    localStorage.setItem('flowboard-sidebar', value);
  }

  function handleShortcut(event: KeyboardEvent): void {
    if (event.key === 'Escape' && document.activeElement === searchInput) {
      searchInput.value = '';
      searchInput.blur();
      return;
    }
    if (!(event.metaKey || event.ctrlKey)) return;
    if (event.key.toLowerCase() === 'b') {
      event.preventDefault();
      toggleSidebar();
    }
    if (event.key.toLowerCase() === 'k') {
      event.preventDefault();
      searchInput?.focus();
    }
  }

</script>

<svelte:window onkeydown={handleShortcut} />

<div class:study-overview-page={context.isOverview} class="app-shell" data-hydrated={hydrated ? 'true' : undefined}>
  <aside class="sidebar" data-open={sidebarOpen ? 'true' : undefined}>
    <div class="brand-row">
      <a class="brand" href="/app" aria-label="Flowboard home">
        <img class="brand-logo" src={context.isOverview || collapsed ? '/focalboard-fb-abbreviation-tp.webp' : '/focalboard-wordmark.webp'} alt="" width="104" height="14" />
      </a>
    </div>

    <div class="sidebar-section">
      <nav class="main-nav" aria-label="Primary navigation">
        <a class:active={context.isOverview} class="nav-link" href="/app" aria-current={context.isOverview ? 'page' : undefined} title="This week">
          <CalendarDays size={16} /><span>This week</span>
        </a>
        <a class:active={context.isSemester} class="nav-link" href="/app/semester" aria-current={context.isSemester ? 'page' : undefined} title="Semester">
          <CalendarDays size={16} /><span>Semester</span>
        </a>
        <a class:active={context.isActiveTasks} class="nav-link" href="/app/tasks" aria-current={context.isActiveTasks ? 'page' : undefined} title="All assignments">
          <CheckSquare size={16} /><span>All assignments</span>
        </a>
        <a class:active={context.isArchivedTasks} class="nav-link" href="/app/tasks/archived" aria-current={context.isArchivedTasks ? 'page' : undefined} title="Archived assignments">
          <Archive size={16} /><span>Archived assignments</span>
        </a>
      </nav>
    </div>

    {#if !context.isOverview}
      <div class="boards-nav">
        <div class="nav-section-header">
          <span>Courses</span>
          <button class="icon-button" type="button" onclick={() => (createBoardOpen = true)} aria-label="Add course" title="Add course"><Plus size={14} /></button>
        </div>
        <nav aria-label="Courses">
          {#each activeBoards as board (board.id)}
            <a class="nav-link" href={board.href} title={board.name} onclick={() => (sidebarOpen = false)}>
              <Folder size={16} /><span>{board.name}</span><small>{board.taskCount}</small>
            </a>
          {/each}
        </nav>
      </div>
    {/if}

    <div class="sidebar-spacer"></div>
    <BuildSignature />
    <nav class="settings-nav">
      <a class:active={context.isSettings} class="nav-link" href="/app/settings" aria-current={context.isSettings ? 'page' : undefined} title="Settings">
        <Settings size={16} /><span>Settings</span>
      </a>
    </nav>
    <a class="user-row" href="/app/settings" title={context.common.userName}>
      <Avatar avatar={context.common.userAvatar} />
      <span><strong>{context.common.userName}</strong><small>{context.common.userEmail}</small></span>
    </a>
  </aside>

  <button class="sidebar-scrim" type="button" aria-label="Close navigation" onclick={() => (sidebarOpen = false)} hidden={!sidebarOpen}></button>

  <main class="workspace">
    <header class="topbar">
      <button class="icon-button menu-button" type="button" onclick={toggleSidebar} title="Toggle sidebar (⌘B)">
        <PanelLeft size={16} /><span class="sr-only">Toggle sidebar</span>
      </button>
      <nav class="breadcrumbs" aria-label="Breadcrumb">
        <a href="/app">Workspace</a><span class="separator" aria-hidden="true">/</span>
        {#if context.isTaskDetail && context.taskDetail}
          <a href={context.taskDetail.boardHref}>{context.taskDetail.boardName}</a><span class="separator" aria-hidden="true">/</span>
        {/if}
        <span aria-current="page">{context.pageTitle}</span>
      </nav>
      <div class="topbar-actions">
        <form class="search-control" method="get" action="/app/tasks" role="search">
          <Search size={16} /><input bind:this={searchInput} name="q" aria-label="Search tasks" placeholder="Search tasks" /><kbd>⌘ K</kbd>
        </form>
        <ThemeToggle />
      </div>
    </header>
    {@render children()}
  </main>
</div>

<CreateBoardDialog bind:open={createBoardOpen} />
<TaskPreview />
<Toast />
