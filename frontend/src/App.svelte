<script lang="ts">
  import { onMount } from 'svelte';
  import {
    Check,
    ChevronRight,
    House,
    LayoutDashboard,
    ListTodo,
    Menu,
    PanelLeftClose,
    Plus,
    Search,
    Settings,
    X
  } from '@lucide/svelte';
  import BoardDialog from './lib/components/BoardDialog.svelte';
  import ConfirmDialog from './lib/components/ConfirmDialog.svelte';
  import KanbanColumn from './lib/components/KanbanColumn.svelte';
  import TaskDialog from './lib/components/TaskDialog.svelte';
  import { api } from './lib/api';
  import type {
    Board,
    BoardSummary,
    Task,
    TaskDraft,
    TaskPriority,
    TaskStatus,
    User
  } from './lib/types';

  type PageName = 'overview' | 'board' | 'tasks' | 'settings';
  type BoardDialogState = { mode: 'create' } | { mode: 'rename'; board: Board };
  type ConfirmState =
    | { kind: 'task'; task: Task }
    | { kind: 'board'; board: Board };

  const columns: Array<{ status: TaskStatus; title: string }> = [
    { status: 'backlog', title: 'Backlog' },
    { status: 'in_progress', title: 'In Progress' },
    { status: 'review', title: 'Review' },
    { status: 'done', title: 'Done' }
  ];
  const statusLabels: Record<TaskStatus, string> = {
    backlog: 'Backlog',
    in_progress: 'In Progress',
    review: 'Review',
    done: 'Done'
  };
  const priorityLabels: Record<TaskPriority, string> = {
    low: 'Low',
    medium: 'Medium',
    high: 'High',
    urgent: 'Urgent'
  };

  const root = document.getElementById('app');
  let user: User | null = root?.dataset.userName
    ? {
        id: '',
        name: root.dataset.userName,
        email: root.dataset.userEmail ?? '',
        createdAt: null
      }
    : null;
  let boards: BoardSummary[] = [];
  let activeBoard: Board | null = null;
  let allTasks: Task[] = [];
  let page: PageName = 'overview';
  let loading = true;
  let error = '';
  let search = '';
  let sidebarOpen = true;
  let selectedTask: Task | null = null;
  let createStatus: TaskStatus | null = null;
  let boardDialog: BoardDialogState | null = null;
  let confirmState: ConfirmState | null = null;
  let saving = false;
  let draggingTaskID: string | null = null;
  let toast = '';
  let toastTimer: ReturnType<typeof setTimeout> | null = null;
  let profileName = user?.name ?? '';

  $: totalTaskCount = boards.reduce((total, board) => total + board.taskCount, 0);
  $: completedTaskCount = boards.reduce((total, board) => total + board.completedCount, 0);
  $: openTaskCount = totalTaskCount - completedTaskCount;
  $: inProgressCount = allTasks.filter((task) => task.status === 'in_progress').length;
  $: filteredAllTasks = allTasks.filter(matchesSearch);
  $: groupedTasks = {
    backlog: (activeBoard?.tasks ?? [])
      .filter((task) => task.status === 'backlog' && matchesSearch(task))
      .sort((left, right) => left.position - right.position),
    in_progress: (activeBoard?.tasks ?? [])
      .filter((task) => task.status === 'in_progress' && matchesSearch(task))
      .sort((left, right) => left.position - right.position),
    review: (activeBoard?.tasks ?? [])
      .filter((task) => task.status === 'review' && matchesSearch(task))
      .sort((left, right) => left.position - right.position),
    done: (activeBoard?.tasks ?? [])
      .filter((task) => task.status === 'done' && matchesSearch(task))
      .sort((left, right) => left.position - right.position)
  };
  $: pageTitle =
    page === 'board'
      ? activeBoard?.name ?? 'Board'
      : page === 'tasks'
        ? 'All Tasks'
        : page === 'settings'
          ? 'Settings'
          : 'Overview';

  onMount(() => {
    sidebarOpen = window.innerWidth > 820;
    const handlePopState = () => void syncRoute();
    window.addEventListener('popstate', handlePopState);
    void loadWorkspace();
    return () => window.removeEventListener('popstate', handlePopState);
  });

  async function loadWorkspace(): Promise<void> {
    loading = true;
    error = '';
    try {
      const [nextUser, nextBoards, taskPage] = await Promise.all([
        api.getMe(),
        api.getBoards(),
        api.getTasks()
      ]);
      user = nextUser;
      profileName = nextUser.name;
      boards = nextBoards;
      allTasks = taskPage.items;
      await syncRoute();
    } catch (caught) {
      error = caught instanceof Error ? caught.message : 'The workspace could not load.';
    } finally {
      loading = false;
    }
  }

  /// Resolves the current browser URL into app state. Board and task pages keep
  /// their own URLs so refresh, Back, Forward, and copied links preserve context.
  async function syncRoute(): Promise<void> {
    const parts = window.location.pathname.split('/').filter(Boolean);
    search = '';
    if (parts[1] === 'boards' && parts[2]) {
      page = 'board';
      await loadBoard(parts[2]);
    } else if (parts[1] === 'tasks') {
      page = 'tasks';
      activeBoard = null;
    } else if (parts[1] === 'settings') {
      page = 'settings';
      activeBoard = null;
    } else {
      page = 'overview';
      activeBoard = null;
    }
    document.title = `${pageTitle} · Flowboard`;
  }

  async function navigate(path: string): Promise<void> {
    if (window.location.pathname !== path) {
      window.history.pushState({}, '', path);
    }
    if (window.innerWidth <= 820) {
      sidebarOpen = false;
    }
    await syncRoute();
  }

  function handleLink(event: MouseEvent, path: string): void {
    if (
      event.button !== 0 ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey
    ) {
      return;
    }
    event.preventDefault();
    void navigate(path);
  }

  async function loadBoard(boardID: string, silent = false): Promise<void> {
    if (!silent) {
      loading = true;
    }
    error = '';
    try {
      activeBoard = await api.getBoard(boardID);
    } catch (caught) {
      activeBoard = null;
      error = caught instanceof Error ? caught.message : 'The board could not load.';
    } finally {
      if (!silent) {
        loading = false;
      }
    }
  }

  async function refreshCollections(): Promise<void> {
    const [nextBoards, taskPage] = await Promise.all([api.getBoards(), api.getTasks()]);
    boards = nextBoards;
    allTasks = taskPage.items;
  }

  function matchesSearch(task: Task): boolean {
    const value = search.trim().toLowerCase();
    if (!value) {
      return true;
    }
    return [task.title, task.description ?? '', task.boardName ?? '', ...task.labels]
      .join(' ')
      .toLowerCase()
      .includes(value);
  }

  function openCreate(status: TaskStatus = 'backlog'): void {
    if (!activeBoard) {
      return;
    }
    selectedTask = null;
    createStatus = status;
  }

  function openTask(task: Task): void {
    createStatus = null;
    selectedTask = task;
  }

  function closeTaskDialog(): void {
    createStatus = null;
    selectedTask = null;
  }

  async function saveTask(draft: TaskDraft): Promise<void> {
    saving = true;
    try {
      if (selectedTask) {
        const updated = await api.updateTask(selectedTask.id, draft);
        if (activeBoard) {
          activeBoard = {
            ...activeBoard,
            tasks: activeBoard.tasks.map((task) => (task.id === updated.id ? updated : task))
          };
        }
        showToast('Task updated');
      } else if (activeBoard) {
        const created = await api.createTask(activeBoard.id, draft);
        activeBoard = { ...activeBoard, tasks: [...activeBoard.tasks, created] };
        showToast('Task created');
      }
      closeTaskDialog();
      await refreshCollections();
    } catch (caught) {
      showToast(caught instanceof Error ? caught.message : 'The task could not be saved.');
    } finally {
      saving = false;
    }
  }

  function requestTaskDelete(task: Task): void {
    closeTaskDialog();
    confirmState = { kind: 'task', task };
  }

  function requestBoardDelete(): void {
    if (activeBoard) {
      confirmState = { kind: 'board', board: activeBoard };
    }
  }

  async function confirmDelete(): Promise<void> {
    if (!confirmState) {
      return;
    }
    const target = confirmState;
    saving = true;
    try {
      if (target.kind === 'task') {
        await api.deleteTask(target.task.id);
        if (activeBoard) {
          activeBoard = {
            ...activeBoard,
            tasks: activeBoard.tasks.filter((task) => task.id !== target.task.id)
          };
        }
        showToast('Task deleted');
      } else {
        await api.deleteBoard(target.board.id);
        showToast('Board deleted');
        await navigate('/app');
      }
      confirmState = null;
      await refreshCollections();
    } catch (caught) {
      showToast(caught instanceof Error ? caught.message : 'The item could not be deleted.');
    } finally {
      saving = false;
    }
  }

  async function saveBoard(name: string): Promise<void> {
    if (!boardDialog) {
      return;
    }
    saving = true;
    try {
      if (boardDialog.mode === 'create') {
        const created = await api.createBoard(name);
        boardDialog = null;
        await refreshCollections();
        await navigate(`/app/boards/${created.id}`);
        showToast('Board created');
      } else {
        const updated = await api.updateBoard(boardDialog.board.id, name);
        activeBoard = updated;
        boardDialog = null;
        await refreshCollections();
        showToast('Board renamed');
      }
    } catch (caught) {
      showToast(caught instanceof Error ? caught.message : 'The board could not be saved.');
    } finally {
      saving = false;
    }
  }

  async function saveProfile(): Promise<void> {
    saving = true;
    try {
      user = await api.updateProfile(profileName.trim());
      showToast('Profile updated');
    } catch (caught) {
      showToast(caught instanceof Error ? caught.message : 'The profile could not be saved.');
    } finally {
      saving = false;
    }
  }

  async function logout(): Promise<void> {
    saving = true;
    try {
      await api.logout();
      window.location.assign('/login');
    } catch (caught) {
      showToast(caught instanceof Error ? caught.message : 'Log out did not complete.');
      saving = false;
    }
  }

  function startDrag(event: DragEvent, task: Task): void {
    draggingTaskID = task.id;
    event.dataTransfer?.setData('text/plain', task.id);
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = 'move';
    }
  }

  function endDrag(): void {
    draggingTaskID = null;
  }

  /// Applies the move immediately, then reconciles with Vapor. A failed request
  /// reloads the board so the interface cannot retain an order the server rejected.
  async function moveTask(status: TaskStatus, targetIndex: number): Promise<void> {
    if (!activeBoard || !draggingTaskID) {
      return;
    }
    const task = activeBoard.tasks.find((item) => item.id === draggingTaskID);
    if (!task) {
      return;
    }

    const destination = activeBoard.tasks
      .filter((item) => item.status === status && item.id !== task.id)
      .sort((left, right) => left.position - right.position);
    const safeIndex = Math.min(targetIndex, destination.length);
    destination.splice(safeIndex, 0, { ...task, status });
    const normalized = new Map(
      destination.map((item, index) => [item.id, { ...item, position: (index + 1) * 1000 }])
    );
    activeBoard = {
      ...activeBoard,
      tasks: activeBoard.tasks.map((item) => normalized.get(item.id) ?? item)
    };
    draggingTaskID = null;

    try {
      await api.moveTask(task.id, status, safeIndex);
      await loadBoard(activeBoard.id, true);
      await refreshCollections();
      showToast(`Moved to ${statusLabels[status]}`);
    } catch (caught) {
      await loadBoard(activeBoard.id, true);
      showToast(caught instanceof Error ? caught.message : 'The task could not be moved.');
    }
  }

  async function openTaskFromList(task: Task): Promise<void> {
    if (task.boardID) {
      await navigate(`/app/boards/${task.boardID}`);
      selectedTask = activeBoard?.tasks.find((item) => item.id === task.id) ?? task;
    }
  }

  function formatDate(value: string | null): string {
    if (!value) {
      return 'No date';
    }
    return new Intl.DateTimeFormat(undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric'
    }).format(new Date(value));
  }

  function initials(name: string): string {
    return name
      .split(' ')
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0])
      .join('')
      .toUpperCase();
  }

  function showToast(message: string): void {
    toast = message;
    if (toastTimer) {
      clearTimeout(toastTimer);
    }
    toastTimer = setTimeout(() => {
      toast = '';
    }, 3200);
  }
