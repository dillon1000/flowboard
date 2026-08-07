<script lang="ts">
  import { goto } from '$app/navigation';
  import { onMount, tick } from 'svelte';
  import { SparkleIcon as Sparkle } from 'phosphor-svelte';
  import type { BoardNavigationContext } from '$lib/types';
  import { endTour, startTour, tourState } from '$lib/ui/tour.svelte';

  let { boards = [] } = $props<{ boards?: BoardNavigationContext[] }>();

  interface TourStep {
    title: string;
    body: string;
    /** Element to spotlight; a step without one renders as a centered card. */
    selector?: string;
    /** Route the step lives on; a function resolves per-user routes (first
        course, its settings). Returning null skips the step. */
    path?: string | (() => string | null);
  }

  const firstCourse = $derived(boards.find((board: BoardNavigationContext) => !board.isArchived) ?? null);

  // Steps that cannot resolve a route or find their target (no courses yet, a
  // collapsed panel, an empty board, a narrow viewport) are skipped in the
  // direction of travel, so the tour never strands the user on a highlight of
  // nothing.
  const steps: TourStep[] = [
    {
      title: 'Welcome to Flowboard',
      body: 'Flowboard turns courses into a study plan: deadlines come in, you say how long things take and when you are free, and the planner schedules the studying. This tour visits every surface — move with the arrow keys, leave any time with Esc.'
    },
    {
      path: '/app',
      selector: '.sidebar',
      title: 'Navigate the workspace',
      body: 'The sidebar moves between the three surfaces: This week is the working view, Semester shows the whole term, and All assignments is one sortable ledger. Courses you add appear here too. Press ⌘B to collapse it into an icon rail — it remembers your choice.'
    },
    {
      path: '/app',
      selector: '.study-course-panel',
      title: 'The week panel',
      body: 'Your week’s vitals live here: deadlines due, hours planned, and your study streak. Filter the week to a single course, click anything under “Needs study time” to give it a slot, and check your weekly availability at the foot of the panel.'
    },
    {
      path: '/app',
      selector: '.study-week-actions',
      title: 'Two buttons run the week',
      body: '“Plan this week” spreads every estimated assignment across your free time automatically — it respects daily capacity, blocked dates, and deadlines. “Add assignment” is the fast path: title, course, due date, estimate. Notes and labels wait behind More options.'
    },
    {
      path: '/app',
      selector: '.study-days',
      title: 'Seven days, honestly loaded',
      body: 'Each row is a day: deadline cards on top, planned study chips underneath, and a load bar comparing planned time with the time you actually have. Today’s chips carry Done, Move, and Skip — finishing a block records the real minutes. Amber means over capacity; a hatched bar means estimates are missing.'
    },
    {
      path: '/app',
      selector: '.study-workflow-band',
      title: 'The week speaks up',
      body: 'When something needs attention, a single band appears here: setup steps while you are new, the estimate inbox when assignments arrive without time estimates, and “Repair my week” when missed sessions or new deadlines knock the plan loose. No band means nothing is wrong.'
    },
    {
      path: '/app',
      selector: '.study-week-footer',
      title: 'The gap line',
      body: 'The footer names the biggest gap in your data — assignments missing time estimates or due dates — and clicking it takes you straight to the fix. When it goes quiet, every assignment is plannable.'
    },
    {
      path: '/app',
      selector: '.context-panel-toggle',
      title: 'Two sidebars, two switches',
      body: 'This button hides the context panel on the planner pages. The topbar button (or ⌘B) controls the app sidebar. They are independent, and both remember how you left them.'
    },
    {
      selector: '.search-control',
      title: 'Find anything',
      body: 'The command palette (⌘K) reaches assignments, courses, and actions from anywhere in the app — usually faster than any sidebar.'
    },
    {
      selector: '.theme-button',
      title: 'Light or dark',
      body: 'The whole app ships in both themes. Toggle here; your choice is remembered on this device.'
    },
    {
      path: '/app/semester',
      selector: '.semester-term-panel',
      title: 'The term panel',
      body: 'The term at a glance: total deadlines, planned hours, open weeks, and the next few due dates under “Up next”. The ladder below is a clickable map of the term — long bars are heavy weeks, striped bars still need estimates, and each rung jumps to its week.'
    },
    {
      path: '/app/semester',
      selector: '.semester-weeks',
      title: 'The whole term, week by week',
      body: 'Sixteen weeks as rows, and every chip is a deadline with its due date and effort. The dot beside each week is its verdict: green fits, amber is heavy, gray is open. Click any chip to open the assignment.'
    },
    {
      path: () => firstCourse?.href ?? null,
      selector: '.course-panel',
      title: 'A course knows its standing',
      body: 'Every course page leads with the one number it exists to answer: the grade — synced from Canvas when connected, or totalled from your scored assignments. Below it, the counts and the stage bars show how much work sits in each column of the board.'
    },
    {
      path: () => firstCourse?.href ?? null,
      selector: '.course-views',
      title: 'Five ways to see one course',
      body: 'Board for dragging work between stages (dropping into a completed stage earns confetti), Table for a sortable ledger, Calendar for deadlines with daily workload, Gantt for the course timeline, Gallery for reading descriptions. Views are saved per course with their own grouping and filters.'
    },
    {
      path: () => firstCourse?.href ?? null,
      selector: '.course-tools',
      title: 'Narrow without rearranging',
      body: 'These controls — search, stage, priority, due, sort — are temporary: they narrow what you see right now and vanish on reload, so you can ask “what is overdue?” without editing the saved view. One note: manual drag ordering pauses while a sort is active.'
    },
    {
      path: () => firstCourse?.href ?? null,
      selector: '.lane-card',
      title: 'Open any assignment',
      body: 'Each card carries the essentials; hover to preview, click to open the full page — deadline pace meter, checklist steps, notes, files, comments, email reminders, and its study plan in the rail. That page is where “what do I do next?” gets answered.'
    },
    {
      path: () => (firstCourse ? `/app/boards/${firstCourse.id}/settings` : null),
      selector: '.settings-content',
      title: 'Everything a course owns',
      body: 'Course settings is a ledger of the course itself: saved views, workflow stages and priorities with custom colors, typed custom fields, members and roles, assignment templates, NFC Tap actions that update an assignment from a physical tag, and JSON export/import.'
    },
    {
      path: '/app/tasks',
      selector: '.page-header',
      title: 'Every assignment, one ledger',
      body: 'All assignments across all courses in one sortable table: due date, priority, effort, score. Archived assignments keep their own page next door, ready to restore.'
    },
    {
      path: '/app/settings/availability',
      selector: '.availability-settings-form',
      title: 'Tell the planner your real week',
      body: 'Set study capacity per weekday, block whole dates, and record classes, work shifts, and one-time conflicts. The auto-planner only ever schedules into the time that is genuinely left. The running total and Save stay together at the top.'
    },
    {
      path: '/app/settings',
      selector: '.settings-content',
      title: 'Your account, your rhythm',
      body: 'Profile and time zone live here, plus the planning emails: a daily brief of today’s sessions and deadlines, and a Monday prompt when work still needs study time — both delivered at your chosen local hour. You can also mint a read-only calendar feed for any calendar app, and API keys for scripts.'
    },
    {
      path: '/app/settings/integrations',
      selector: '.settings-content',
      title: 'Let Canvas do the typing',
      body: 'Connect your school’s Canvas origin, copy the one-time sync key into the private browser extension, and your courses, assignments, deadlines, and grades import and stay in sync — read-only, through your own signed-in session. Canvas-linked fields lock; your planning stays yours.'
    },
    {
      title: 'You’re set',
      body: 'The loop is simple: add courses (or let Canvas import them), give assignments time estimates, press “Plan this week”, then work the plan — Done, Move, or Skip. Replay this tour from the sidebar any time, and ⌘/ lists every keyboard shortcut.'
    }
  ];

  interface SpotRect {
    top: number;
    left: number;
    width: number;
    height: number;
  }

  let rect = $state<SpotRect | null>(null);
  let cardStyle = $state('');
  let cardElement = $state<HTMLElement | null>(null);
  let targetElement: HTMLElement | null = null;
  let placingToken = 0;
  let started = false;

  const current = $derived(steps[tourState.step]);

  onMount(() => {
    if (!localStorage.getItem('flowboard-tour') && window.location.pathname === '/app') {
      setTimeout(() => startTour(), 700);
    }
  });

  $effect(() => {
    if (tourState.active && !started) {
      started = true;
      void show(tourState.step, 1);
    } else if (!tourState.active) {
      started = false;
      targetElement = null;
      rect = null;
    }
  });

  $effect(() => {
    if (!tourState.active) return;
    const refresh = (): void => {
      measure();
      positionCard();
    };
    window.addEventListener('resize', refresh);
    window.addEventListener('scroll', refresh, { capture: true, passive: true });
    return () => {
      window.removeEventListener('resize', refresh);
      window.removeEventListener('scroll', refresh, { capture: true });
    };
  });

  async function waitFor(selector: string): Promise<HTMLElement | null> {
    for (let attempt = 0; attempt < 24; attempt += 1) {
      const element = document.querySelector<HTMLElement>(selector);
      if (element && element.getBoundingClientRect().width > 0) return element;
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    return null;
  }

  async function show(index: number, direction: 1 | -1): Promise<void> {
    if (index < 0) {
      return;
    }
    if (index >= steps.length) {
      finish();
      return;
    }
    placingToken += 1;
    const token = placingToken;
    const step = steps[index];
    const path = typeof step.path === 'function' ? step.path() : step.path;
    if (step.path && !path) {
      await show(index + direction, direction);
      return;
    }
    if (path && window.location.pathname !== path) await goto(path);
    let element: HTMLElement | null = null;
    if (step.selector) {
      element = await waitFor(step.selector);
      if (token !== placingToken || !tourState.active) return;
      if (!element) {
        await show(index + direction, direction);
        return;
      }
    }
    tourState.step = index;
    targetElement = element;
    element?.scrollIntoView({ block: 'center', behavior: 'auto' });
    measure();
    await tick();
    positionCard();
    cardElement?.focus();
  }

  function measure(): void {
    if (!targetElement) {
      rect = null;
      return;
    }
    const bounds = targetElement.getBoundingClientRect();
    rect = { top: bounds.top, left: bounds.left, width: bounds.width, height: bounds.height };
  }

  function positionCard(): void {
    if (!rect || !cardElement) {
      cardStyle = '';
      return;
    }
    const width = cardElement.offsetWidth || 360;
    const height = cardElement.offsetHeight || 220;
    const margin = 14;
    let top = rect.top + rect.height + margin;
    let left = rect.left;

    // Tall targets (sidebars, full panels) read better with the card beside
    // them; short targets get it underneath, flipped above when space runs out.
    if (rect.height > window.innerHeight * 0.6) {
      left = rect.left + rect.width + margin;
      top = Math.max(16, rect.top + 24);
      if (left + width > window.innerWidth - 16) left = rect.left - width - margin;
    } else if (top + height > window.innerHeight - 16) {
      top = rect.top - height - margin;
    }

    top = Math.max(16, Math.min(top, window.innerHeight - height - 16));
    left = Math.max(16, Math.min(left, window.innerWidth - width - 16));
    cardStyle = `top: ${Math.round(top)}px; left: ${Math.round(left)}px;`;
  }

  function markDone(): void {
    localStorage.setItem('flowboard-tour', 'done');
  }

  function finish(): void {
    markDone();
    endTour();
  }

  function next(): void {
    void show(tourState.step + 1, 1);
  }

  function back(): void {
    void show(tourState.step - 1, -1);
  }

  function handleKey(event: KeyboardEvent): void {
    if (!tourState.active) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      finish();
    }
    if (event.key === 'ArrowRight') {
      event.preventDefault();
      next();
    }
    if (event.key === 'ArrowLeft') {
      event.preventDefault();
      back();
    }
  }
