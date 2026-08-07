<script lang="ts">
  import { goto } from '$app/navigation';
  import { dialogLayer } from '$lib/actions/dialogLayer';
  import { api, messageFor, refreshAll } from '$lib/api';
  import Avatar from '$lib/components/Avatar.svelte';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import PopoverMenu from '$lib/components/PopoverMenu.svelte';
  import TapActionDialog from '$lib/components/TapActionDialog.svelte';
  import WorkflowColorField from '$lib/components/WorkflowColorField.svelte';
  import SelectMenu, { type SelectMenuOption } from '$lib/components/SelectMenu.svelte';
  import type {
    BoardResponse,
    BoardMemberContext,
    BoardSettingsPageContext,
    BoardSettingsViewContext,
    PropertyDefinitionContext,
    TapActionContext,
    TemplateContext,
    TaskOptionContext,
    TaskResponse
  } from '$lib/types';
  import { showToast } from '$lib/ui/toast';
  import {
    ArchiveIcon as Archive,
    CheckIcon as Check,
    CaretLeftIcon as ChevronLeft,
    ColumnsIcon as Columns3,
    CopyIcon as Copy,
    DownloadIcon as Download,
    DotsThreeIcon as DotsThree,
    ListChecksIcon as ListChecks,
    PlusIcon as Plus,
    GearIcon as Settings,
    TagIcon as Tag,
    TextTIcon as TextT,
    TrashIcon as Trash2,
    UploadIcon as Upload,
    UsersIcon as Users,
    XIcon as X
  } from 'phosphor-svelte';
  import { onMount } from 'svelte';

  // Common NFC tags expose 504 writable bytes. The generated link normally fits,
  // but the UI reports and blocks an oversized link before the browser starts.
  const standardNFCTagBytes = 504;

  let { board } = $props<{ board: BoardSettingsPageContext }>();
  let pendingCount = $state(0);
  const pending = $derived(pendingCount > 0);
  let requestError = $state('');
  let tapOpen = $state(false);
  let editingTap = $state<TapActionContext | null>(null);
  let editingView = $state<BoardSettingsViewContext | null>(null);
  let deletingView = $state<BoardSettingsViewContext | null>(null);
  let deletingTap = $state<TapActionContext | null>(null);
  let removingMember = $state<BoardMemberContext | null>(null);
  let deletingTemplate = $state<TemplateContext | null>(null);
  let editingProperty = $state<PropertyDefinitionContext | null>(null);
  let deletingProperty = $state<PropertyDefinitionContext | null>(null);
  let archiveOpen = $state(false);
  let duplicateOpen = $state(false);
  let viewFilterField = $state('');
  let viewFilterValue = $state('');
  let editingWorkflowOption = $state<{
    kind: 'status' | 'severity';
    option: TaskOptionContext;
  } | null>(null);
  let provisionedURLOverride = $state('');
  let provisionStatus = $state('');
  let copied = $state(false);
  let nfcSupported = $state(false);
  let deleteOpen = $state(false);
  let propertyType = $state('text');
  const viewTypeOptions: SelectMenuOption[] = [
    { value: 'board', label: 'Columns' },
    { value: 'table', label: 'Table' },
    { value: 'calendar', label: 'Calendar' },
    { value: 'gantt', label: 'Gantt' },
    { value: 'gallery', label: 'Gallery' }
  ];
  const fieldTypeOptions: SelectMenuOption[] = [
    { value: 'text', label: 'Text' },
    { value: 'number', label: 'Number' },
    { value: 'select', label: 'Select' },
    { value: 'multi_select', label: 'Multi-select' },
    { value: 'date', label: 'Date' },
    { value: 'checkbox', label: 'Checkbox' },
    { value: 'url', label: 'URL' },
    { value: 'email', label: 'Email' },
    { value: 'person', label: 'Person' }
  ];
  const memberRoleOptions: SelectMenuOption[] = [
    { value: 'viewer', label: 'Viewer' },
    { value: 'commenter', label: 'Commenter' },
    { value: 'editor', label: 'Editor' },
    { value: 'admin', label: 'Admin' }
  ];
  const groupOptions: SelectMenuOption[] = [
    { value: 'status', label: 'Status' },
    { value: 'priority', label: 'Priority' }
  ];
  const sortDirectionOptions: SelectMenuOption[] = [
    { value: 'ascending', label: 'Ascending' },
    { value: 'descending', label: 'Descending' }
  ];
  const sortFieldOptions: SelectMenuOption[] = [
    { value: '', label: 'No sorting' },
    { value: 'title', label: 'Assignment title' },
    { value: 'due_at', label: 'Due date' },
    { value: 'priority', label: 'Priority' }
  ];
  const filterFieldOptions = $derived<SelectMenuOption[]>([
    { value: '', label: 'No filter' },
    { value: 'status', label: 'Status' },
    { value: 'priority', label: 'Priority' },
    ...(board.filterLabels.length ? [{ value: 'label', label: 'Label' }] : []),
    ...board.properties.filter((property: PropertyDefinitionContext) => property.hasOptions).map((property: PropertyDefinitionContext) => ({ value: property.id, label: property.name }))
  ]);
  const filterValueOptions = $derived.by<SelectMenuOption[]>(() => {
    if (viewFilterField === 'status') return board.statuses.map((option: TaskOptionContext) => ({ value: option.value, label: option.name }));
    if (viewFilterField === 'priority') return board.severities.map((option: TaskOptionContext) => ({ value: option.value, label: option.name }));
    if (viewFilterField === 'label') return board.filterLabels.map((label: string) => ({ value: label, label }));
    return board.properties.find((property: PropertyDefinitionContext) => property.id === viewFilterField)?.options ?? [{ value: '', label: 'No value' }];
  });

  const provisionedURL = $derived(provisionedURLOverride || board.createdTapURL);
  const provisionedURLByteCount = $derived(
    provisionedURL ? new TextEncoder().encode(provisionedURL).length : 0
  );
  const propertyNeedsOptions = $derived(propertyType === 'select' || propertyType === 'multi_select');

  function selectPropertyType(value: string): void {
    propertyType = value;
  }

  onMount(() => {
    nfcSupported = 'NDEFReader' in globalThis;
    if (provisionedURL) provisionStatus = tapSizeLabel(provisionedURLByteCount);
  });

  function tapSizeLabel(byteCount: number): string {
    const comparison = byteCount <= standardNFCTagBytes ? 'below' : 'above';
    return `${byteCount} UTF-8 bytes, ${comparison} the ${standardNFCTagBytes}-byte tag limit.`;
  }

  async function mutate(path: string, init: RequestInit, successMessage = ''): Promise<boolean> {
    pendingCount += 1;
    requestError = '';
    try {
      await api(path, init);
      await refreshAll();
      if (successMessage) showToast(successMessage);
      return true;
    } catch (cause) {
      requestError = messageFor(cause);
      return false;
    } finally {
      pendingCount -= 1;
    }
  }

  function deleteSelectedView(): Promise<boolean> {
    if (!deletingView) return Promise.resolve(false);
    return mutate(`/api/v1/boards/${board.id}/views/${deletingView.id}`, { method: 'DELETE' }, 'View deleted');
  }

  function deleteSelectedTap(): Promise<boolean> {
    if (!deletingTap) return Promise.resolve(false);
    return mutate(`/api/v1/boards/${board.id}/tap-actions/${deletingTap.id}`, { method: 'DELETE' }, 'Tap action deleted');
  }

  function removeSelectedMember(): Promise<boolean> {
    if (!removingMember) return Promise.resolve(false);
    return mutate(`/api/v1/boards/${board.id}/members/${removingMember.id}`, { method: 'DELETE' }, 'Member removed');
  }

  function deleteSelectedTemplate(): Promise<boolean> {
    if (!deletingTemplate) return Promise.resolve(false);
    return mutate(`/api/v1/boards/${board.id}/templates/${deletingTemplate.id}`, { method: 'DELETE' }, 'Template deleted');
  }

  function deleteSelectedProperty(): Promise<boolean> {
    if (!deletingProperty) return Promise.resolve(false);
    return mutate(`/api/v1/boards/${board.id}/properties/${deletingProperty.id}`, { method: 'DELETE' }, 'Custom field deleted');
  }

  function archiveCourse(): Promise<boolean> {
    return mutate(`/api/v1/boards/${board.id}`, { method: 'PATCH', body: JSON.stringify({ isArchived: true }) }, 'Course archived');
  }

  function openViewEditor(view: BoardSettingsViewContext): void {
    viewFilterField = view.filterField;
    viewFilterValue = view.filterValue;
    editingView = view;
  }

  function selectFilterField(value: string): void {
    viewFilterField = value;
    viewFilterValue = filterValueOptions[0]?.value ?? '';
  }

  async function saveBoard(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    await mutate(
      `/api/v1/boards/${board.id}`,
      {
        method: 'PATCH',
        body: JSON.stringify(board.isCanvasLinked
          ? { description: String(data.get('description') ?? '') || null }
          : { name: String(data.get('name') ?? ''), description: String(data.get('description') ?? '') || null })
      },
      'Course saved'
    );
  }

  async function addView(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    const saved = await mutate(
      `/api/v1/boards/${board.id}/views`,
      {
        method: 'POST',
        body: JSON.stringify({
          name: String(data.get('name') ?? ''),
          type: String(data.get('type') ?? 'board'),
          configuration: null
        })
      },
      'View added'
    );
    if (saved) form.reset();
  }

  async function configureView(event: SubmitEvent, viewID: string): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const filterField = String(data.get('filterField') ?? '').trim();
    const filterValue = String(data.get('filterValue') ?? '').trim();
    const sortField = String(data.get('sortField') ?? '').trim();
    const saved = await mutate(
      `/api/v1/boards/${board.id}/views/${viewID}`,
      {
        method: 'PATCH',
        body: JSON.stringify({
          name: String(data.get('name') ?? ''),
          type: String(data.get('type') ?? 'board'),
          configuration: {
            groupBy: String(data.get('groupBy') ?? 'status'),
            filters: filterField && filterValue
              ? [{ field: filterField, comparison: 'equals', value: filterValue }]
              : [],
            sorts: sortField
              ? [{ field: sortField, direction: String(data.get('sortDirection') ?? 'ascending') }]
              : []
          }
        })
      },
      'View saved'
    );
    if (saved) editingView = null;
  }

  async function editWorkflowOption(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    if (!editingWorkflowOption) return;
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const { kind, option } = editingWorkflowOption;
    const saved = await mutate(
      `/api/v1/boards/${board.id}/task-options/${option.value}`,
      {
        method: 'PATCH',
        body: JSON.stringify({
          kind,
          name: String(data.get('name') ?? ''),
          color: String(data.get('color') ?? 'gray'),
          isCompleted: kind === 'status' && data.has('isCompleted')
        })
      },
      kind === 'status' ? 'Status saved' : 'Priority saved'
    );
    if (saved) editingWorkflowOption = null;
  }

  async function addWorkflowOption(event: SubmitEvent, kind: 'status' | 'severity'): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    const saved = await mutate(
      `/api/v1/boards/${board.id}/task-options`,
      {
        method: 'POST',
        body: JSON.stringify({
          kind,
          name: String(data.get('name') ?? ''),
          color: String(data.get('color') ?? 'gray'),
          isCompleted: data.has('isCompleted')
        })
      },
      kind === 'status' ? 'Status added' : 'Priority added'
    );
    if (saved) form.reset();
  }

  async function addProperty(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    const saved = await mutate(
      `/api/v1/boards/${board.id}/properties`,
      {
        method: 'POST',
        body: JSON.stringify({
          name: String(data.get('name') ?? ''),
          type: propertyType,
          options: String(data.get('options') ?? '').split(',').map((value) => value.trim()).filter(Boolean)
        })
      },
      'Custom field added'
    );
    if (saved) {
      form.reset();
      propertyType = 'text';
    }
  }

  async function saveProperty(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    if (!editingProperty) return;
    const name = String(new FormData(event.currentTarget as HTMLFormElement).get('name') ?? '');
    const saved = await mutate(`/api/v1/boards/${board.id}/properties/${editingProperty.id}`, {
      method: 'PATCH',
      body: JSON.stringify({ name })
    }, 'Custom field saved');
    if (saved) editingProperty = null;
  }

  async function addMember(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    const saved = await mutate(
      `/api/v1/boards/${board.id}/members`,
      {
        method: 'POST',
        body: JSON.stringify({
          email: String(data.get('email') ?? ''),
          role: String(data.get('role') ?? 'editor')
        })
      },
      'Member added'
    );
    if (saved) form.reset();
  }

  async function addTemplate(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    const saved = await mutate(
      `/api/v1/boards/${board.id}/templates`,
      {
        method: 'POST',
        body: JSON.stringify({
          name: String(data.get('name') ?? ''),
          title: String(data.get('title') ?? ''),
          description: null,
          status: null,
          priority: null,
          labels: [],
          isDefault: false
        })
      },
      'Template added'
    );
    if (saved) form.reset();
  }

  async function useTemplate(templateID: string): Promise<void> {
    pendingCount += 1;
    requestError = '';
    try {
      const task = await api<TaskResponse>(
        `/api/v1/boards/${board.id}/templates/${templateID}/instantiate`,
        { method: 'POST' }
      );
      showToast('Assignment created from template');
      await goto(task.browserPath, { invalidateAll: true });
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingCount -= 1;
    }
  }

  function provisionTap(url: string): void {
    provisionedURLOverride = url;
    provisionStatus = tapSizeLabel(new TextEncoder().encode(url).length);
    copied = false;
  }

  async function rotateTap(actionID: string): Promise<void> {
    pendingCount += 1;
    requestError = '';
    try {
      const result = await api<{ url: string }>(
        `/api/v1/boards/${board.id}/tap-actions/${actionID}/rotate`,
        { method: 'POST' }
      );
      provisionTap(result.url);
      await refreshAll();
      showToast('Tap link rotated');
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pendingCount -= 1;
    }
  }

  async function importBoard(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const saved = await mutate(
      `/api/v1/boards/${board.id}/import`,
      { method: 'POST', body: new FormData(form) },
      'Course data imported'
    );
    if (saved) form.reset();
  }

  async function duplicateBoard(): Promise<boolean> {
    pendingCount += 1;
    requestError = '';
    try {
      const copy = await api<BoardResponse>(`/api/v1/boards/${board.id}/duplicate`, { method: 'POST' });
      showToast('Course duplicated');
      await goto(`/app/boards/${copy.id}`, { invalidateAll: true });
      return true;
    } catch (cause) {
      requestError = messageFor(cause);
      return false;
    } finally {
      pendingCount -= 1;
    }
  }

  async function deleteBoard(): Promise<void> {
    if (await mutate(`/api/v1/boards/${board.id}`, { method: 'DELETE' }, 'Course deleted')) {
      await goto('/app', { invalidateAll: true });
    }
  }

  async function copyTapURL(): Promise<void> {
    requestError = '';
    try {
      await navigator.clipboard.writeText(provisionedURL);
      copied = true;
      provisionStatus = 'Link copied. ' + tapSizeLabel(provisionedURLByteCount);
      showToast('Tap link copied');
      setTimeout(() => (copied = false), 1800);
    } catch (cause) {
      requestError = messageFor(cause);
      provisionStatus = 'The browser could not copy the link.';
    }
  }

  async function writeTapURL(): Promise<void> {
    type NDEFWriter = { write: (message: { records: { recordType: string; data: string }[] }) => Promise<void> };
    type NDEFConstructor = new () => NDEFWriter;
    const constructor = (globalThis as typeof globalThis & { NDEFReader?: NDEFConstructor }).NDEFReader;
    if (!constructor) {
      requestError = 'This browser does not support writing NFC tags.';
      return;
    }

    requestError = '';
    provisionStatus = 'Hold the NFC tag near this device.';
    try {
      await new constructor().write({ records: [{ recordType: 'url', data: provisionedURL }] });
      provisionStatus = 'NFC tag written. ' + tapSizeLabel(provisionedURLByteCount);
      showToast('NFC tag written');
    } catch (cause) {
      requestError = messageFor(cause);
      provisionStatus = 'The NFC write did not finish.';
    }
  }
