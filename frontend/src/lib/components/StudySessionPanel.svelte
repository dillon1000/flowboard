<script lang="ts">
  import { api, messageFor, refreshAll } from '$lib/api';
  import { dialogLayer } from '$lib/actions/dialogLayer';
  import type { AutoPlanStudySessionsResponse, StudySessionContext } from '$lib/types';
  import { showToast } from '$lib/ui/toast';
  import DatePicker from './DatePicker.svelte';
  import {
    ArrowRightIcon as ArrowRight,
    CalendarPlusIcon as CalendarPlus,
    CheckIcon as Check,
    ClockIcon as Clock,
    StrategyIcon as Strategy,
    TrashIcon as Trash,
    XIcon as X
  } from 'phosphor-svelte';

  let {
    sessions,
    variant,
    taskID = '',
    courseID = '',
    remainingMinutes = 0,
    canPlan = false,
    hasEstimate = true,
    defaultDate = '',
    dueDate = ''
  } = $props<{
    sessions: StudySessionContext[];
    variant: 'task' | 'course';
    taskID?: string;
    courseID?: string;
    remainingMinutes?: number;
    canPlan?: boolean;
    hasEstimate?: boolean;
    defaultDate?: string;
    dueDate?: string;
  }>();

  let addOpen = $state(false);
  let completeOpen = $state(false);
  let moveOpen = $state(false);
  let activeSession = $state<StudySessionContext | null>(null);
  let plannedMinutes = $state(30);
  let actualMinutes = $state(30);
  let selectedDate = $state('');
  let pendingAction = $state('');
  let requestError = $state('');

  const displayedSessions = $derived(
    [...sessions].sort((left, right) => {
      if (left.isPlanned !== right.isPlanned) return left.isPlanned ? -1 : 1;
      return left.isPlanned
        ? left.scheduledDate.localeCompare(right.scheduledDate)
        : right.scheduledDate.localeCompare(left.scheduledDate);
    })
  );
  const maxStudyDate = $derived(dueDate >= defaultDate ? dueDate : '');

  function openAdd(): void {
    selectedDate = defaultDate;
    plannedMinutes = Math.min(60, remainingMinutes);
    requestError = '';
    addOpen = true;
  }

  function openComplete(session: StudySessionContext): void {
    activeSession = session;
    actualMinutes = session.plannedMinutes;
    requestError = '';
    completeOpen = true;
  }

  function openMove(session: StudySessionContext): void {
    activeSession = session;
    selectedDate = session.scheduledDate;
    requestError = '';
    moveOpen = true;
  }

  async function mutate(path: string, init: RequestInit, successMessage: string): Promise<boolean> {
    pendingAction = path;
    requestError = '';
    try {
      await api(path, init);
      showToast(successMessage);
      await refreshAll();
      return true;
    } catch (cause) {
      requestError = messageFor(cause);
      return false;
    } finally {
      pendingAction = '';
    }
  }

  async function addSession(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const saved = await mutate(`/api/v1/tasks/${taskID}/study-sessions`, {
      method: 'POST',
      body: JSON.stringify({ scheduledDate: String(data.get('scheduledDate') ?? ''), plannedMinutes: Number(plannedMinutes) })
    }, 'Study session added');
    if (saved) addOpen = false;
  }

  async function completeSession(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    if (!activeSession) return;
    const saved = await mutate(`/api/v1/study-sessions/${activeSession.id}/complete`, {
      method: 'POST',
      body: JSON.stringify({ actualMinutes: Number(actualMinutes) })
    }, 'Study session completed');
    if (saved) completeOpen = false;
  }

  async function moveSession(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    if (!activeSession) return;
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const saved = await mutate(`/api/v1/study-sessions/${activeSession.id}`, {
      method: 'PATCH',
      body: JSON.stringify({ scheduledDate: String(data.get('scheduledDate') ?? '') })
    }, 'Study session moved');
    if (saved) moveOpen = false;
  }

  async function skipSession(session: StudySessionContext): Promise<void> {
    pendingAction = session.id;
    requestError = '';
    try {
      await api(`/api/v1/study-sessions/${session.id}/skip`, { method: 'POST' });
      await refreshAll();
      showToast('Study session skipped', {
        action: {
          label: 'Undo',
          onclick: async () => {
            await mutate(`/api/v1/study-sessions/${session.id}/restore`, { method: 'POST' }, 'Study session restored');
          }
        }
      });
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingAction = '';
    }
  }

  async function removeSession(session: StudySessionContext): Promise<void> {
    pendingAction = session.id;
    requestError = '';
    try {
      await api(`/api/v1/study-sessions/${session.id}`, { method: 'DELETE' });
      await refreshAll();
      showToast('Study session removed', {
        action: {
          label: 'Undo',
          onclick: async () => {
            await mutate(`/api/v1/tasks/${session.taskID}/study-sessions`, {
              method: 'POST',
              body: JSON.stringify({ scheduledDate: session.scheduledDate, plannedMinutes: session.plannedMinutes })
            }, 'Study session restored');
          }
        }
      });
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingAction = '';
    }
  }

  async function planCourse(): Promise<void> {
    pendingAction = 'plan-course';
    requestError = '';
    try {
      const result = await api<AutoPlanStudySessionsResponse>('/api/v1/study-sessions/plan', {
        method: 'POST',
        body: JSON.stringify({ courseID })
      });
      const changed = result.createdSessionCount + result.updatedSessionCount;
      showToast(changed ? `${changed} study ${changed === 1 ? 'session' : 'sessions'} planned` : 'Course plan is current');
      await refreshAll();
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingAction = '';
    }
  }