</script>

<svelte:window onkeydown={handleKey} />

{#if tourState.active}
  <div class="tour-layer" role="presentation">
    {#if rect}
      <div
        class="tour-ring"
        style={`top: ${rect.top - 6}px; left: ${rect.left - 6}px; width: ${rect.width + 12}px; height: ${rect.height + 12}px;`}
        aria-hidden="true"
      ></div>
    {:else}
      <div class="tour-backdrop" aria-hidden="true"></div>
    {/if}

    <div
      class:centered={!rect}
      class="tour-card"
      role="dialog"
      aria-modal="true"
      aria-labelledby="tour-step-title"
      tabindex="-1"
      bind:this={cardElement}
      style={rect ? cardStyle : ''}
    >
      <span class="tour-kicker"><Sparkle size={13} aria-hidden="true" />Tour · {tourState.step + 1} of {steps.length}</span>
      <h2 id="tour-step-title">{current.title}</h2>
      <p>{current.body}</p>
      <div class="tour-footer">
        <button class="tour-skip" type="button" onclick={finish}>Skip tour</button>
        <div class="tour-dots" aria-hidden="true">
          {#each steps as _, index (index)}
            <span class:active={index === tourState.step}></span>
          {/each}
        </div>
        <div class="tour-nav">
          {#if tourState.step > 0}<button class="button small" type="button" onclick={back}>Back</button>{/if}
          <button class="button primary small" type="button" onclick={next}>
            {tourState.step === steps.length - 1 ? 'Finish' : 'Next'}
          </button>
        </div>
      </div>
    </div>
  </div>
{/if}