</script>

<div class="page narrow">
  <header class="page-header">
    <div class="page-title">
      <a class="page-eyebrow" href={board.firstViewHref}><ChevronLeft size={14} />{board.name}</a>
      <h1>Course settings</h1>
      <p>Everything this course owns — basics, layout, workflow, sharing, and data.</p>
    </div>
  </header>

  {#if requestError || board.hasTapError}
    <p class="error-message" role="alert">{requestError || board.tapError}</p>
  {/if}

  <div class="settings-grid">
    <nav class="settings-menu" aria-label="Course settings sections">
      <a class="nav-link" href="#general"><Settings size={15} /><span>General</span></a>
      <a class="nav-link" href="#views"><Columns3 size={15} /><span>Views</span></a>
      <a class="nav-link" href="#workflow"><ListChecks size={15} /><span>Workflow</span></a>
      <a class="nav-link" href="#fields"><TextT size={15} /><span>Custom fields</span></a>
      <a class="nav-link" href="#members"><Users size={15} /><span>Members</span></a>
      <a class="nav-link" href="#templates"><Copy size={15} /><span>Templates</span></a>
      <a class="nav-link" href="#tap-actions"><Tag size={15} /><span>Tap actions</span></a>
      <a class="nav-link" href="#data"><Download size={15} /><span>Data</span></a>
      <a class="nav-link" href="#danger"><Archive size={15} /><span>Course actions</span></a>
    </nav>

    <div class="settings-content">
      <section class="section" id="general">
        <div class="section-heading"><h2>General</h2></div>
        <form class="panel panel-form" onsubmit={saveBoard}>
          <div class="field"><label for="settings-board-name">Name</label><input class="input" id="settings-board-name" name="name" value={board.name} minlength="2" maxlength="80" required readonly={board.isCanvasLinked} aria-describedby={board.isCanvasLinked ? 'canvas-board-name-help' : undefined} />{#if board.isCanvasLinked}<span class="field-help" id="canvas-board-name-help">Canvas manages the course name.</span>{/if}</div>
          <div class="field"><label for="settings-board-description">Description</label><textarea class="textarea" id="settings-board-description" name="description" maxlength="500">{board.description}</textarea></div>
          <div class="form-actions"><button class="button primary" type="submit" disabled={pending}>Save course</button></div>
        </form>
      </section>

      <section class="section" id="views">
        <div class="section-heading"><div><h2>Views</h2><p>Saved layouts can keep their own filters and sorting.</p></div></div>
        <div class="panel">
          {#each board.views as view (view.id)}
            <div class="panel-row">
              <Columns3 size={15} />
              <span class="panel-row-main"><strong>{view.name}</strong><span>{view.typeName} · Grouped by {view.groupByName}</span></span>
              <button class="button small" type="button" onclick={() => openViewEditor(view)}>Configure</button>
              <button class="icon-button" type="button" onclick={() => (deletingView = view)} aria-label={`Delete ${view.name}`} disabled={pending}><X size={14} /></button>
            </div>
          {/each}
          <form class="panel-row" onsubmit={addView}>
            <input class="input" name="name" placeholder="View name" maxlength="60" required />
            <SelectMenu name="type" value="board" options={viewTypeOptions} ariaLabel="View type" />
            <button class="button small" type="submit" disabled={pending}>Add view</button>
          </form>
        </div>
      </section>

      <section class="section" id="workflow">
        <div class="section-heading"><div><h2>Workflow</h2><p>Add the status and priority values that this course needs.</p></div></div>
        <div class="settings-split">
          <div class="panel">
            <div class="panel-row"><span class="panel-row-main"><strong>Statuses</strong><span>Completed statuses count toward course progress.</span></span></div>
            {#each board.statuses as option (option.value)}
              <div class="panel-row">
                <span class={`badge status ${option.colorClass}`} style={option.colorStyle}>{option.name}</span>
                <span class="panel-row-main"><span>{option.isCompleted ? 'Counts as completed' : 'Active work'}</span></span>
                <button class="button small" type="button" aria-label={`Edit status ${option.name}`} onclick={() => (editingWorkflowOption = { kind: 'status', option })}>Edit</button>
              </div>
            {/each}
            <form class="panel-row workflow-option-form" onsubmit={(event) => addWorkflowOption(event, 'status')}>
              <input class="input" name="name" placeholder="Status name" maxlength="40" required />
              <WorkflowColorField />
              <label class="checkbox-label"><input class="checkbox-input" type="checkbox" name="isCompleted" value="true" /><span class="checkbox-control" aria-hidden="true"><Check size={13} /></span><span>Completed</span></label>
              <button class="button small" type="submit" disabled={pending}>Add status</button>
            </form>
          </div>

          <div class="panel">
            <div class="panel-row"><span class="panel-row-main"><strong>Priorities</strong><span>Priority shows which assignments need attention first.</span></span></div>
            {#each board.severities as option (option.value)}
              <div class="panel-row">
                <span class={`badge ${option.colorClass}`} style={option.colorStyle}>{option.name}</span>
                <span class="panel-row-main"></span>
                <button class="button small" type="button" aria-label={`Edit priority ${option.name}`} onclick={() => (editingWorkflowOption = { kind: 'severity', option })}>Edit</button>
              </div>
            {/each}
            <form class="panel-row workflow-option-form" onsubmit={(event) => addWorkflowOption(event, 'severity')}>
              <input class="input" name="name" placeholder="Priority name" maxlength="40" required />
              <WorkflowColorField />
              <button class="button small" type="submit" disabled={pending}>Add priority</button>
            </form>
          </div>
        </div>
      </section>

      <section class="section" id="fields">
        <div class="section-heading"><div><h2>Custom fields</h2><p>Add typed fields to every assignment in this course.</p></div></div>
        <div class="panel">
          {#each board.properties as property (property.id)}
            <div class="panel-row">
              <Tag size={15} />
              <span class="panel-row-main"><strong>{property.name}</strong><span>{property.detail}</span></span>
              <button class="button small" type="button" onclick={() => (editingProperty = property)}>Edit</button>
              <button class="icon-button" type="button" onclick={() => (deletingProperty = property)} aria-label={`Delete ${property.name}`} disabled={pending}><Trash2 size={14} /></button>
            </div>
          {/each}
          <form class="panel-row" onsubmit={addProperty}>
            <input class="input" name="name" placeholder="Field name" maxlength="60" required />
            <SelectMenu name="type" value={propertyType} options={fieldTypeOptions} ariaLabel="Field type" onchange={selectPropertyType} />
            {#if propertyNeedsOptions}<input class="input" name="options" placeholder="Options, comma-separated" aria-label="Field options" maxlength="800" required />{/if}
            <button class="button small" type="submit" disabled={pending}>Add field</button>
          </form>
        </div>
      </section>

      <section class="section" id="members">
        <div class="section-heading"><div><h2>Members</h2><p>Viewer, Commenter, Editor, and Admin roles control access.</p></div></div>
        <div class="panel">
          <div class="panel-row"><Avatar avatar={board.ownerAvatar} /><span class="panel-row-main"><strong>{board.ownerName}</strong><span>{board.ownerEmail}</span></span><span class="badge">Owner</span></div>
          {#each board.members as member (member.id)}<div class="panel-row"><Avatar avatar={member.avatar} /><span class="panel-row-main"><strong>{member.name}</strong><span>{member.email}</span></span><span class="badge">{member.role}</span><button class="icon-button" type="button" onclick={() => (removingMember = member)} aria-label={`Remove ${member.name}`} disabled={pending}><X size={14} /></button></div>{/each}
          <form class="panel-row" onsubmit={addMember}><input class="input" type="email" name="email" placeholder="Member email" required /><SelectMenu name="role" value="editor" options={memberRoleOptions} ariaLabel="Member role" /><button class="button small" type="submit" disabled={pending}>Share</button></form>
        </div>
      </section>

      <section class="section" id="templates">
        <div class="section-heading"><div><h2>Assignment templates</h2><p>Reuse a common assignment structure.</p></div></div>
        <div class="panel">
          {#each board.templates as template (template.id)}<div class="panel-row"><Copy size={15} /><span class="panel-row-main"><strong>{template.name}</strong><span>{template.title}</span></span>{#if template.isDefault}<span class="badge">Default</span>{/if}<button class="button small" type="button" onclick={() => useTemplate(template.id)} disabled={pending}>Use</button><button class="button ghost small" type="button" onclick={() => mutate(`/api/v1/boards/${board.id}/templates/${template.id}`, { method: 'PATCH', body: JSON.stringify({ isDefault: true }) }, 'Default template changed')} disabled={pending}>Set default</button><button class="icon-button" type="button" onclick={() => (deletingTemplate = template)} aria-label={`Delete ${template.name}`} disabled={pending}><X size={14} /></button></div>{/each}
          <form class="panel-row" onsubmit={addTemplate}><input class="input" name="name" placeholder="Template name" maxlength="80" required /><input class="input" name="title" placeholder="Default assignment title" maxlength="120" required /><button class="button small" type="submit" disabled={pending}>Add template</button></form>
        </div>
      </section>

      <section class="section" id="tap-actions">
        <div class="section-heading"><div><h2>Tap actions</h2><p>Run a fixed assignment change from an NFC tag without signing in.</p></div><button class="button primary" type="button" onclick={() => { editingTap = null; tapOpen = true; }}><Plus size={14} />New Tap action</button></div>
        {#if provisionedURL}
          <div class="panel tap-provision">
            <div class="tap-provision-main">
              <div><strong>Program this tag now</strong><span>This bearer link is shown once. Rotate the action if it is lost or copied.</span></div>
              <code class="tap-url-secret">{provisionedURL}</code>
              <div class="tap-provision-actions">
                <button class="button" type="button" onclick={copyTapURL}><Copy size={14} />{copied ? 'Copied' : 'Copy link'}</button>
                {#if nfcSupported}<button class="button primary" type="button" onclick={writeTapURL} disabled={provisionedURLByteCount > standardNFCTagBytes}><Tag size={14} />Write NFC tag</button>{/if}
                <span class="tap-provision-status" aria-live="polite">{provisionStatus || tapSizeLabel(provisionedURLByteCount)}</span>
              </div>
            </div>
          </div>
        {/if}

        <div class="panel tap-action-list">
          {#if board.hasTapActions}
            {#each board.tapActions as action (action.id)}
              <div class="panel-row tap-action-row">
                <Tag size={15} />
                <span class="panel-row-main"><strong>{action.name}</strong>{#if action.hasDisplayDescription}<span>{action.displayDescription}</span>{/if}<span>{action.summary} · {action.useLimitLabel} · Expires {action.expiresAtLabel}</span></span>
                <code class="tap-token-prefix">{action.prefix}…</code>
                <span class={`badge ${action.isActive ? 'success' : 'subtle'}`}>{action.stateName}</span>
                <button class="button small" type="button" onclick={() => mutate(`/api/v1/boards/${board.id}/tap-actions/${action.id}`, { method: 'PATCH', body: JSON.stringify({ isEnabled: !action.isEnabled }) }, action.isEnabled ? 'Tap action disabled' : 'Tap action enabled')} disabled={pending}>{action.isEnabled ? 'Disable' : 'Enable'}</button>
                <PopoverMenu panelLabel={`Actions for ${action.name}`} align="right">
                  {#snippet trigger(control)}
                    <button class="icon-button" type="button" aria-haspopup="menu" aria-expanded={control.open} aria-label={`Actions for ${action.name}`} onclick={control.toggle}><DotsThree size={18} weight="bold" /></button>
                  {/snippet}
                  {#snippet children(close)}
                    <button class="menu-option" type="button" role="menuitem" disabled={pending} onclick={() => { close(); rotateTap(action.id); }}>Rotate link</button>
                    <button class="menu-option" type="button" role="menuitem" onclick={() => { close(); editingTap = action; tapOpen = true; }}>Edit action</button>
                    <div class="menu-separator"></div>
                    <button class="menu-option danger" type="button" role="menuitem" disabled={pending} onclick={() => { close(); deletingTap = action; }}><Trash2 size={14} />Delete action</button>
                  {/snippet}
                </PopoverMenu>
              </div>
            {/each}
          {:else}
            <div class="panel-row"><Tag size={15} /><span class="panel-row-main"><strong>No Tap actions yet</strong><span>Create one, then write its one-time link to an NFC tag.</span></span></div>
          {/if}
        </div>

        {#if board.hasTapExecutions}<div class="tap-history"><h3>Recent uses</h3><div class="panel">{#each board.tapExecutions as execution}<div class="panel-row"><span class="panel-row-main"><strong>{execution.actionName}</strong><span>{execution.message}</span></span><time class="tap-history-time">{execution.createdAt}</time></div>{/each}</div></div>{/if}
      </section>

      <section class="section" id="data">
        <div class="section-heading"><h2>Data</h2></div>
        <div class="panel">
          <div class="panel-row"><span class="panel-row-main"><strong>Export course</strong><span>Download assignments and course settings as JSON.</span></span><a class="button" href={`/api/v1/boards/${board.id}/export`}><Download size={14} />Export</a></div>
          <form class="panel-row" onsubmit={importBoard}><span class="panel-row-main"><strong>Import course</strong><span>Add assignments from a Flowboard JSON export.</span></span><label class="button"><Upload size={14} />Choose file<input class="sr-only" type="file" name="file" accept="application/json" required /></label><button class="button" type="submit" disabled={pending}>Import</button></form>
        </div>
      </section>

      <section class="section" id="danger">
        <div class="section-heading"><h2>Course actions</h2></div>
        <div class="panel danger-zone">
          <div class="panel-row"><span class="panel-row-main"><strong>{board.isArchived ? 'Restore course' : 'Archive course'}</strong><span>Archived courses leave the main navigation.</span></span><button class="button" type="button" onclick={() => board.isArchived ? mutate(`/api/v1/boards/${board.id}`, { method: 'PATCH', body: JSON.stringify({ isArchived: false }) }, 'Course restored') : (archiveOpen = true)} disabled={pending}><Archive size={14} />{board.isArchived ? 'Restore' : 'Archive'}</button></div>
          <div class="panel-row"><span class="panel-row-main"><strong>Duplicate course</strong><span>Copy assignments, views, fields, and templates.</span></span><button class="button" type="button" onclick={() => (duplicateOpen = true)} disabled={pending}><Copy size={14} />Duplicate</button></div>
          {#if board.isOwner && !board.isCanvasLinked}<div class="panel-row"><span class="panel-row-main"><strong>Delete course</strong><span>Permanently remove this course and its assignments.</span></span><button class="button danger" type="button" onclick={() => (deleteOpen = true)}>Delete</button></div>{:else if board.isCanvasLinked}<div class="panel-row"><span class="panel-row-main"><strong>Canvas course cannot be deleted</strong><span>Disconnect Canvas in Integrations to turn this into a local course.</span></span><a class="button small" href="/app/settings/integrations">Open integrations</a></div>{/if}
        </div>
      </section>
    </div>
  </div>
</div>

<TapActionDialog bind:open={tapOpen} {board} action={editingTap} onprovision={provisionTap} />
<ConfirmDialog open={Boolean(deletingView)} title={`Delete ${deletingView?.name ?? 'this view'}?`} description="This saved layout will be removed from the course." confirmLabel="Delete view" pendingLabel="Deleting…" oncancel={() => (deletingView = null)} onconfirm={deleteSelectedView} />
<ConfirmDialog open={Boolean(deletingTap)} title={`Delete ${deletingTap?.name ?? 'this Tap action'}?`} description="The NFC link for this action will stop working." confirmLabel="Delete action" pendingLabel="Deleting…" oncancel={() => (deletingTap = null)} onconfirm={deleteSelectedTap} />
<ConfirmDialog open={Boolean(removingMember)} title={`Remove ${removingMember?.name ?? 'this member'}?`} description="This person will lose access to the course and its assignments." confirmLabel="Remove member" pendingLabel="Removing…" oncancel={() => (removingMember = null)} onconfirm={removeSelectedMember} />
<ConfirmDialog open={Boolean(deletingTemplate)} title={`Delete ${deletingTemplate?.name ?? 'this template'}?`} description="This template will no longer be available for new assignments." confirmLabel="Delete template" pendingLabel="Deleting…" oncancel={() => (deletingTemplate = null)} onconfirm={deleteSelectedTemplate} />
<ConfirmDialog open={Boolean(deletingProperty)} title={`Delete ${deletingProperty?.name ?? 'this custom field'}?`} description="This removes the field and its values from every assignment in this course." confirmLabel="Delete field" pendingLabel="Deleting…" oncancel={() => (deletingProperty = null)} onconfirm={deleteSelectedProperty} />
<ConfirmDialog open={archiveOpen} title={`Archive ${board.name}?`} description="The course will leave the main navigation. You can restore it later." confirmLabel="Archive course" pendingLabel="Archiving…" oncancel={() => (archiveOpen = false)} onconfirm={archiveCourse} />
<ConfirmDialog open={duplicateOpen} title={`Duplicate ${board.name}?`} description="A new course will include these assignments, views, fields, and templates." confirmLabel="Duplicate course" pendingLabel="Duplicating…" tone="primary" oncancel={() => (duplicateOpen = false)} onconfirm={duplicateBoard} />

{#if editingView}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="configure-view-title" tabindex="-1" use:dialogLayer={{ close: () => (editingView = null) }}>
    <form class="dialog" onsubmit={(event) => configureView(event, editingView!.id)}>
      <div class="dialog-header"><div><h2 id="configure-view-title">Configure {editingView.name}</h2><p>Change the name, layout, grouping, filter, and sort rule.</p></div><button class="icon-button" type="button" onclick={() => (editingView = null)} aria-label="Close"><X size={16} /></button></div>
      <div class="dialog-body">
        <div class="form-grid">
          <div class="field"><label for="view-name">Name</label><input class="input" id="view-name" name="name" value={editingView.name} minlength="1" maxlength="80" required /></div>
          <div class="field"><label for="view-type">Layout</label><SelectMenu id="view-type" name="type" value={editingView.type} options={viewTypeOptions} ariaLabel="Layout" /></div>
        </div>
        <div class="field"><label for="view-group">Group assignments by</label><SelectMenu id="view-group" name="groupBy" value={editingView.groupBy} options={groupOptions} ariaLabel="Group assignments by" initialFocus /></div>
        <div class="form-grid">
          <div class="field"><label for="view-filter-field">Filter field</label><SelectMenu id="view-filter-field" name="filterField" bind:value={viewFilterField} options={filterFieldOptions} ariaLabel="Filter field" onchange={selectFilterField} /></div>
          <div class="field"><label for="view-filter-value">Filter value</label><SelectMenu id="view-filter-value" name="filterValue" bind:value={viewFilterValue} options={filterValueOptions} ariaLabel="Filter value" disabled={!viewFilterField} /></div>
          <div class="field"><label for="view-sort-field">Sort field</label><SelectMenu id="view-sort-field" name="sortField" value={editingView.sortField} options={sortFieldOptions} ariaLabel="Sort field" /></div>
          <div class="field"><label for="view-sort-direction">Sort direction</label><SelectMenu id="view-sort-direction" name="sortDirection" value={editingView.sortDirection} options={sortDirectionOptions} ariaLabel="Sort direction" /></div>
        </div>
      </div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (editingView = null)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>Save view</button></div>
    </form>
  </div>
{/if}

{#if editingProperty}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="edit-property-title" tabindex="-1" use:dialogLayer={{ close: () => (editingProperty = null) }}>
    <form class="dialog compact" onsubmit={saveProperty}>
      <div class="dialog-header"><div><h2 id="edit-property-title">Edit custom field</h2><p>Rename the field across this course.</p></div><button class="icon-button" type="button" onclick={() => (editingProperty = null)} aria-label="Close"><X size={16} /></button></div>
      <div class="dialog-body">
        <div class="field"><label for="property-name">Name</label><input class="input" id="property-name" name="name" value={editingProperty.name} minlength="1" maxlength="60" required data-dialog-focus /></div>
        <p class="field-help">The {editingProperty.typeName.toLowerCase()} field type and its options stay unchanged.</p>
      </div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (editingProperty = null)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>Save field</button></div>
    </form>
  </div>
{/if}

{#if editingWorkflowOption}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="edit-workflow-title" tabindex="-1" use:dialogLayer={{ close: () => (editingWorkflowOption = null) }}>
    <form class="dialog" onsubmit={editWorkflowOption}>
      <div class="dialog-header">
        <div><h2 id="edit-workflow-title">Edit {editingWorkflowOption.kind === 'severity' ? 'priority' : editingWorkflowOption.kind}</h2><p>The updated name and color apply everywhere in this course.</p></div>
        <button class="icon-button" type="button" onclick={() => (editingWorkflowOption = null)} aria-label="Close"><X size={16} /></button>
      </div>
      <div class="dialog-body">
        <div class="field"><label for="workflow-option-name">Name</label><input class="input" id="workflow-option-name" name="name" value={editingWorkflowOption.option.name} minlength="1" maxlength="40" required data-dialog-focus /></div>
        <div class="field"><span class="field-label">Color</span><WorkflowColorField value={editingWorkflowOption.option.customColor || editingWorkflowOption.option.colorClass.replace('workflow-', '')} /></div>
        {#if editingWorkflowOption.kind === 'status'}
          <label class="checkbox-label"><input class="checkbox-input" type="checkbox" name="isCompleted" value="true" checked={editingWorkflowOption.option.isCompleted} /><span class="checkbox-control" aria-hidden="true"><Check size={13} /></span><span>Counts as completed</span></label>
        {/if}
      </div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (editingWorkflowOption = null)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>Save {editingWorkflowOption.kind === 'severity' ? 'priority' : editingWorkflowOption.kind}</button></div>
    </form>
  </div>
{/if}

{#if deleteOpen}
  <div class="dialog-layer" role="alertdialog" aria-modal="true" aria-labelledby="delete-board-title" tabindex="-1" use:dialogLayer={{ close: () => (deleteOpen = false), closeOnBackdrop: false }}>
    <div class="dialog"><div class="dialog-header"><div><h2 id="delete-board-title">Delete {board.name}?</h2><p>This action cannot be undone.</p></div></div><div class="dialog-footer"><button class="button" type="button" onclick={() => (deleteOpen = false)} data-dialog-focus>Cancel</button><button class="button danger" type="button" onclick={deleteBoard} disabled={pending}>Delete course</button></div></div>
  </div>
{/if}
