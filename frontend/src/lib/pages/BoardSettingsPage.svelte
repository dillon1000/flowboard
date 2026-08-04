<script lang="ts">
  import { goto, invalidateAll } from '$app/navigation';
  import { api, messageFor } from '$lib/api';
  import type { BoardResponse, BoardSettingsPageContext, TapActionContext, TaskResponse } from '$lib/types';
  import { Archive, ChevronLeft, Columns3, Copy, Download, KeyRound, ListFilter, Plus, Settings, Tag, Trash2, Upload, Users, X } from '@lucide/svelte';
  import Avatar from '$lib/components/Avatar.svelte';
  import TapActionDialog from '$lib/components/TapActionDialog.svelte';

  let { board } = $props<{ board: BoardSettingsPageContext }>();
  let pending = $state(false);
  let requestError = $state('');
  let tapOpen = $state(false);
  let editingTap = $state<TapActionContext | null>(null);
  let provisionedURL = $state('');
  let copied = $state(false);
  let deleteOpen = $state(false);

  async function mutate(path: string, init: RequestInit): Promise<boolean> {
    pending = true;
    requestError = '';
    try {
      await api(path, init);
      await invalidateAll();
      return true;
    } catch (cause) {
      requestError = messageFor(cause);
      return false;
    } finally {
      pending = false;
    }
  }

  async function saveBoard(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    await mutate(`/api/v1/boards/${board.id}`, { method: 'PATCH', body: JSON.stringify({ name: String(data.get('name') ?? ''), description: String(data.get('description') ?? '') || null }) });
  }

  async function addView(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    if (await mutate(`/api/v1/boards/${board.id}/views`, { method: 'POST', body: JSON.stringify({ name: String(data.get('name') ?? ''), type: String(data.get('type') ?? 'board'), configuration: null }) })) form.reset();
  }

  async function configureView(event: SubmitEvent, viewID: string): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const filterField = String(data.get('filterField') ?? '').trim();
    const filterValue = String(data.get('filterValue') ?? '').trim();
    const sortField = String(data.get('sortField') ?? '').trim();
    await mutate(`/api/v1/boards/${board.id}/views/${viewID}`, {
      method: 'PATCH',
      body: JSON.stringify({
        configuration: {
          groupBy: String(data.get('groupBy') ?? 'status'),
          filters: filterField && filterValue ? [{ field: filterField, comparison: 'equals', value: filterValue }] : [],
          sorts: sortField ? [{ field: sortField, direction: String(data.get('sortDirection') ?? 'ascending') }] : []
        }
      })
    });
  }

  async function addWorkflowOption(event: SubmitEvent, kind: 'status' | 'severity'): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    if (await mutate(`/api/v1/boards/${board.id}/task-options`, { method: 'POST', body: JSON.stringify({ kind, name: String(data.get('name') ?? ''), color: String(data.get('color') ?? 'gray'), isCompleted: data.has('isCompleted') }) })) form.reset();
  }

  async function addProperty(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    if (await mutate(`/api/v1/boards/${board.id}/properties`, { method: 'POST', body: JSON.stringify({ name: String(data.get('name') ?? ''), type: String(data.get('type') ?? 'text'), options: String(data.get('options') ?? '').split(',').map((value) => value.trim()).filter(Boolean) }) })) form.reset();
  }

  async function addMember(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    if (await mutate(`/api/v1/boards/${board.id}/members`, { method: 'POST', body: JSON.stringify({ email: String(data.get('email') ?? ''), role: String(data.get('role') ?? 'editor') }) })) form.reset();
  }

  async function addTemplate(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    if (await mutate(`/api/v1/boards/${board.id}/templates`, { method: 'POST', body: JSON.stringify({ name: String(data.get('name') ?? ''), title: String(data.get('title') ?? ''), description: null, status: null, priority: null, labels: [], isDefault: false }) })) form.reset();
  }

  async function useTemplate(templateID: string): Promise<void> {
    pending = true;
    requestError = '';
    try {
      const task = await api<TaskResponse>(`/api/v1/boards/${board.id}/templates/${templateID}/instantiate`, { method: 'POST' });
      await goto(task.browserPath, { invalidateAll: true });
    } catch (cause) {
      requestError = messageFor(cause);
      pending = false;
    }
  }

  async function rotateTap(actionID: string): Promise<void> {
    pending = true;
    requestError = '';
    try {
      const result = await api<{ url: string }>(`/api/v1/boards/${board.id}/tap-actions/${actionID}/rotate`, { method: 'POST' });
      provisionedURL = result.url;
      await invalidateAll();
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pending = false;
    }
  }

  async function importBoard(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    if (await mutate(`/api/v1/boards/${board.id}/import`, { method: 'POST', body: new FormData(form) })) form.reset();
  }

  async function duplicateBoard(): Promise<void> {
    pending = true;
    requestError = '';
    try {
      const copy = await api<BoardResponse>(`/api/v1/boards/${board.id}/duplicate`, { method: 'POST' });
      await goto(`/app/boards/${copy.id}`, { invalidateAll: true });
    } catch (cause) {
      requestError = messageFor(cause);
      pending = false;
    }
  }

  async function deleteBoard(): Promise<void> {
    if (await mutate(`/api/v1/boards/${board.id}`, { method: 'DELETE' })) await goto('/app');
  }

  async function copyTapURL(): Promise<void> {
    await navigator.clipboard.writeText(provisionedURL);
    copied = true;
    setTimeout(() => (copied = false), 1800);
  }

  async function writeTapURL(): Promise<void> {
    type NDEFWriter = { write: (message: { records: { recordType: string; data: string }[] }) => Promise<void> };
    type NDEFConstructor = new () => NDEFWriter;
    const constructor = (globalThis as typeof globalThis & { NDEFReader?: NDEFConstructor }).NDEFReader;
    if (!constructor) {
      requestError = 'This browser does not support writing NFC tags.';
      return;
    }
    try {
      await new constructor().write({ records: [{ recordType: 'url', data: provisionedURL }] });
    } catch (cause) {
      requestError = messageFor(cause);
    }
  }
