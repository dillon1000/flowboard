<script lang="ts">
  import type { TapExecutionResponse, TapPreparationResponse, TapTaskProperty } from '$lib/types';
  import { onMount, tick } from 'svelte';

  type TapState = 'running' | 'ready' | 'success' | 'error' | 'rotation';

  class TapRequestError extends Error {
    readonly status: number;

    constructor(status: number, message: string) {
      super(message);
      this.status = status;
    }
  }

  let tapState: TapState = $state('running');
  let heading = $state('Opening tag…');
  let detail = $state('Keep this page open.');
  let outcome = $state('');
  let token = '';
  let requestID = '';
  let prepared: TapPreparationResponse | null = $state(null);
  let retryAction: (() => Promise<void>) | null = $state(null);
  let titleInput = $state<HTMLInputElement>();

  onMount(() => {
    token = location.hash.slice(1);
    history.replaceState(null, '', location.pathname + location.search);
    requestID = crypto.randomUUID();
    if (!/^fbt_[A-Za-z0-9_-]{32}$/.test(token)) {
      showRotation('This Tap link is not valid', 'Ask the tag owner to program it again.');
      return;
    }
    void prepare();
  });

  async function request<T>(path: string, body: unknown): Promise<T> {
    const response = await fetch(path, {
      method: 'POST',
      credentials: 'omit',
      cache: 'no-store',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body)
    });
    const payload: unknown = await response.json().catch(() => null);
    if (!response.ok) {
      const reason = payload && typeof payload === 'object' && 'reason' in payload && typeof (payload as { reason?: unknown }).reason === 'string'
        ? String((payload as { reason: string }).reason)
        : 'This Tap action could not run.';
      throw new TapRequestError(response.status, reason);
    }
    return payload as T;
  }

  async function prepare(): Promise<void> {
    tapState = 'running';
    heading = 'Opening tag…';
    detail = 'Loading the task form.';
    outcome = '';
    retryAction = null;
    try {
      prepared = await request<TapPreparationResponse>('/api/v1/taps/prepare', { token });
      if (prepared.kind === 'create_task' && prepared.task) {
        tapState = 'ready';
        heading = prepared.actionName || 'Create task';
        detail = prepared.actionDescription || 'Enter the task details.';
        await tick();
        titleInput?.focus();
      } else {
        await execute(null);
      }
    } catch (cause) {
      handleFailure(cause, prepare);
    }
  }

  async function execute(task: Record<string, unknown> | null): Promise<void> {
    tapState = 'running';
    heading = 'Running action…';
    detail = 'Keep this page open.';
    outcome = '';
    retryAction = null;
    try {
      const result = await request<TapExecutionResponse>('/api/v1/taps/execute', { token, requestID, task });
      tapState = 'success';
      heading = result.actionName || 'Action complete';
      detail = result.actionDescription?.trim() || 'The Tap action is complete.';
      outcome = result.message || 'Done.';
    } catch (cause) {
      handleFailure(cause, () => execute(task));
    }
  }

  function handleFailure(cause: unknown, retry: () => Promise<void>): void {
    if (cause instanceof TapRequestError) {
      if (cause.status === 404 || cause.status === 410) {
        showRotation(cause.status === 404 ? 'This Tap link is not valid' : 'This Tap action is unavailable', cause.message);
        return;
      }
      if (cause.status === 422 && prepared?.kind === 'create_task') {
        tapState = 'ready';
        heading = prepared.actionName;
        detail = cause.message;
        return;
      }
      tapState = 'error';
      heading = cause.status === 429 ? 'Try again in a moment' : 'The action could not run';
      detail = cause.message;
      retryAction = cause.status === 429 || cause.status >= 500 ? retry : null;
      return;
    }
    tapState = 'error';
    heading = 'Flowboard could not be reached';
    detail = 'Check the network, then try again.';
    retryAction = retry;
  }

  function showRotation(title: string, message: string): void {
    tapState = 'rotation';
    heading = title;
    detail = message;
    outcome = '';
    retryAction = null;
  }

  function propertyValue(data: FormData, property: TapTaskProperty): string | undefined {
    if (property.type === 'multi_select') {
      const values = data.getAll(`property-${property.id}`).map(String).filter(Boolean);
      return values.length ? JSON.stringify(values) : undefined;
    }
    if (property.type === 'checkbox') return data.has(`property-${property.id}`) ? 'true' : undefined;
    const value = String(data.get(`property-${property.id}`) ?? '').trim();
    return value || undefined;
  }

  function submitTask(event: SubmitEvent): void {
    event.preventDefault();
    if (!prepared?.task) return;
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const properties: Record<string, string> = {};
    for (const property of prepared.task.properties) {
      const value = propertyValue(data, property);
      if (value) properties[property.id] = value;
    }
    void execute({
      title: String(data.get('title') ?? ''),
      description: String(data.get('description') ?? '') || null,
      status: String(data.get('status') ?? ''),
      priority: String(data.get('priority') ?? ''),
      labels: String(data.get('labels') ?? '').split(',').map((label) => label.trim()).filter(Boolean).slice(0, 6),
      startAt: String(data.get('startAt') ?? '') || null,
      dueAt: String(data.get('dueAt') ?? '') || null,
      properties
    });
  }