</script>

<svelte:head>
  <meta
    name="description"
    content="Flowboard is a focused workspace for boards and tasks."
  />
</svelte:head>

<div class:sidebar-open={sidebarOpen} class="app-shell">
  <aside class="sidebar" aria-label="Workspace navigation">
    <div class="brand-row">
      <a href="/app" class="brand" on:click={(event) => handleLink(event, '/app')}>
        <span class="brand-symbol" aria-hidden="true"></span>
        <span>Flowboard</span>
      </a>
      <button
        type="button"
        class="icon-button sidebar-close"
        on:click={() => (sidebarOpen = false)}
        aria-label="Close navigation"
      >
        <PanelLeftClose size={17} />
      </button>
    </div>

    <nav class="main-nav">
      <a
        href="/app"
        class:active={page === 'overview'}
        on:click={(event) => handleLink(event, '/app')}
      >
        <House size={16} strokeWidth={1.8} />
        Overview
      </a>
      <a
        href="/app/tasks"
        class:active={page === 'tasks'}
        on:click={(event) => handleLink(event, '/app/tasks')}
      >
        <ListTodo size={16} strokeWidth={1.8} />
        All Tasks
      </a>
    </nav>

    <div class="boards-nav">
      <div class="nav-section-header">
        <span>Boards</span>
        <button
          type="button"
          class="icon-button"
          on:click={() => (boardDialog = { mode: 'create' })}
          aria-label="Create board"
        >
          <Plus size={15} />
        </button>
      </div>
      <nav>
        {#each boards as board (board.id)}
          <a
            href={`/app/boards/${board.id}`}
            class:active={page === 'board' && activeBoard?.id === board.id}
            on:click={(event) => handleLink(event, `/app/boards/${board.id}`)}
          >
            <LayoutDashboard size={15} strokeWidth={1.8} />
            <span>{board.name}</span>
            <small>{board.taskCount}</small>
          </a>
        {/each}
      </nav>
    </div>

    <div class="sidebar-spacer"></div>

    <nav class="settings-nav">
      <a
        href="/app/settings"
        class:active={page === 'settings'}
        on:click={(event) => handleLink(event, '/app/settings')}
      >
        <Settings size={16} strokeWidth={1.8} />
        Settings
      </a>
    </nav>

    <a
      href="/app/settings"
      class="user-row"
      on:click={(event) => handleLink(event, '/app/settings')}
    >
      <span class="avatar">{initials(user?.name ?? 'User')}</span>
      <span>
        <strong>{user?.name ?? 'Account'}</strong>
        <small>{user?.email ?? ''}</small>
      </span>
    </a>
  </aside>

  {#if sidebarOpen}
    <button
      type="button"
      class="sidebar-scrim"
      on:click={() => (sidebarOpen = false)}
      aria-label="Close navigation"
    ></button>
  {/if}

  <main class="workspace">
    <header class="topbar">
      <button
        type="button"
        class="icon-button menu-button"
        on:click={() => (sidebarOpen = true)}
        aria-label="Open navigation"
      >
        <Menu size={18} />
      </button>
      <nav class="breadcrumbs" aria-label="Breadcrumb">
        <a href="/app" on:click={(event) => handleLink(event, '/app')}>Workspace</a>
        <ChevronRight size={13} aria-hidden="true" />
        <span>{pageTitle}</span>
      </nav>
      {#if page === 'board' && activeBoard}
        <div class="topbar-actions">
          <label class="search-control">
            <Search size={15} strokeWidth={1.8} />
            <span class="sr-only">Search this board</span>
            <input bind:value={search} name="board-search" autocomplete="off" placeholder="Search…" />
          </label>
          <button type="button" class="button primary-button" on:click={() => openCreate()}>
            <Plus size={15} />
            New Task
          </button>
        </div>
      {/if}
    </header>

    {#if loading}
      <section class="page-state" aria-live="polite">
        <span class="spinner" aria-hidden="true"></span>
        <h1>Loading workspace…</h1>
      </section>
    {:else if error}
      <section class="page-state">
        <h1>Workspace unavailable</h1>
        <p>{error}</p>
        <button type="button" class="button primary-button" on:click={loadWorkspace}>Try Again</button>
      </section>
    {:else if page === 'overview'}
      <section class="page-content">
        <header class="page-header">
          <div>
            <h1>Overview</h1>
            <p>Your current work across {boards.length} {boards.length === 1 ? 'board' : 'boards'}.</p>
          </div>
          <button type="button" class="button primary-button" on:click={() => (boardDialog = { mode: 'create' })}>
            <Plus size={15} />
            New Board
          </button>
        </header>

        <section class="metrics" aria-label="Workspace totals">
          <div><span>Open Tasks</span><strong>{openTaskCount}</strong></div>
          <div><span>In Progress</span><strong>{inProgressCount}</strong></div>
          <div><span>Completed</span><strong>{completedTaskCount}</strong></div>
        </section>

        <section class="content-section">
          <div class="section-header">
            <h2>Boards</h2>
          </div>
          {#if boards.length}
            <div class="board-list">
              {#each boards as board (board.id)}
                <a
                  href={`/app/boards/${board.id}`}
                  on:click={(event) => handleLink(event, `/app/boards/${board.id}`)}
                >
                  <span class="board-icon"><LayoutDashboard size={17} /></span>
                  <span class="board-list-name">
                    <strong>{board.name}</strong>
                    <small>Updated {formatDate(board.updatedAt ?? board.createdAt)}</small>
                  </span>
                  <span class="board-progress">
                    {board.completedCount} of {board.taskCount} done
                  </span>
                  <ChevronRight size={15} aria-hidden="true" />
                </a>
              {/each}
            </div>
          {:else}
            <div class="empty-state">
              <h3>Create your first board</h3>
              <p>Boards keep related tasks and their status in one place.</p>
              <button type="button" class="button primary-button" on:click={() => (boardDialog = { mode: 'create' })}>
                Create Board
              </button>
            </div>
          {/if}
        </section>

        {#if allTasks.length}
          <section class="content-section">
            <div class="section-header">
              <h2>Recently Updated</h2>
              <a href="/app/tasks" on:click={(event) => handleLink(event, '/app/tasks')}>View All</a>
            </div>
            <div class="task-table">
              {#each allTasks.slice(0, 6) as task (task.id)}
                <button type="button" on:click={() => openTaskFromList(task)}>
                  <span class={`status-dot status-${task.status}`}></span>
                  <span class="table-task-title">{task.title}</span>
                  <span>{task.boardName ?? 'Board'}</span>
                  <span>{statusLabels[task.status]}</span>
                  <ChevronRight size={14} aria-hidden="true" />
                </button>
              {/each}
            </div>
          </section>
        {/if}
      </section>
    {:else if page === 'board' && activeBoard}
      <section class="board-page">
        <header class="page-header board-page-header">
          <div>
            <h1>{activeBoard.name}</h1>
            <p>{activeBoard.tasks.length} {activeBoard.tasks.length === 1 ? 'task' : 'tasks'}</p>
          </div>
          <div class="page-actions">
            <button
              type="button"
              class="button secondary-button"
              on:click={() => (boardDialog = { mode: 'rename', board: activeBoard! })}
            >
              Rename
            </button>
            <button type="button" class="button secondary-button" on:click={requestBoardDelete}>
              Delete
            </button>
          </div>
        </header>

        <section class="kanban-board" aria-label={`${activeBoard.name} Kanban board`}>
          {#each columns as column (column.status)}
            <KanbanColumn
              status={column.status}
              title={column.title}
              tasks={groupedTasks[column.status]}
              {draggingTaskID}
              oncreate={openCreate}
              onopen={openTask}
              ondragstart={startDrag}
              ondragend={endDrag}
              ondrop={moveTask}
            />
          {/each}
        </section>
      </section>
    {:else if page === 'tasks'}
      <section class="page-content">
        <header class="page-header">
          <div>
            <h1>All Tasks</h1>
            <p>Review work from every board.</p>
          </div>
          <label class="search-control page-search">
            <Search size={15} strokeWidth={1.8} />
            <span class="sr-only">Search all tasks</span>
            <input bind:value={search} name="task-search" autocomplete="off" placeholder="Search tasks…" />
          </label>
        </header>

        <section class="content-section task-page-section">
          {#if filteredAllTasks.length}
            <div class="task-list-header" aria-hidden="true">
              <span>Task</span><span>Board</span><span>Status</span><span>Priority</span><span></span>
            </div>
            <div class="task-table full-task-table">
              {#each filteredAllTasks as task (task.id)}
                <button type="button" on:click={() => openTaskFromList(task)}>
                  <span class="table-task-title">{task.title}</span>
                  <span>{task.boardName ?? 'Board'}</span>
                  <span class="status-cell"><span class={`status-dot status-${task.status}`}></span>{statusLabels[task.status]}</span>
                  <span>{priorityLabels[task.priority]}</span>
                  <ChevronRight size={14} aria-hidden="true" />
                </button>
              {/each}
            </div>
          {:else}
            <div class="empty-state">
              <h3>No tasks found</h3>
              <p>{search ? 'Try a different search.' : 'Create a task from one of your boards.'}</p>
            </div>
          {/if}
        </section>
      </section>
    {:else if page === 'settings' && user}
      <section class="page-content settings-page">
        <header class="page-header">
          <div>
            <h1>Settings</h1>
            <p>Manage your account.</p>
          </div>
        </header>

        <section class="settings-section">
          <div class="settings-copy">
            <h2>Profile</h2>
            <p>This name appears throughout your workspace.</p>
          </div>
          <form on:submit={(event) => {
            event.preventDefault();
            void saveProfile();
          }}>
            <label class="field">
              <span>Name</span>
              <input bind:value={profileName} name="name" autocomplete="name" maxlength="80" required />
            </label>
            <label class="field">
              <span>Email</span>
              <input value={user.email} name="email" autocomplete="email" disabled />
            </label>
            <div>
              <button type="submit" class="button primary-button" disabled={saving || !profileName.trim()}>
                {saving ? 'Saving…' : 'Save Changes'}
              </button>
            </div>
          </form>
        </section>

        <section class="settings-section">
          <div class="settings-copy">
            <h2>Session</h2>
            <p>End your session on this device.</p>
          </div>
          <div>
            <button type="button" class="button secondary-button" on:click={logout} disabled={saving}>
              Log Out
            </button>
          </div>
        </section>
      </section>
    {/if}
  </main>
</div>

{#if createStatus || selectedTask}
  <TaskDialog
    task={selectedTask}
    defaultStatus={createStatus ?? selectedTask?.status ?? 'backlog'}
    {saving}
    onclose={closeTaskDialog}
    onsave={saveTask}
    onrequestdelete={selectedTask ? requestTaskDelete : null}
  />
{/if}

{#if boardDialog}
  <BoardDialog
    initialName={boardDialog.mode === 'rename' ? boardDialog.board.name : ''}
    title={boardDialog.mode === 'rename' ? 'Rename Board' : 'Create Board'}
    submitLabel={boardDialog.mode === 'rename' ? 'Save Changes' : 'Create Board'}
    {saving}
    onclose={() => (boardDialog = null)}
    onsave={saveBoard}
  />
{/if}

{#if confirmState}
  <ConfirmDialog
    title={confirmState.kind === 'task' ? 'Delete Task' : 'Delete Board'}
    message={confirmState.kind === 'task'
      ? `Delete “${confirmState.task.title}”? This action cannot be undone.`
      : `Delete “${confirmState.board.name}” and all of its tasks? This action cannot be undone.`}
    confirmLabel={confirmState.kind === 'task' ? 'Delete Task' : 'Delete Board'}
    busy={saving}
    oncancel={() => (confirmState = null)}
    onconfirm={confirmDelete}
  />
{/if}

{#if toast}
  <div class="toast" role="status" aria-live="polite">
    <Check size={14} strokeWidth={2.2} />
    {toast}
    <button type="button" on:click={() => (toast = '')} aria-label="Dismiss">
      <X size={14} />
    </button>
  </div>
{/if}
