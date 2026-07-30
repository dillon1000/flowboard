<script lang="ts">
  import { onMount } from 'svelte';
  import {
    Bell,
    Check,
    Command,
    Inbox,
    LayoutDashboard,
    PanelLeftClose,
    PanelLeftOpen,
    Plus,
    Search,
    Settings,
    SlidersHorizontal
  } from '@lucide/svelte';
  import KanbanColumn from './lib/components/KanbanColumn.svelte';
  import TaskDialog from './lib/components/TaskDialog.svelte';
  import { api } from './lib/api';
  import type { Activity, Board, Task, TaskDraft, TaskStatus } from './lib/types';

  const columns: Array<{ status: TaskStatus; title: string; note: string }> = [
    { status: 'backlog', title: 'Backlog', note: 'Ready to shape' },
    { status: 'in_progress', title: 'In progress', note: 'Actively moving' },
    { status: 'review', title: 'Review', note: 'Needs a second look' },
    { status: 'done', title: 'Done', note: 'Shipped this cycle' }
  ];

  let board: Board | null = null;
  let loading = true;
  let error = '';
  let search = '';
  let compact = false;
  let sidebarOpen = true;
  let createStatus: TaskStatus | null = null;
  let selectedTask: Task | null = null;
  let dialogVersion = 0;
  let saving = false;
  let draggingTaskID: string | null = null;
  let toast = '';
  let toastTimer: ReturnType<typeof setTimeout> | null = null;
  let activityCounter = 4;
  let activities: Activity[] = [
    { id: 1, verb: 'Board ready', detail: 'Launch week', time: 'Now' },
    { id: 2, verb: 'Release branch', detail: 'Rules set', time: '12m' },
    { id: 3, verb: 'Billing copy', detail: 'Ready for review', time: '38m' }
  ];

  $: filteredCount = board
    ? board.tasks.filter((task) => matchesSearch(task)).length
    : 0;
  $: completedCount = board
    ? board.tasks.filter((task) => task.status === 'done').length
    : 0;
  $: progress = board?.tasks.length
    ? Math.round((completedCount / board.tasks.length) * 100)
    : 0;

  onMount(() => {
    void loadBoard();
  });

  async function loadBoard(silent = false): Promise<void> {
    if (!silent) {
      loading = true;
    }
    error = '';

    try {
      board = await api.getDefaultBoard();
    } catch (caught) {
      error = caught instanceof Error ? caught.message : 'The board could not load.';
    } finally {
      loading = false;
    }
  }

  function tasksFor(status: TaskStatus): Task[] {
    if (!board) {
      return [];
    }

    return board.tasks
      .filter((task) => task.status === status && matchesSearch(task))
      .sort((left, right) => left.position - right.position);
  }

  function matchesSearch(task: Task): boolean {
    const value = search.trim().toLowerCase();
    if (!value) {
      return true;
    }

    return [task.title, task.description ?? '', ...task.labels]
      .join(' ')
      .toLowerCase()
      .includes(value);
  }

  function openCreate(status: TaskStatus = 'backlog'): void {
    selectedTask = null;
    createStatus = status;
    dialogVersion += 1;
  }

  function openTask(task: Task): void {
    createStatus = null;
    selectedTask = task;
    dialogVersion += 1;
  }

  function closeDialog(): void {
    createStatus = null;
    selectedTask = null;
  }

  async function saveTask(draft: TaskDraft): Promise<void> {
    if (!board) {
      return;
    }
    saving = true;

    try {
      if (selectedTask) {
        const updated = await api.updateTask(selectedTask.id, draft);
        board = {
          ...board,
          tasks: board.tasks.map((task) => (task.id === updated.id ? updated : task))
        };
        addActivity('Task updated', updated.title);
        showToast('Changes saved');
      } else {
        const created = await api.createTask(board.id, draft);
        board = { ...board, tasks: [...board.tasks, created] };
        addActivity('Task created', created.title);
        showToast('Task created');
      }
      closeDialog();
    } catch (caught) {
      showToast(caught instanceof Error ? caught.message : 'The task could not be saved.');
    } finally {
      saving = false;
    }
  }

  async function deleteTask(task: Task): Promise<void> {
    if (!board || !window.confirm(`Delete “${task.title}”? This cannot be undone.`)) {
      return;
    }
    saving = true;

    try {
      await api.deleteTask(task.id);
      board = { ...board, tasks: board.tasks.filter((item) => item.id !== task.id) };
      addActivity('Task deleted', task.title);
      showToast('Task deleted');
      closeDialog();
    } catch (caught) {
      showToast(caught instanceof Error ? caught.message : 'The task could not be deleted.');
    } finally {
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

  /// Applies an immediate local reorder, then asks Vapor to commit and normalize it.
  /// A failed request reloads the server state so the UI cannot keep a false order.
  async function moveTask(status: TaskStatus, targetIndex: number): Promise<void> {
    if (!board || !draggingTaskID) {
      return;
    }

    const task = board.tasks.find((item) => item.id === draggingTaskID);
    if (!task) {
      return;
    }

    const destination = board.tasks
      .filter((item) => item.status === status && item.id !== task.id)
      .sort((left, right) => left.position - right.position);
    const safeIndex = Math.min(targetIndex, destination.length);
    const moved = { ...task, status };
    destination.splice(safeIndex, 0, moved);

    const normalized = new Map(
      destination.map((item, index) => [item.id, { ...item, position: (index + 1) * 1000 }])
    );
    board = {
      ...board,
      tasks: board.tasks.map((item) => normalized.get(item.id) ?? item)
    };
    draggingTaskID = null;

    try {
      await api.moveTask(task.id, status, safeIndex);
      await loadBoard(true);
      addActivity('Task moved', `${task.title} → ${columnTitle(status)}`);
      showToast(`Moved to ${columnTitle(status)}`);
    } catch (caught) {
      await loadBoard(true);
      showToast(caught instanceof Error ? caught.message : 'The task could not be moved.');
    }
  }

  function columnTitle(status: TaskStatus): string {
    return columns.find((column) => column.status === status)?.title ?? status;
  }

  function addActivity(verb: string, detail: string): void {
    activities = [
      { id: activityCounter++, verb, detail, time: 'Now' },
      ...activities
    ].slice(0, 3);
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
  <title>{board ? `${board.name} · Flowboard` : 'Flowboard'}</title>
</svelte:head>

<div class:sidebar-closed={!sidebarOpen} class="app-shell">
  <aside class="sidebar" aria-label="Workspace navigation">
    <div class="brand-row">
      <span class="brand-mark" aria-hidden="true">
        <span></span><span></span><span></span>
      </span>
      <span class="brand-name">Flowboard</span>
      <button
        type="button"
        class="icon-button sidebar-toggle"
        on:click={() => (sidebarOpen = !sidebarOpen)}
        aria-label={sidebarOpen ? 'Collapse sidebar' : 'Expand sidebar'}
      >
        {#if sidebarOpen}
          <PanelLeftClose size={16} />
        {:else}
          <PanelLeftOpen size={16} />
        {/if}
      </button>
    </div>

    <nav class="main-nav">
      <a href="#board" class="active">
        <LayoutDashboard size={17} strokeWidth={1.8} />
        <span>Board</span>
        <span class="nav-key">B</span>
      </a>
      <a href="#inbox">
        <Inbox size={17} strokeWidth={1.8} />
        <span>Inbox</span>
        <span class="nav-count">3</span>
      </a>
    </nav>

    <div class="sidebar-section">
      <span class="sidebar-label">Workspace</span>
      <button type="button" class="workspace-item active">
        <span class="workspace-glyph">LW</span>
        <span>
          <strong>{board?.name ?? 'Launch week'}</strong>
          <small>{board?.tasks.length ?? 0} open items</small>
        </span>
      </button>
    </div>

    <div class="sidebar-spacer"></div>

    <div class="cycle-card">
      <span class="cycle-label">Current cycle</span>
      <div class="cycle-value">
        <strong>{progress}%</strong>
        <span>{completedCount}/{board?.tasks.length ?? 0} shipped</span>
      </div>
      <span class="progress-track"><span style={`width: ${progress}%`}></span></span>
    </div>

    <nav class="utility-nav">
      <a href="#settings">
        <Settings size={17} strokeWidth={1.8} />
        <span>Settings</span>
      </a>
      <button type="button" on:click={() => showToast('No new notifications')}>
        <Bell size={17} strokeWidth={1.8} />
        <span>Notifications</span>
        <span class="online-dot"></span>
      </button>
    </nav>

    <div class="user-row">
      <span class="avatar">DM</span>
      <span>
        <strong>Dillon</strong>
        <small>Workspace owner</small>
      </span>
    </div>
  </aside>

  <main class="workspace">
    <header class="topbar">
      {#if !sidebarOpen}
        <button
          type="button"
          class="icon-button floating-sidebar-toggle"
          on:click={() => (sidebarOpen = true)}
          aria-label="Expand sidebar"
        >
          <PanelLeftOpen size={17} />
        </button>
      {/if}

      <div class="breadcrumbs" aria-label="Breadcrumb">
        <span>Workspace</span>
        <span class="breadcrumb-divider">/</span>
        <strong>{board?.name ?? 'Board'}</strong>
      </div>

      <div class="topbar-actions">
        <label class="search-control">
          <Search size={15} strokeWidth={1.8} />
          <span class="sr-only">Search tasks</span>
          <input bind:value={search} placeholder="Search work" />
          <kbd><Command size={11} /> K</kbd>
        </label>
        <button
          type="button"
          class:active={compact}
          class="button view-button"
          on:click={() => (compact = !compact)}
          aria-pressed={compact}
        >
          <SlidersHorizontal size={15} strokeWidth={1.8} />
          {compact ? 'Comfortable' : 'Compact'}
        </button>
        <button type="button" class="button primary-button" on:click={() => openCreate()}>
          <Plus size={16} strokeWidth={2} />
          New task
        </button>
      </div>
    </header>

    <section class="board-intro">
      <div class="board-heading">
        <span class="board-kicker">Product operations / July cycle</span>
        <div class="title-line">
          <h1>{board?.name ?? 'Launch week'}</h1>
          <span class="live-badge"><span></span> Live</span>
        </div>
        <p>Keep the work visible, make the handoffs clean, and ship the smallest useful thing.</p>
      </div>

      <div class="activity-rail" aria-label="Recent board activity">
        <div class="rail-header">
          <span>Signal</span>
          <span>{filteredCount} visible</span>
        </div>
        <div class="rail-events">
          {#each activities as activity, index (activity.id)}
            <div class="rail-event">
              <span class:current={index === 0} class="rail-node"></span>
              <span>
                <strong>{activity.verb}</strong>
                <small>{activity.detail}</small>
              </span>
              <time>{activity.time}</time>
            </div>
          {/each}
        </div>
      </div>
    </section>

    {#if loading}
      <section class="board-state" aria-live="polite">
        <span class="loading-line"></span>
        <h2>Opening the board</h2>
        <p>Vapor is loading the latest task state.</p>
      </section>
    {:else if error}
      <section class="board-state error-state" aria-live="assertive">
        <span class="state-code">API / 01</span>
        <h2>The board could not connect</h2>
        <p>{error} Start the Vapor server on port 8080, then try again.</p>
        <button type="button" class="button primary-button" on:click={() => loadBoard()}>Try again</button>
      </section>
    {:else if board}
      <section id="board" class="kanban-board" aria-label={`${board.name} Kanban board`}>
        {#each columns as column (column.status)}
          <KanbanColumn
            status={column.status}
            title={column.title}
            note={column.note}
            tasks={tasksFor(column.status)}
            {compact}
            {draggingTaskID}
            oncreate={openCreate}
            onopen={openTask}
            ondragstart={startDrag}
            ondragend={endDrag}
            ondrop={moveTask}
          />
        {/each}
      </section>
    {/if}
  </main>
</div>

{#if createStatus || selectedTask}
  {#key dialogVersion}
    <TaskDialog
      task={selectedTask}
      defaultStatus={createStatus ?? selectedTask?.status ?? 'backlog'}
      {saving}
      onclose={closeDialog}
      onsave={saveTask}
      ondelete={selectedTask ? deleteTask : null}
    />
  {/key}
{/if}

{#if toast}
  <div class="toast" role="status">
    <span class="toast-icon"><Check size={13} strokeWidth={2.2} /></span>
    {toast}
  </div>
{/if}