</script>

<svelte:head><title>Tap action · Flowboard</title><meta name="referrer" content="no-referrer" /><meta name="robots" content="noindex, nofollow" /></svelte:head>

<div class="tap-page">
  <header class="tap-header"><a class="tap-brand" href="/" aria-label="Flowboard home"><span class="brand-mark" aria-hidden="true"></span>Flowboard</a></header>
  <main>
    <section class="tap-card" data-state={tapState} aria-live="polite" aria-labelledby="tap-title">
      {#if tapState !== 'ready'}<div class="state-icon" aria-hidden="true">{#if tapState === 'running'}<span class="spinner"></span>{:else if tapState === 'success'}<span class="check">✓</span>{:else}<img src={tapState === 'rotation' ? '/tagneedsrotation.svg' : '/scanerror.svg'} alt="" />{/if}</div>{/if}
      <p class="state-label">{tapState === 'success' ? 'Action complete' : tapState === 'ready' ? 'Create task' : tapState === 'error' || tapState === 'rotation' ? 'Tap action stopped' : 'Tap action'}</p>
      <h1 id="tap-title">{heading}</h1>
      {#if detail}<p class="message">{detail}</p>{/if}
      {#if outcome}<p class="result">{outcome}</p>{/if}

      {#if tapState === 'ready' && prepared?.task}
        <form class="tap-form" onsubmit={submitTask}>
          <div class="form-grid">
            <label class="field wide"><span class="field-label">Task title</span><input bind:this={titleInput} name="title" maxlength="120" required /></label>
            <label class="field wide"><span class="field-label">Task description</span><textarea name="description" maxlength="5000"></textarea></label>
            <label class="field"><span class="field-label">Status</span><select name="status" value={prepared.task.status}>{#each prepared.task.statuses as option}<option value={option.id}>{option.name}</option>{/each}</select></label>
            <label class="field"><span class="field-label">Severity</span><select name="priority" value={prepared.task.priority}>{#each prepared.task.priorities as option}<option value={option.id}>{option.name}</option>{/each}</select></label>
            <label class="field"><span class="field-label">Start date</span><input type="date" name="startAt" /></label>
            <label class="field"><span class="field-label">Due date</span><input type="date" name="dueAt" /></label>
            <label class="field wide"><span class="field-label">Labels</span><input name="labels" maxlength="500" placeholder="Design, Launch" /></label>
            {#each prepared.task.properties as property (property.id)}
              <label class:wide={property.type === 'text' || property.type === 'checkbox'} class="field"><span class="field-label">{property.name}</span>
                {#if property.type === 'select' || property.type === 'person'}<select name={`property-${property.id}`}><option value="">Select an option</option>{#each property.options as option}<option value={option.id}>{option.name}</option>{/each}</select>{:else if property.type === 'multi_select'}<select name={`property-${property.id}`} multiple>{#each property.options as option}<option value={option.id}>{option.name}</option>{/each}</select>{:else if property.type === 'checkbox'}<span class="check-field"><input type="checkbox" name={`property-${property.id}`} />Set this field</span>{:else}<input type={property.type === 'text' ? 'text' : property.type} name={`property-${property.id}`} maxlength={property.type === 'text' ? 2000 : undefined} />{/if}
              </label>
            {/each}
          </div>
          <button type="submit">Create task</button>
        </form>
      {/if}
      {#if retryAction}<button type="button" onclick={() => retryAction?.()}>Try again</button>{/if}
      <noscript><p class="message">JavaScript is required to run this Tap action.</p></noscript>
    </section>
  </main>
</div>

<style>
  .tap-page { min-height: 100dvh; color: var(--text); background: var(--surface); font-family: system-ui, sans-serif; }
  .tap-header { display: flex; height: 64px; align-items: center; padding: 0 24px; }
  .tap-brand { display: inline-flex; min-height: 40px; align-items: center; gap: 9px; color: var(--text); font-weight: 600; text-decoration: none; }
  .brand-mark { display: grid; width: 28px; height: 28px; place-items: center; border-radius: 6px; background: var(--text); }
  .brand-mark::after { width: 0; height: 0; border-right: 6px solid transparent; border-bottom: 11px solid var(--surface); border-left: 6px solid transparent; content: ''; }
  main { display: grid; min-height: calc(100dvh - 64px); place-items: center; padding: 40px 24px 104px; }
  .tap-card { width: min(100%, 420px); }
  .state-icon { display: grid; width: 48px; height: 48px; margin-bottom: 24px; place-items: center; border-radius: 12px; background: var(--surface-sunken); box-shadow: var(--shadow-border); }
  .state-icon img { width: 30px; height: 30px; }
  .spinner { width: 18px; height: 18px; border: 2px solid var(--border-strong); border-top-color: var(--text); border-radius: 50%; animation: spin .7s linear infinite; }
  .check { color: var(--ds-green-700); font-size: 21px; font-weight: 600; }
  .state-label { margin: 0 0 8px; color: var(--text-tertiary); font-size: 12px; font-weight: 500; }
  h1 { margin: 0; font-size: 24px; font-weight: 600; letter-spacing: -.03em; line-height: 1.2; }
  .message { margin: 10px 0 0; color: var(--text-secondary); line-height: 1.55; white-space: pre-wrap; }
  .result { margin: 24px 0 0; padding: 11px 12px; border-radius: 8px; color: var(--ds-green-700); background: var(--ds-green-100); font-size: 13px; font-weight: 500; }
  .tap-form { display: grid; gap: 16px; margin-top: 24px; }
  .form-grid { display: grid; gap: 16px; grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .field { display: grid; gap: 7px; min-width: 0; }
  .field.wide { grid-column: 1 / -1; }
  .field-label { font-size: 13px; font-weight: 500; }
  input, textarea, select { width: 100%; min-height: 40px; border: 1px solid var(--border-strong); border-radius: 6px; color: var(--text); background: var(--surface); font: inherit; }
  input, select { padding: 0 11px; }
  textarea { min-height: 96px; padding: 10px 11px; resize: vertical; }
  select[multiple] { height: 112px; padding: 6px; }
  .check-field { display: flex; min-height: 40px; align-items: center; gap: 9px; color: var(--text-secondary); }
  .check-field input { width: 16px; min-height: 16px; }
  .tap-card button { display: inline-flex; height: 40px; align-items: center; justify-content: center; margin-top: 24px; padding: 0 16px; border: 0; border-radius: 6px; color: var(--surface); background: var(--text); cursor: pointer; font: inherit; font-weight: 500; }
  @keyframes spin { to { transform: rotate(360deg); } }
  @media (width <= 480px) { .tap-header { padding: 0 16px; } main { align-items: start; padding: min(18vh, 112px) 20px 64px; } .form-grid { grid-template-columns: 1fr; } .field.wide { grid-column: auto; } }
  @media (prefers-reduced-motion: reduce) { .spinner { animation-duration: 1.4s; } }
</style>