</script>

<div class="page">
  <header class="page-header"><div class="page-title"><a class="page-eyebrow" href={board.firstViewHref}><ChevronLeft size={14} />{board.name}</a><h1>Board settings</h1><p>Configure views, fields, templates, sharing, and data.</p></div></header>
  {#if requestError || board.hasTapError}<p class="error-message" role="alert">{requestError || board.tapError}</p>{/if}
  <div class="settings-grid">
    <nav class="settings-menu" aria-label="Board settings sections"><a class="nav-link" href="#general"><Settings size={15} /><span>General</span></a><a class="nav-link" href="#views"><Columns3 size={15} /><span>Views</span></a><a class="nav-link" href="#workflow"><ListFilter size={15} /><span>Workflow</span></a><a class="nav-link" href="#fields"><Tag size={15} /><span>Custom fields</span></a><a class="nav-link" href="#members"><Users size={15} /><span>Members</span></a><a class="nav-link" href="#templates"><Copy size={15} /><span>Templates</span></a><a class="nav-link" href="#tap-actions"><KeyRound size={15} /><span>Tap actions</span></a><a class="nav-link" href="#data"><Download size={15} /><span>Data</span></a><a class="nav-link" href="#danger"><Archive size={15} /><span>Board actions</span></a></nav>
    <div class="settings-content">
      <section class="section" id="general"><div class="section-heading"><h2>General</h2></div><form class="panel panel-form" onsubmit={saveBoard}><div class="field"><label for="settings-board-name">Name</label><input class="input" id="settings-board-name" name="name" value={board.name} minlength="2" maxlength="80" required /></div><div class="field"><label for="settings-board-description">Description</label><textarea class="textarea" id="settings-board-description" name="description" maxlength="500">{board.description}</textarea></div><div class="form-actions"><button class="button primary" type="submit" disabled={pending}>Save board</button></div></form></section>

      <section class="section" id="views"><div class="section-heading"><div><h2>Views</h2><p>Saved layouts can keep their own filters and sorting.</p></div></div><div class="panel">
        {#each board.views as view (view.id)}<details class="panel-row settings-details"><summary><Columns3 size={15} /><span class="panel-row-main"><strong>{view.name}</strong><span>{view.typeName} · Grouped by {view.groupByName}</span></span><span class="button small">Configure</span></summary><form class="details-form" onsubmit={(event) => configureView(event, view.id)}><div class="form-grid"><div class="field"><label for={`group-${view.id}`}>Group by</label><select class="input" id={`group-${view.id}`} name="groupBy" value={view.groupBy}><option value="status">Status</option><option value="priority">Severity</option></select></div><div class="field"><label for={`filter-field-${view.id}`}>Filter field</label><input class="input" id={`filter-field-${view.id}`} name="filterField" value={view.filterField} /></div><div class="field"><label for={`filter-value-${view.id}`}>Filter value</label><input class="input" id={`filter-value-${view.id}`} name="filterValue" value={view.filterValue} /></div><div class="field"><label for={`sort-field-${view.id}`}>Sort field</label><input class="input" id={`sort-field-${view.id}`} name="sortField" value={view.sortField} /></div><div class="field"><label for={`sort-direction-${view.id}`}>Direction</label><select class="input" id={`sort-direction-${view.id}`} name="sortDirection" value={view.sortDirection}><option value="ascending">Ascending</option><option value="descending">Descending</option></select></div></div><div class="form-actions"><button class="button primary small" type="submit" disabled={pending}>Save view</button><button class="button danger small" type="button" onclick={() => mutate(`/api/v1/boards/${board.id}/views/${view.id}`, { method: 'DELETE' })} disabled={pending}>Delete view</button></div></form></details>{/each}
        <form class="panel-row" onsubmit={addView}><input class="input" name="name" placeholder="View name" maxlength="60" required /><select class="input" name="type"><option value="board">Board</option><option value="table">Table</option><option value="calendar">Calendar</option><option value="gallery">Gallery</option></select><button class="button small" type="submit" disabled={pending}>Add view</button></form>
      </div></section>

      <section class="section" id="workflow"><div class="section-heading"><div><h2>Workflow</h2><p>Add the status and severity values that this board needs.</p></div></div><div class="settings-split"><div class="panel"><div class="panel-row"><span class="panel-row-main"><strong>Statuses</strong><span>Completed statuses count toward board progress.</span></span></div>{#each board.statuses as option}<div class="panel-row"><span class={`badge status ${option.colorClass}`} style={option.colorStyle}>{option.name}</span><span class="panel-row-main"><span>{option.isCompleted ? 'Counts as completed' : 'Active work'}</span></span></div>{/each}<form class="panel-row workflow-option-form" onsubmit={(event) => addWorkflowOption(event, 'status')}><input class="input" name="name" placeholder="Status name" maxlength="40" required /><select class="input" name="color"><option>gray</option><option>blue</option><option>purple</option><option>green</option><option>amber</option><option>orange</option><option>red</option></select><label class="checkbox-label"><input type="checkbox" name="isCompleted" /><span>Completed</span></label><button class="button small" type="submit">Add status</button></form></div><div class="panel"><div class="panel-row"><span class="panel-row-main"><strong>Severities</strong><span>Severity describes effect or urgency.</span></span></div>{#each board.severities as option}<div class="panel-row"><span class={`badge ${option.colorClass}`} style={option.colorStyle}>{option.name}</span></div>{/each}<form class="panel-row workflow-option-form" onsubmit={(event) => addWorkflowOption(event, 'severity')}><input class="input" name="name" placeholder="Severity name" maxlength="40" required /><select class="input" name="color"><option>gray</option><option>blue</option><option>purple</option><option>green</option><option>amber</option><option>orange</option><option>red</option></select><button class="button small" type="submit">Add severity</button></form></div></div></section>

      <section class="section" id="fields"><div class="section-heading"><div><h2>Custom fields</h2><p>Add typed fields to every task on this board.</p></div></div><div class="panel">{#each board.properties as property}<div class="panel-row"><Tag size={15} /><span class="panel-row-main"><strong>{property.name}</strong><span>{property.detail}</span></span></div>{/each}<form class="panel-row wrap-row" onsubmit={addProperty}><input class="input" name="name" placeholder="Field name" maxlength="60" required /><select class="input" name="type"><option value="text">Text</option><option value="number">Number</option><option value="select">Select</option><option value="multi_select">Multi-select</option><option value="date">Date</option><option value="checkbox">Checkbox</option><option value="url">URL</option><option value="email">Email</option><option value="person">Person</option></select><input class="input" name="options" placeholder="Options, comma-separated" /><button class="button small" type="submit">Add field</button></form></div></section>

      <section class="section" id="members"><div class="section-heading"><div><h2>Members</h2><p>Roles control access to this course.</p></div></div><div class="panel"><div class="panel-row"><Avatar avatar={board.ownerAvatar} /><span class="panel-row-main"><strong>{board.ownerName}</strong><span>{board.ownerEmail}</span></span><span class="badge">Owner</span></div>{#each board.members as member (member.id)}<div class="panel-row"><Avatar avatar={member.avatar} /><span class="panel-row-main"><strong>{member.name}</strong><span>{member.email}</span></span><span class="badge">{member.role}</span><button class="icon-button" type="button" onclick={() => mutate(`/api/v1/boards/${board.id}/members/${member.id}`, { method: 'DELETE' })} aria-label={`Remove ${member.name}`}><X size={14} /></button></div>{/each}<form class="panel-row" onsubmit={addMember}><input class="input" type="email" name="email" placeholder="Member email" required /><select class="input" name="role"><option value="viewer">Viewer</option><option value="commenter">Commenter</option><option value="editor" selected>Editor</option><option value="admin">Admin</option></select><button class="button small" type="submit">Share</button></form></div></section>

      <section class="section" id="templates"><div class="section-heading"><div><h2>Task templates</h2><p>Reuse common task structure.</p></div></div><div class="panel">{#each board.templates as template (template.id)}<div class="panel-row"><Copy size={15} /><span class="panel-row-main"><strong>{template.name}</strong><span>{template.title}</span></span>{#if template.isDefault}<span class="badge">Default</span>{/if}<button class="button small" type="button" onclick={() => useTemplate(template.id)}>Use</button><button class="button ghost small" type="button" onclick={() => mutate(`/api/v1/boards/${board.id}/templates/${template.id}`, { method: 'PATCH', body: JSON.stringify({ isDefault: true }) })}>Set default</button><button class="icon-button" type="button" onclick={() => mutate(`/api/v1/boards/${board.id}/templates/${template.id}`, { method: 'DELETE' })} aria-label={`Delete ${template.name}`}><X size={14} /></button></div>{/each}<form class="panel-row" onsubmit={addTemplate}><input class="input" name="name" placeholder="Template name" required /><input class="input" name="title" placeholder="Default task title" required /><button class="button small" type="submit">Add template</button></form></div></section>

      <section class="section" id="tap-actions"><div class="section-heading"><div><h2>Tap actions</h2><p>Run a fixed task change from an NFC tag without signing in.</p></div><button class="button primary" type="button" onclick={() => { editingTap = null; tapOpen = true; }}><Plus size={14} />New Tap action</button></div>
        {#if provisionedURL}<div class="panel tap-provision"><div class="tap-provision-main"><div><strong>Program this tag now</strong><span>This bearer link is shown once.</span></div><code class="tap-url-secret">{provisionedURL}</code><div class="tap-provision-actions"><button class="button" type="button" onclick={copyTapURL}><Copy size={14} />{copied ? 'Copied' : 'Copy link'}</button><button class="button primary" type="button" onclick={writeTapURL}><Tag size={14} />Write NFC tag</button><span class="tap-provision-status">{new TextEncoder().encode(provisionedURL).length} UTF-8 bytes.</span></div></div></div>{/if}
        <div class="panel tap-action-list">{#if board.hasTapActions}{#each board.tapActions as action (action.id)}<div class="panel-row tap-action-row"><Tag size={15} /><span class="panel-row-main"><strong>{action.name}</strong>{#if action.hasDisplayDescription}<span>{action.displayDescription}</span>{/if}<span>{action.summary} · {action.useLimitLabel} · Expires {action.expiresAtLabel}</span></span><code class="tap-token-prefix">{action.prefix}…</code><span class:success={action.isActive} class="badge subtle">{action.stateName}</span><button class="button small" type="button" onclick={() => mutate(`/api/v1/boards/${board.id}/tap-actions/${action.id}`, { method: 'PATCH', body: JSON.stringify({ isEnabled: !action.isEnabled }) })}>{action.isEnabled ? 'Disable' : 'Enable'}</button><button class="button ghost small" type="button" onclick={() => rotateTap(action.id)}>Rotate link</button><button class="button ghost small" type="button" onclick={() => { editingTap = action; tapOpen = true; }}>Edit</button><button class="icon-button" type="button" onclick={() => confirm('Delete this Tap action?') && mutate(`/api/v1/boards/${board.id}/tap-actions/${action.id}`, { method: 'DELETE' })} aria-label={`Delete ${action.name}`}><Trash2 size={14} /></button></div>{/each}{:else}<div class="panel-row"><Tag size={15} /><span class="panel-row-main"><strong>No Tap actions yet</strong><span>Create one, then write its one-time link to an NFC tag.</span></span></div>{/if}</div>
        {#if board.hasTapExecutions}<div class="tap-history"><h3>Recent uses</h3><div class="panel">{#each board.tapExecutions as execution}<div class="panel-row"><span class="panel-row-main"><strong>{execution.actionName}</strong><span>{execution.message}</span></span><time class="tap-history-time">{execution.createdAt}</time></div>{/each}</div></div>{/if}
      </section>

      <section class="section" id="data"><div class="section-heading"><h2>Data</h2></div><div class="panel"><div class="panel-row"><span class="panel-row-main"><strong>Export board</strong><span>Download tasks and configuration as JSON.</span></span><a class="button" href={`/api/v1/boards/${board.id}/export`}><Download size={14} />Export</a></div><form class="panel-row" onsubmit={importBoard}><span class="panel-row-main"><strong>Import board</strong><span>Add tasks from a Flowboard JSON export.</span></span><label class="button"><Upload size={14} />Choose file<input class="sr-only" type="file" name="file" accept="application/json" required /></label><button class="button" type="submit">Import</button></form></div></section>

      <section class="section" id="danger"><div class="section-heading"><h2>Board actions</h2></div><div class="panel danger-zone"><div class="panel-row"><span class="panel-row-main"><strong>{board.isArchived ? 'Restore board' : 'Archive board'}</strong><span>Archived boards leave the main navigation.</span></span><button class="button" type="button" onclick={() => mutate(`/api/v1/boards/${board.id}`, { method: 'PATCH', body: JSON.stringify({ isArchived: !board.isArchived }) })}><Archive size={14} />{board.isArchived ? 'Restore' : 'Archive'}</button></div><div class="panel-row"><span class="panel-row-main"><strong>Duplicate board</strong><span>Copy tasks, views, fields, and templates.</span></span><button class="button" type="button" onclick={duplicateBoard}><Copy size={14} />Duplicate</button></div>{#if board.isOwner}<div class="panel-row"><span class="panel-row-main"><strong>Delete board</strong><span>Permanently remove this board and its tasks.</span></span><button class="button danger" type="button" onclick={() => (deleteOpen = true)}>Delete</button></div>{/if}</div></section>
    </div>
  </div>
</div>

<TapActionDialog bind:open={tapOpen} {board} action={editingTap} onprovision={(url) => (provisionedURL = url)} />
{#if deleteOpen}<div class="dialog-layer" role="alertdialog" aria-modal="true" aria-labelledby="delete-board-title" tabindex="-1" onkeydown={(event) => event.key === 'Escape' && (deleteOpen = false)}><div class="dialog"><div class="dialog-header"><div><h2 id="delete-board-title">Delete {board.name}?</h2><p>This action cannot be undone.</p></div></div><div class="dialog-footer"><button class="button" type="button" onclick={() => (deleteOpen = false)}>Cancel</button><button class="button danger" type="button" onclick={deleteBoard}>Delete board</button></div></div></div>{/if}
