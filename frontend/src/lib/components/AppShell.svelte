<script lang="ts">
  import { navigating } from '$app/state';
  import type { AppPageContext, BoardNavigationContext } from '$lib/types';
  import type { Snippet } from 'svelte';
  import { onMount } from 'svelte';
  import { ArchiveIcon as Archive, CalendarBlankIcon as SemesterCalendar, CalendarDotsIcon as CalendarDays, CheckSquareIcon as CheckSquare, FolderIcon as Folder, KeyboardIcon as Keyboard, SidebarSimpleIcon as PanelLeft, PlusIcon as Plus, MagnifyingGlassIcon as Search, GearIcon as Settings, XIcon as X } from 'phosphor-svelte';
  import { dialogLayer } from '$lib/actions/dialogLayer';
  import { activityCount } from '$lib/ui/progress';
  import Avatar from './Avatar.svelte';
  import BuildSignature from './BuildSignature.svelte';
  import CreateBoardDialog from './CreateBoardDialog.svelte';
  import ThemeToggle from './ThemeToggle.svelte';
  import TaskPreview from './TaskPreview.svelte';
  import Toast from './Toast.svelte';

  let { context, children } = $props<{ context: AppPageContext; children: Snippet }>();
  let createBoardOpen = $state(false);
  let sidebarOpen = $state(false);
  let mobileSearchOpen = $state(false);
  let shortcutsOpen = $state(false);
  let collapsed = $state(false);
  let hydrated = $state(false);
  let searchInput: HTMLInputElement;
  const shellBusy = $derived(Boolean(navigating.to) || $activityCount > 0);
  const activeBoards = $derived(
    context.common.boards.filter((board: BoardNavigationContext) => !board.isArchived)
  );
  const searchQuery = $derived(context.tasks?.query ?? '');

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
    if (document.querySelector('[role="dialog"][aria-modal="true"]')) return;
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
      openSearch();
    }
    if (event.key === '/') {
      event.preventDefault();
      shortcutsOpen = true;
    }
  }

  function openSearch(): void {
    if (searchInput?.offsetParent) searchInput.focus();
    else mobileSearchOpen = true;
  }
</script>

<svelte:window onkeydown={handleShortcut} />

<div class:study-overview-page={context.isOverview} class="app-shell" data-hydrated={hydrated ? 'true' : undefined}>
  <div class="route-progress" data-active={shellBusy ? 'true' : undefined} role="progressbar" aria-label="Loading" aria-hidden={!shellBusy}></div>
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
          <SemesterCalendar size={16} /><span>Semester</span>
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
      <button class="nav-link nav-button" type="button" onclick={() => { sidebarOpen = false; shortcutsOpen = true; }} title="Keyboard shortcuts">
        <Keyboard size={16} /><span>Keyboard shortcuts</span><small>⌘ /</small>
      </button>
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
          <Search size={16} /><input bind:this={searchInput} name="q" value={searchQuery} aria-label="Search assignments" placeholder="Search assignments" /><kbd>⌘ K</kbd>
        </form>
        <button class="icon-button mobile-search-button" type="button" onclick={openSearch} aria-label="Search assignments"><Search size={16} /></button>
        <ThemeToggle />
      </div>
    </header>
    {@render children()}
  </main>
</div>

<CreateBoardDialog bind:open={createBoardOpen} />
<TaskPreview />
<Toast />

{#if mobileSearchOpen}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="mobile-search-title" tabindex="-1" use:dialogLayer={{ close: () => (mobileSearchOpen = false) }}>
    <form class="dialog compact shell-search-dialog" method="get" action="/app/tasks" onsubmit={() => (mobileSearchOpen = false)}>
      <div class="dialog-header"><div><h2 id="mobile-search-title">Search assignments</h2><p>Find work across every course.</p></div><button class="icon-button" type="button" onclick={() => (mobileSearchOpen = false)} aria-label="Close"><X size={16} /></button></div>
      <div class="dialog-body"><label class="search-control shell-search-field"><Search size={16} /><input name="q" value={searchQuery} aria-label="Search assignments" placeholder="Title or notes" data-dialog-focus /></label></div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (mobileSearchOpen = false)}>Cancel</button><button class="button primary" type="submit">Search</button></div>
    </form>
  </div>
{/if}

{#if shortcutsOpen}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="shortcuts-title" tabindex="-1" use:dialogLayer={{ close: () => (shortcutsOpen = false) }}>
    <div class="dialog compact shortcut-dialog">
      <div class="dialog-header"><div><h2 id="shortcuts-title">Keyboard shortcuts</h2><p>Move through your study plan without reaching for the pointer.</p></div><button class="icon-button" type="button" onclick={() => (shortcutsOpen = false)} aria-label="Close"><X size={16} /></button></div>
      <div class="dialog-body shortcut-list">
        <div><span>Search assignments</span><kbd>⌘ / Ctrl + K</kbd></div>
        <div><span>Toggle navigation</span><kbd>⌘ / Ctrl + B</kbd></div>
        <div><span>Show this reference</span><kbd>⌘ / Ctrl + /</kbd></div>
        <div><span>Close a menu or dialog</span><kbd>Esc</kbd></div>
      </div>
      <div class="dialog-footer"><button class="button primary" type="button" onclick={() => (shortcutsOpen = false)} data-dialog-focus>Done</button></div>
    </div>
  </div>
{/if}