</script>

<section class:course={variant === 'course'} class="study-session-panel" aria-labelledby={`study-session-title-${variant}`}>
  <header class="study-session-heading">
    <div>
      <span class="study-session-kicker">Study plan</span>
      <h2 id={`study-session-title-${variant}`}>{variant === 'course' ? 'Study blocks' : 'When will you work on this?'}</h2>
      {#if variant !== 'course'}<p>{hasEstimate ? `${remainingMinutes} minutes remain available in the estimate.` : 'Add a time estimate before you plan a study block.'}</p>{/if}
    </div>
    {#if variant === 'course'}
      <button class="button small" type="button" onclick={planCourse} disabled={Boolean(pendingAction)}><Strategy size={14} />{pendingAction === 'plan-course' ? 'Planning…' : 'Plan this course'}</button>
    {:else if canPlan}
      <button class="button primary small" type="button" onclick={openAdd}><CalendarPlus size={14} />Add study block</button>
    {/if}
  </header>

  {#if requestError}<p class="error-message study-session-error" role="alert">{requestError}</p>{/if}

  {#if displayedSessions.length}
    <div class="study-session-list">
      {#each displayedSessions as session (session.id)}
        <article class:history={!session.isPlanned} class="study-session-row">
          <span class="study-session-date"><Clock size={14} /><span><strong>{session.scheduledDisplay}</strong><small>{session.isCompleted ? `${session.actualDisplay} studied` : session.isSkipped ? `${session.plannedDisplay} skipped` : `${session.plannedDisplay} planned`}</small></span></span>
          {#if variant === 'course'}<a class="study-session-assignment" href={session.taskHref}>{session.taskTitle}<ArrowRight size={12} /></a>{/if}
          <span class={`study-session-state ${session.state}`}>{session.stateName}</span>
          {#if session.isPlanned}
            <span class="study-session-actions">
              <button type="button" onclick={() => openComplete(session)} disabled={Boolean(pendingAction)}>Done</button>
              <button type="button" onclick={() => openMove(session)} disabled={Boolean(pendingAction)}>Move</button>
              <button type="button" onclick={() => skipSession(session)} disabled={Boolean(pendingAction)}>Skip</button>
              <button class="icon-button" type="button" onclick={() => removeSession(session)} disabled={Boolean(pendingAction)} aria-label={`Remove study block on ${session.scheduledDisplay}`}><Trash size={13} /></button>
            </span>
          {/if}
        </article>
      {/each}
    </div>
  {:else}
    <p class="study-session-empty">{variant === 'course' ? 'No study blocks are planned for this course yet.' : 'No study blocks yet. Put this assignment on a real day.'}</p>
  {/if}
</section>

{#if addOpen}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="add-study-session-title" tabindex="-1" use:dialogLayer={{ close: () => (addOpen = false) }}>
    <form class="dialog compact" onsubmit={addSession}>
      <div class="dialog-header"><div><h2 id="add-study-session-title">Add study block</h2><p>Choose when you will work and how long you expect to study.</p></div><button class="icon-button" type="button" onclick={() => (addOpen = false)} aria-label="Close"><X size={16} /></button></div>
      <div class="dialog-body"><div class="form-grid"><div class="field wide"><label for="study-session-date">Study date</label><DatePicker id="study-session-date" name="scheduledDate" value={selectedDate} label="Study date" minDate={defaultDate} maxDate={maxStudyDate} required initialFocus /></div><div class="field wide"><label for="study-session-minutes">How long?</label><div class="duration-chips">{#each [25, 45, 60, 90] as quick (quick)}{#if quick <= remainingMinutes}<button type="button" aria-pressed={plannedMinutes === quick} onclick={() => (plannedMinutes = quick)}>{quick} min</button>{/if}{/each}</div><input class="input" id="study-session-minutes" type="number" min="5" max={remainingMinutes} step="5" bind:value={plannedMinutes} required /><span class="field-help">{remainingMinutes} minutes remain in the estimate.</span></div></div>{#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}</div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (addOpen = false)}>Cancel</button><button class="button primary" type="submit" disabled={Boolean(pendingAction)}><CalendarPlus size={14} />{pendingAction ? 'Adding…' : 'Add block'}</button></div>
    </form>
  </div>
{/if}

{#if completeOpen && activeSession}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="complete-study-session-title" tabindex="-1" use:dialogLayer={{ close: () => (completeOpen = false) }}>
    <form class="dialog compact" onsubmit={completeSession}>
      <div class="dialog-header"><div><h2 id="complete-study-session-title">Finish this study block</h2><p>You planned {activeSession.plannedDisplay} on {activeSession.scheduledDisplay}.</p></div><button class="icon-button" type="button" onclick={() => (completeOpen = false)} aria-label="Close"><X size={16} /></button></div>
      <div class="dialog-body"><div class="field"><label for="actual-study-minutes">Minutes studied</label><input class="input" id="actual-study-minutes" type="number" min="1" max="1440" bind:value={actualMinutes} required data-dialog-focus /></div>{#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}</div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (completeOpen = false)}>Cancel</button><button class="button primary" type="submit" disabled={Boolean(pendingAction)}><Check size={14} />{pendingAction ? 'Saving…' : 'Mark done'}</button></div>
    </form>
  </div>
{/if}

{#if moveOpen && activeSession}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="move-study-session-title" tabindex="-1" use:dialogLayer={{ close: () => (moveOpen = false) }}>
    <form class="dialog compact" onsubmit={moveSession}>
      <div class="dialog-header"><div><h2 id="move-study-session-title">Move this study block</h2><p>Keep the planned time and choose another day.</p></div><button class="icon-button" type="button" onclick={() => (moveOpen = false)} aria-label="Close"><X size={16} /></button></div>
      <div class="dialog-body"><div class="field"><label for="move-study-session-date">Study date</label><DatePicker id="move-study-session-date" name="scheduledDate" value={selectedDate} label="Study date" minDate={defaultDate} maxDate={maxStudyDate} required initialFocus /></div>{#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}</div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (moveOpen = false)}>Cancel</button><button class="button primary" type="submit" disabled={Boolean(pendingAction)}>{pendingAction ? 'Moving…' : 'Move block'}</button></div>
    </form>
  </div>
{/if}
