<script lang="ts">
  import { goto } from '$app/navigation';
  import { dialogLayer } from '$lib/actions/dialogLayer';
  import type { BoardNavigationContext, CommonPageContext, SearchAssignmentContext } from '$lib/types';
  import {
    ArrowRightIcon as ArrowRight,
    CheckSquareIcon as CheckSquare,
    FolderIcon as Folder,
    GearIcon as Settings,
    MagnifyingGlassIcon as Search,
    StrategyIcon as Strategy,
    XIcon as X
  } from 'phosphor-svelte';

  interface PaletteItem {
    id: string;
    label: string;
    detail: string;
    href: string;
    kind: 'action' | 'course' | 'assignment';
    searchText?: string;
  }

  let { open = $bindable(false), common, initialQuery = '' } = $props<{
    open: boolean;
    common: CommonPageContext;
    initialQuery?: string;
  }>();
  let query = $state('');
  let activeIndex = $state(0);
  let wasOpen = false;

  const baseItems = $derived<PaletteItem[]>([
    { id: 'plan-week', label: 'Plan this week', detail: 'Action', href: '/app', kind: 'action' },
    { id: 'all-assignments', label: 'View all assignments', detail: 'Action', href: '/app/tasks', kind: 'action' },
    { id: 'availability', label: 'Set availability', detail: 'Action', href: '/app/settings/availability', kind: 'action' },
    { id: 'settings', label: 'Open settings', detail: 'Action', href: '/app/settings', kind: 'action' },
    ...common.boards
      .filter((board: BoardNavigationContext) => !board.isArchived)
      .map((board: BoardNavigationContext) => ({
        id: `course-${board.id}`,
        label: board.name,
        detail: `Course · ${board.taskCount} ${board.taskCount === 1 ? 'assignment' : 'assignments'}`,
        href: board.href,
        kind: 'course' as const
      })),
    ...common.searchAssignments.map((assignment: SearchAssignmentContext) => ({
      id: `assignment-${assignment.id}`,
      label: assignment.title,
      detail: assignment.courseName,
      href: assignment.href,
      kind: 'assignment' as const,
      searchText: assignment.searchText
    }))
  ]);
  const results = $derived.by(() => {
    const words = query.toLocaleLowerCase().trim().split(/\s+/).filter(Boolean);
    const matches = baseItems.filter((item) => {
      const value = `${item.label} ${item.detail} ${item.searchText ?? ''}`.toLocaleLowerCase();
      return words.every((word) => value.includes(word));
    });
    return matches.slice(0, 12);
  });

  $effect(() => {
    if (open && !wasOpen) {
      query = initialQuery;
      activeIndex = 0;
    }
    wasOpen = open;
  });

  function updateQuery(event: Event): void {
    query = (event.currentTarget as HTMLInputElement).value;
    activeIndex = 0;
  }

  function select(item: PaletteItem): void {
    open = false;
    void goto(item.href);
  }

  function handleKeydown(event: KeyboardEvent): void {
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      activeIndex = results.length ? (activeIndex + 1) % results.length : 0;
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      activeIndex = results.length ? (activeIndex - 1 + results.length) % results.length : 0;
    } else if (event.key === 'Enter' && results[activeIndex]) {
      event.preventDefault();
      select(results[activeIndex]);
    }
  }
</script>

{#if open}
  <div class="dialog-layer command-palette-layer" role="dialog" aria-modal="true" aria-labelledby="command-palette-title" tabindex="-1" use:dialogLayer={{ close: () => (open = false) }}>
    <div class="dialog command-palette">
      <div class="command-palette-search">
        <Search size={18} />
        <input
          value={query}
          oninput={updateQuery}
          onkeydown={handleKeydown}
          placeholder="Search courses, assignments, and actions"
          aria-label="Search courses, assignments, and actions"
          aria-controls="command-palette-results"
          aria-activedescendant={results[activeIndex] ? `palette-${results[activeIndex].id}` : undefined}
          autocomplete="off"
          data-dialog-focus
        />
        <button class="icon-button" type="button" onclick={() => (open = false)} aria-label="Close"><X size={16} /></button>
      </div>
      <h2 class="sr-only" id="command-palette-title">Find anything</h2>
      <div class="command-palette-results" id="command-palette-results" role="listbox" aria-label="Search results">
        {#each results as item, index (item.id)}
          <a
            id={`palette-${item.id}`}
            class:active={index === activeIndex}
            href={item.href}
            role="option"
            aria-selected={index === activeIndex}
            onmouseenter={() => (activeIndex = index)}
            onclick={(event) => { event.preventDefault(); select(item); }}
          >
            <span class="command-palette-icon">
              {#if item.kind === 'course'}<Folder size={16} />
              {:else if item.kind === 'assignment'}<CheckSquare size={16} />
              {:else if item.id === 'plan-week'}<Strategy size={16} />
              {:else}<Settings size={16} />{/if}
            </span>
            <span><strong>{item.label}</strong><small>{item.detail}</small></span>
            <ArrowRight size={14} />
          </a>
        {:else}
          <div class="command-palette-empty"><Search size={20} /><strong>No matches</strong><span>Try an assignment title, course, or action.</span></div>
        {/each}
      </div>
      <div class="command-palette-footer"><span><kbd>↑</kbd><kbd>↓</kbd> Move</span><span><kbd>↵</kbd> Open</span><span><kbd>Esc</kbd> Close</span></div>
    </div>
  </div>
{/if}
