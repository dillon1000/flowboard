<script lang="ts">
  import { goto } from '$app/navigation';
  import { api, messageFor, refreshAll } from '$lib/api';
  import type { AttachmentContext, ChecklistContext, MemberOptionContext, TaskDetailPageContext, TaskOptionContext, TaskPropertyContext, TaskPropertyOptionContext } from '$lib/types';
  import confetti from 'canvas-confetti';
  import { AlarmIcon as Alarm, ArchiveIcon as Archive, ArrowLeftIcon as ArrowLeft, ArrowSquareOutIcon as ArrowSquareOut, BellIcon as Bell, CaretDownIcon as CaretDown, ChatCircleIcon as ChatCircle, CheckCircleIcon as CheckCircle, CheckIcon as Check, DotsThreeIcon as DotsThree, DownloadIcon as Download, PaperPlaneTiltIcon as Send, PaperclipIcon as Paperclip, PencilSimpleIcon as Pencil, PlusIcon as Plus, TrashIcon as Trash2, UploadIcon as Upload, XIcon as X } from 'phosphor-svelte';
  import Avatar from '$lib/components/Avatar.svelte';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import DatePicker from '$lib/components/DatePicker.svelte';
  import TimePicker from '$lib/components/TimePicker.svelte';
  import PopoverMenu from '$lib/components/PopoverMenu.svelte';
  import SelectMenu, { type SelectMenuOption } from '$lib/components/SelectMenu.svelte';
  import { dialogLayer } from '$lib/actions/dialogLayer';
  import { onMount, type Snippet } from 'svelte';
  import { showToast } from '$lib/ui/toast';

  // The API rejects larger request bodies. Keep the browser limit equal to the
  // server limit so a user gets a useful message before an upload starts.
  const maxAttachmentBytes = 10_000_000;
  const dayMilliseconds = 86_400_000;
  // Tasks without a start date still get a window to measure pace against, so
  // the meter always answers "how much of the run-up is gone?".
  const defaultWindowDays = 7;

  let { detail, currentUserEmail, descriptionHTML } = $props<{
    detail: TaskDetailPageContext;
    currentUserEmail: string;
    descriptionHTML: string;
  }>();
  let editOpen = $state(false);
  let deleteOpen = $state(false);
  let remindersOpen = $state(false);
  let reminderDate = $state('');
  let reminderTime = $state('09:00');
  let pending = $state(false);
  let requestError = $state('');
  let selectedStatus = $state('');
  let commentBody = $state('');
  let selectedFileName = $state('No file chosen');
  let checklist = $state<ChecklistContext[]>([]);
  let pendingChecklistIDs = $state<string[]>([]);
  let uploadPending = $state(false);
  let uploadProgress = $state(0);
  let uploadError = $state('');
  let notesEditing = $state(false);
  let notesDraft = $state('');
  let editingProperty = $state('');
  let deletingAttachment = $state<AttachmentContext | null>(null);
  // The meter compares elapsed time against finished steps, so it depends on the
  // reader's clock. The server cannot know it: `now` stays null through the
  // server render and the meter fills in once the browser takes over.
  let now = $state<number | null>(null);

  const completedChecklist = $derived(
    checklist.filter((item: ChecklistContext) => item.isCompleted).length
  );
  const statusMenuOptions = $derived<SelectMenuOption[]>(
    detail.task.statusOptions.map((option: TaskOptionContext) => ({ value: option.value, label: option.name }))
  );
  const severityMenuOptions = $derived<SelectMenuOption[]>(
    detail.task.severityOptions.map((option: TaskOptionContext) => ({ value: option.value, label: option.name }))
  );
  const assigneeMenuOptions = $derived<SelectMenuOption[]>([
    { value: '', label: 'Unassigned' },
    ...detail.members.map((member: MemberOptionContext) => ({ value: member.id, label: `${member.name} · ${member.email}` }))
  ]);
  const completionOption = $derived(
    detail.task.statusOptions.find((option: TaskOptionContext) => option.isCompleted)
  );
  const currentStatus = $derived(selectedStatus || detail.task.statusValue);
  const selectedStatusOption = $derived(
    detail.task.statusOptions.find((option: TaskOptionContext) => option.value === currentStatus)
  );
  const isComplete = $derived(Boolean(selectedStatusOption?.isCompleted));
  const commentDraftKey = $derived(`flowboard-comment-draft:${detail.task.id}`);

  const dueAt = $derived.by<Date | null>(() => {
    if (!detail.task.dueInput) return null;
    const time = detail.task.hasDueTime ? detail.task.dueTimeInput : '23:59';
    const parsed = new Date(`${detail.task.dueInput}T${time}:00`);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  });

  /** The left edge of the meter: the start date, or a week before the deadline. */
  const windowStart = $derived.by<Date | null>(() => {
    if (!dueAt) return null;
    const fallback = new Date(dueAt.getTime() - defaultWindowDays * dayMilliseconds);
    if (!detail.task.startInput) return fallback;
    const started = new Date(`${detail.task.startInput}T00:00:00`);
    if (Number.isNaN(started.getTime()) || started >= dueAt) return fallback;
    return started;
  });

  const elapsedPercent = $derived.by<number>(() => {
    if (!dueAt || !windowStart || now === null) return 0;
    const span = dueAt.getTime() - windowStart.getTime();
    return clampPercent(((now - windowStart.getTime()) / span) * 100);
  });

  const donePercent = $derived(
    checklist.length ? clampPercent((completedChecklist / checklist.length) * 100) : 0
  );

  const daysUntilDue = $derived.by<number | null>(() => {
    if (!dueAt || now === null) return null;
    return Math.round((midnight(dueAt) - midnight(new Date(now))) / dayMilliseconds);
  });

  const countdownLabel = $derived.by<string>(() => {
    if (isComplete) return 'Complete';
    // The server cannot say how far away "today" is, so it says nothing.
    if (daysUntilDue === null) return '';
    if (daysUntilDue < 0) return `${plural(Math.abs(daysUntilDue), 'day')} late`;
    if (daysUntilDue === 0) return 'Due today';
    if (daysUntilDue === 1) return 'Due tomorrow';
    return `Due in ${plural(daysUntilDue, 'day')}`;
  });

  /** Drives the meter's colour and its written verdict. Never colour alone. */
  const paceState = $derived.by<'complete' | 'late' | 'behind' | 'steady'>(() => {
    if (isComplete) return 'complete';
    if (daysUntilDue !== null && daysUntilDue < 0) return 'late';
    if (checklist.length && donePercent + 10 < elapsedPercent) return 'behind';
    return 'steady';
  });

  const paceSummary = $derived.by<string>(() => {
    if (!dueAt) return '';
    if (paceState === 'complete') return 'Finished';
    if (now === null) return '';
    if (paceState === 'late') return 'Past the deadline';
    if (!checklist.length) return 'Add steps to track your pace';
    if (paceState === 'behind') return 'Behind the clock';
    return 'On pace';
  });

  const unsetDetails = $derived<{ key: string; label: string }[]>([
    ...(detail.task.hasAssignee ? [] : [{ key: 'assigneeID', label: 'Assignee' }]),
    ...(detail.task.hasGrade || detail.task.hasPointsPossible || detail.task.isCanvasLinked ? [] : [{ key: 'grade', label: 'Grade' }]),
    ...(detail.task.startInput ? [] : [{ key: 'startAt', label: 'Start date' }]),
    ...detail.properties
      .filter((property: TaskPropertyContext) => !property.value)
      .map((property: TaskPropertyContext) => ({ key: property.id, label: property.name }))
  ]);

  $effect(() => {
    checklist = detail.checklist.map((item: ChecklistContext) => ({ ...item }));
  });

  $effect(() => {
    selectedStatus = detail.task.statusValue;
  });

  onMount(() => {
    commentBody = sessionStorage.getItem(commentDraftKey) ?? '';
    now = Date.now();
  });

  function clampPercent(value: number): number {
    return Math.min(100, Math.max(0, value));
  }

  function midnight(date: Date): number {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  }

  function plural(count: number, noun: string): string {
    return `${count} ${noun}${count === 1 ? '' : 's'}`;
  }

  function apiDate(value: FormDataEntryValue | null): string | null {
    const date = String(value ?? '');
    return date ? `${date}T00:00:00Z` : null;
  }

  function estimateMinutes(value: FormDataEntryValue | null): number | null {
    const minutes = Number(value);
    return Number.isInteger(minutes) && minutes > 0 ? minutes : null;
  }

  function score(value: FormDataEntryValue | null): number | null {
    const raw = String(value ?? '').trim();
    if (!raw) return null;
    const number = Number(raw);
    return Number.isFinite(number) && number >= 0 ? number : null;
  }

  async function mutate(path: string, init: RequestInit, successMessage = ''): Promise<boolean> {
    pending = true;
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
      pending = false;
    }
  }

  async function changeStatus(status: string): Promise<void> {
    const didComplete = detail.task.statusOptions.some(
      (option: TaskOptionContext) => option.value === status && option.isCompleted
    );
    const priorStatus = currentStatus;
    selectedStatus = status;
    pending = true;
    requestError = '';
    try {
      await api(`/api/v1/tasks/${detail.task.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ status })
      });
      if (didComplete) confetti({ particleCount: 80, spread: 70, origin: { y: 0.7 } });
      showToast('Assignment status updated');
      await refreshAll();
    } catch (cause) {
      selectedStatus = priorStatus;
      requestError = messageFor(cause);
    } finally {
      pending = false;
    }
  }

  async function toggleFollow(): Promise<void> {
    await mutate(`/api/v1/tasks/${detail.task.id}/followers/me`, {
      method: detail.isFollowing ? 'DELETE' : 'POST'
    }, detail.isFollowing ? 'Assignment unfollowed' : 'Assignment followed');
  }

  function openReminders(): void {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    reminderDate = futureDateInput(detail.task.dueInput) || localDateInput(tomorrow);
    reminderTime = detail.task.hasDueTime ? detail.task.dueTimeInput : '09:00';
    requestError = '';
    remindersOpen = true;
  }

  function futureDateInput(value: string): string {
    if (!value) return '';
    const endOfDay = new Date(`${value}T23:59:59`);
    return endOfDay > new Date() ? value : '';
  }

  function localDateInput(date: Date): string {
    const offsetDate = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
    return offsetDate.toISOString().slice(0, 10);
  }

  async function addReminder(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const date = String(data.get('reminderDate') ?? '');
    const time = String(data.get('reminderTime') ?? '');
    const remindAt = new Date(`${date}T${time}:00`);
    if (!date || !time || Number.isNaN(remindAt.getTime())) {
      requestError = 'Choose a reminder date and time.';
      return;
    }
    await mutate(`/api/v1/tasks/${detail.task.id}/reminders`, {
      method: 'POST',
      body: JSON.stringify({
        remindAt: remindAt.toISOString(),
        timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone
      })
    }, 'Reminder added');
  }

  async function deleteReminder(reminderID: string): Promise<void> {
    await mutate(`/api/v1/tasks/${detail.task.id}/reminders/${reminderID}`, {
      method: 'DELETE'
    }, 'Reminder removed');
  }

  async function saveTask(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const assigneeID = String(data.get('assigneeID') ?? '');
    const body: Record<string, unknown> = {
      status: String(data.get('status') ?? ''),
      priority: String(data.get('priority') ?? ''),
      assigneeID: assigneeID || null,
      startAt: apiDate(data.get('startAt')),
      estimatedMinutes: estimateMinutes(data.get('estimatedMinutes')),
      labels: String(data.get('labels') ?? '').split(',').map((label) => label.trim()).filter(Boolean).slice(0, 6)
    };
    if (!detail.task.isCanvasLinked) Object.assign(body, {
      title: String(data.get('title') ?? ''),
      description: String(data.get('description') ?? '') || null,
      dueAt: apiDate(data.get('dueAt')),
      dueTime: data.get('dueAt') ? String(data.get('dueTime') ?? '') || null : null,
      gradeEarned: score(data.get('gradeEarned')),
      gradePossible: score(data.get('gradePossible'))
    });
    const saved = await mutate(`/api/v1/tasks/${detail.task.id}`, {
      method: 'PATCH',
      body: JSON.stringify(body)
    }, 'Assignment updated');
    if (saved) editOpen = false;
  }

  function editNotes(): void {
    notesDraft = detail.task.description;
    notesEditing = true;
  }

  async function saveNotes(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const description = String(new FormData(event.currentTarget as HTMLFormElement).get('description') ?? '').trim();
    if (await mutate(`/api/v1/tasks/${detail.task.id}`, { method: 'PATCH', body: JSON.stringify({ description: description || null }) }, 'Notes saved')) {
      notesEditing = false;
    }
  }

  async function saveInlineProperty(event: SubmitEvent, property: string): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    let body: Record<string, string | number | null> = {};
    switch (property) {
      case 'priority':
        body = { priority: String(data.get('priority') ?? '') };
        break;
      case 'estimatedMinutes':
        body = { estimatedMinutes: estimateMinutes(data.get('estimatedMinutes')) };
        break;
      case 'grade':
        body = { gradeEarned: score(data.get('gradeEarned')), gradePossible: score(data.get('gradePossible')) };
        break;
      case 'assigneeID': {
        const assigneeID = String(data.get('assigneeID') ?? '');
        body = { assigneeID: assigneeID || null };
        break;
      }
      case 'startAt':
        body = { startAt: apiDate(data.get('startAt')) };
        break;
      case 'dueAt': {
        const dueDate = apiDate(data.get('dueAt'));
        body = { dueAt: dueDate, dueTime: dueDate ? String(data.get('dueTime') ?? '') || null : null };
        break;
      }
    }
    if (await mutate(`/api/v1/tasks/${detail.task.id}`, { method: 'PATCH', body: JSON.stringify(body) }, 'Property updated')) {
      editingProperty = '';
    }
  }

  /** Saves one custom field while preserving every other field in the task. */
  async function saveCustomProperty(event: SubmitEvent, property: TaskPropertyContext): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const properties: Record<string, string> = Object.fromEntries(
      detail.properties.filter((item: TaskPropertyContext) => item.inputValue).map((item: TaskPropertyContext) => [item.id, item.inputValue])
    );
    let value = '';
    if (property.usesMultiSelect) {
      value = JSON.stringify(property.options.filter((option) => data.has(`property-${property.id}-${option.id}`)).map((option) => option.id));
    } else if (property.usesCheckbox) {
      value = data.has(`property-${property.id}`) ? 'true' : 'false';
    } else {
      value = String(data.get(`property-${property.id}`) ?? '').trim();
    }
    if (value) properties[property.id] = value;
    else delete properties[property.id];
    if (await mutate(`/api/v1/tasks/${detail.task.id}`, { method: 'PATCH', body: JSON.stringify({ properties }) }, 'Property updated')) {
      editingProperty = '';
    }
  }

  async function toggleChecklist(itemID: string, isCompleted: boolean): Promise<void> {
    if (pendingChecklistIDs.includes(itemID)) return;
    const item = checklist.find((candidate) => candidate.id === itemID);
    if (!item) return;

    item.isCompleted = !isCompleted;
    pendingChecklistIDs = [...pendingChecklistIDs, itemID];
    requestError = '';
    try {
      await api(`/api/v1/tasks/${detail.task.id}/checklist/${itemID}`, {
        method: 'PATCH',
        body: JSON.stringify({ isCompleted: !isCompleted })
      });
      await refreshAll();
      showToast(item.isCompleted ? 'Step completed' : 'Step reopened');
    } catch (cause) {
      item.isCompleted = isCompleted;
      requestError = messageFor(cause);
    } finally {
      pendingChecklistIDs = pendingChecklistIDs.filter((id) => id !== itemID);
    }
  }

  async function addChecklist(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const title = String(new FormData(form).get('title') ?? '');
    if (await mutate(`/api/v1/tasks/${detail.task.id}/checklist`, { method: 'POST', body: JSON.stringify({ title }) }, 'Step added')) form.reset();
  }

  async function deleteChecklist(itemID: string): Promise<void> {
    await mutate(`/api/v1/tasks/${detail.task.id}/checklist/${itemID}`, { method: 'DELETE' }, 'Step removed');
  }

  async function addComment(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    if (await mutate(`/api/v1/tasks/${detail.task.id}/comments`, { method: 'POST', body: JSON.stringify({ body: commentBody }) }, 'Comment added')) {
      commentBody = '';
      sessionStorage.removeItem(commentDraftKey);
    }
  }

  function updateCommentDraft(event: Event): void {
    commentBody = (event.currentTarget as HTMLTextAreaElement).value;
    if (commentBody) sessionStorage.setItem(commentDraftKey, commentBody);
    else sessionStorage.removeItem(commentDraftKey);
  }

  function submitCommentShortcut(event: KeyboardEvent): void {
    if (event.key !== 'Enter' || !(event.metaKey || event.ctrlKey)) return;
    event.preventDefault();
    const textarea = event.currentTarget as HTMLTextAreaElement;
    if (!pending && commentBody.trim()) textarea.form?.requestSubmit();
  }

  async function uploadAttachment(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const input = form.elements.namedItem('file');
    const file = input instanceof HTMLInputElement ? input.files?.[0] : null;
    if (!file) return;
    if (file.size > maxAttachmentBytes) {
      uploadError = 'Choose a file that is 10 MB or smaller.';
      return;
    }

    uploadPending = true;
    uploadProgress = 0;
    uploadError = '';
    try {
      await uploadForm(`/api/v1/tasks/${detail.task.id}/attachments`, new FormData(form));
      form.reset();
      selectedFileName = 'No file chosen';
      await refreshAll();
      showToast('File uploaded');
    } catch (cause) {
      uploadError = messageFor(cause);
    } finally {
      uploadPending = false;
    }
  }

  function selectAttachment(event: Event): void {
    const file = (event.currentTarget as HTMLInputElement).files?.[0];
    selectedFileName = file?.name ?? 'No file chosen';
    uploadError = file && file.size > maxAttachmentBytes ? 'Choose a file that is 10 MB or smaller.' : '';
  }

  function deleteAttachment(): Promise<boolean> {
    if (!deletingAttachment) return Promise.resolve(false);
    return mutate(`/api/v1/attachments/${deletingAttachment.id}`, { method: 'DELETE' }, 'File deleted');
  }

  /** Uploads one attachment and reports browser upload progress. */
  function uploadForm(path: string, data: FormData): Promise<void> {
    return new Promise((resolve, reject) => {
      const request = new XMLHttpRequest();
      request.open('POST', path);
      request.responseType = 'json';
      request.upload.addEventListener('progress', (event) => {
        if (event.lengthComputable) uploadProgress = Math.min(100, Math.round((event.loaded / event.total) * 100));
      });
      request.addEventListener('load', () => {
        if (request.status >= 200 && request.status < 300) {
          uploadProgress = 100;
          resolve();
          return;
        }
        const payload: unknown = request.response;
        const reason = payload && typeof payload === 'object' && 'reason' in payload
          ? (payload as { reason?: unknown }).reason
          : null;
        reject(new Error(typeof reason === 'string' ? reason : request.statusText || 'The upload failed.'));
      });
      request.addEventListener('error', () => reject(new Error('The upload could not reach the server.')));
      request.send(data);
    });
  }

  async function archiveTask(): Promise<void> {
    const wasArchived = detail.task.isArchived;
    if (await mutate(`/api/v1/tasks/${detail.task.id}`, { method: 'PATCH', body: JSON.stringify({ isArchived: !wasArchived }) }, wasArchived ? 'Assignment restored' : 'Assignment archived') && !wasArchived) {
      await goto(detail.boardHref);
    }
  }

  async function deleteTask(): Promise<void> {
    pending = true;
    requestError = '';
    try {
      await api(`/api/v1/tasks/${detail.task.id}`, { method: 'DELETE' });
      showToast('Assignment deleted');
      await goto(detail.boardHref, { invalidateAll: true });
    } catch (cause) {
      requestError = messageFor(cause);
      pending = false;
    }
  }
</script>

<!-- One detail row: only rendered when the field carries a value or is being
     edited. Empty fields collect at the foot of the list as "add" buttons. -->
{#snippet detailRow(key: string, label: string, isSet: boolean, value: Snippet, editor: Snippet, editable = true)}
  {#if editingProperty === key}
    <div class="detail-row editing">
      <dt>{label}</dt>
      <dd>{@render editor()}</dd>
    </div>
  {:else if isSet}
    <div class="detail-row">
      <dt>{label}</dt>
      <dd>
        {@render value()}
        {#if detail.canEdit && editable}
          <button class="detail-edit" type="button" onclick={() => (editingProperty = key)} aria-label={`Edit ${label.toLowerCase()}`}><Pencil size={13} /></button>
        {/if}
      </dd>
    </div>
  {/if}
{/snippet}

{#snippet inlineActions()}
  <div class="property-inline-actions">
    <button class="button small" type="button" onclick={() => (editingProperty = '')}>Cancel</button>
    <button class="button primary small" type="submit" disabled={pending}>Save</button>
  </div>
{/snippet}

<div class="page task-detail-page">
  <header class="task-headline">
    <a class="page-eyebrow" href={detail.boardHref}><ArrowLeft size={14} />{detail.boardName}</a>
    <div class="task-headline-row">
      <h1>{detail.task.title}</h1>
      <div class="task-headline-actions">
        {#if detail.canEdit}
          <PopoverMenu panelLabel="Change assignment status" panelRole="listbox" align="right">
            {#snippet trigger(control)}
              <button class="task-status-trigger" type="button" disabled={pending} aria-haspopup="listbox" aria-expanded={control.open} onclick={control.toggle}>
                <span class={`badge status ${selectedStatusOption?.colorClass ?? detail.task.statusColorClass}`} style={selectedStatusOption?.colorStyle ?? detail.task.statusColorStyle}>{selectedStatusOption?.name ?? detail.task.statusName}</span>
                <CaretDown size={13} />
              </button>
            {/snippet}
            {#snippet children(close)}
              {#each detail.task.statusOptions as option (option.value)}
                <button
                  class="menu-option"
                  type="button"
                  role="option"
                  aria-selected={option.value === currentStatus}
                  onclick={() => { close(); if (option.value !== currentStatus) changeStatus(option.value); }}
                >
                  <span class={`badge status ${option.colorClass}`} style={option.colorStyle}>{option.name}</span>
                </button>
              {/each}
            {/snippet}
          </PopoverMenu>
        {:else}
          <span class={`badge status ${detail.task.statusColorClass}`} style={detail.task.statusColorStyle}>{detail.task.statusName}</span>
        {/if}

        {#if detail.canEdit && completionOption && !isComplete}
          <button class="button primary" type="button" onclick={() => changeStatus(completionOption.value)} disabled={pending}><CheckCircle size={15} />Mark complete</button>
        {/if}

        <PopoverMenu panelLabel="More assignment actions" align="right">
          {#snippet trigger(control)}
            <button class="icon-button task-more" type="button" aria-haspopup="menu" aria-expanded={control.open} aria-label="More assignment actions" onclick={control.toggle}>
              <DotsThree size={18} weight="bold" />
            </button>
          {/snippet}
          {#snippet children(close)}
            <button class="menu-option" type="button" role="menuitem" onclick={() => { close(); openReminders(); }}>
              <Alarm size={15} />Reminders{#if detail.reminders.length}<span class="badge count tabular">{detail.reminders.length}</span>{/if}
            </button>
            <button class="menu-option" type="button" role="menuitem" disabled={pending} onclick={() => { close(); toggleFollow(); }}>
              <Bell size={15} />{detail.isFollowing ? 'Unfollow' : 'Follow'}<span class="badge count tabular">{detail.followerCount}</span>
            </button>
            {#if detail.canEdit}
              <button class="menu-option" type="button" role="menuitem" onclick={() => { close(); editOpen = true; }}>
                <Pencil size={15} />{detail.task.isCanvasLinked ? 'Edit planning' : 'Edit assignment'}
              </button>
              <div class="menu-separator"></div>
              <button class="menu-option" type="button" role="menuitem" disabled={pending} onclick={() => { close(); archiveTask(); }}>
                <Archive size={15} />{detail.task.isArchived ? 'Restore assignment' : 'Archive assignment'}
              </button>
              {#if !detail.task.isCanvasLinked}<button class="menu-option danger" type="button" role="menuitem" onclick={() => { close(); deleteOpen = true; }}><Trash2 size={15} />Delete assignment</button>{/if}
            {/if}
          {/snippet}
        </PopoverMenu>
      </div>
    </div>
  </header>

  {#if requestError && !remindersOpen}<p class="error-message" role="alert">{requestError}</p>{/if}

  {#if detail.task.isCanvasLinked}
    <section class="canvas-task-source" aria-labelledby="canvas-task-source-title">
      <div><span class="badge subtle" id="canvas-task-source-title">Synced from Canvas</span><a href={detail.task.canvasURL} target="_blank" rel="noopener">Open assignment <ArrowSquareOut size={13} /></a></div>
      <dl>
        <div><dt>Submission</dt><dd>{detail.task.canvasSubmissionState}{#if detail.task.canvasRedoRequested} · Redo requested{/if}</dd></div>
        <div><dt>Submitted</dt><dd>{detail.task.canvasSubmittedAtDisplay}</dd></div>
        <div><dt>Late</dt><dd>{detail.task.canvasLate ? 'Yes' : 'No'}</dd></div>
        <div><dt>Missing</dt><dd>{detail.task.canvasMissing ? 'Yes' : 'No'}</dd></div>
        <div><dt>Excused</dt><dd>{detail.task.canvasExcused ? 'Yes' : 'No'}</dd></div>
        <div><dt>Last sync</dt><dd>{detail.task.canvasLastSyncDisplay}</dd></div>
      </dl>
    </section>
  {/if}

  <!-- The pace meter is the page's thesis: elapsed run-up behind, finished
       steps in front, so being behind is a shape rather than a number. -->
  <section class="pace" data-state={paceState} aria-labelledby="pace-title">
    <h2 class="sr-only" id="pace-title">Deadline pace</h2>
    {#if dueAt}
      <div class="pace-ends">
        <span class="pace-start">{detail.task.startInput ? `Started ${detail.task.startDisplay}` : 'Final week'}</span>
        {#if detail.canEdit && !detail.task.isCanvasLinked}
          <button class="pace-due" type="button" onclick={() => (editingProperty = 'dueAt')}>
            <span class="pace-due-label">Due</span>
            <strong>{detail.task.dueDisplay}{#if detail.task.hasDueTime} · {detail.task.dueTimeDisplay}{/if}</strong>
            <Pencil size={12} />
          </button>
        {:else}
          <span class="pace-due"><span class="pace-due-label">Due</span><strong>{detail.task.dueDisplay}</strong></span>
        {/if}
      </div>

      <div class="pace-track" class:ready={now !== null} aria-hidden="true">
        <div class="pace-elapsed" style={`width: ${elapsedPercent}%`}></div>
        <div class="pace-done" style={`width: ${donePercent}%`}></div>
        <div class="pace-today" style={`left: ${elapsedPercent}%`}></div>
      </div>
      {#if now !== null}
        <p class="sr-only">
          {Math.round(elapsedPercent)}% of the time before this deadline has passed{#if checklist.length}, and {completedChecklist} of {checklist.length} steps are done{/if}.
        </p>
      {/if}

      <div class="pace-caption">
        <span class="pace-verdict">{paceSummary}</span>
        <span class="pace-facts">
          {#if checklist.length}<span class="tabular">{completedChecklist}/{checklist.length} steps</span>{/if}
          {#if detail.canEdit}
            <button class="pace-estimate" type="button" onclick={() => (editingProperty = 'estimatedMinutes')}>
              {detail.task.hasEstimate ? detail.task.estimatedDisplay : 'Add estimate'}
            </button>
          {:else if detail.task.hasEstimate}
            <span>{detail.task.estimatedDisplay}</span>
          {/if}
          <span class="pace-countdown tabular">{countdownLabel}</span>
        </span>
      </div>
    {:else}
      <div class="pace-undated">
        <p><strong>No due date yet.</strong> Without one this assignment stays out of your week and semester plans.</p>
        {#if detail.canEdit && !detail.task.isCanvasLinked}<button class="button" type="button" onclick={() => (editingProperty = 'dueAt')}>Set a due date</button>{/if}
      </div>
    {/if}

    {#if editingProperty === 'dueAt'}
      <form class="pace-editor" onsubmit={(event) => saveInlineProperty(event, 'dueAt')}>
        <div class="field"><label for="inline-due">Due date</label><DatePicker id="inline-due" name="dueAt" value={detail.task.dueInput} label="Due date" initialFocus /></div>
        <div class="field"><label for="inline-due-time">Due time</label><TimePicker id="inline-due-time" name="dueTime" value={detail.task.dueTimeInput} label="Due time" /></div>
        {@render inlineActions()}
      </form>
    {:else if editingProperty === 'estimatedMinutes'}
      <form class="pace-editor" onsubmit={(event) => saveInlineProperty(event, 'estimatedMinutes')}>
        <div class="field"><label for="inline-estimate">Time estimate</label><input class="input" id="inline-estimate" name="estimatedMinutes" type="number" min="5" max="1440" step="5" inputmode="numeric" value={detail.task.hasEstimate ? detail.task.estimatedMinutes : ''} placeholder="Minutes, e.g. 45" /></div>
        {@render inlineActions()}
      </form>
    {/if}
  </section>

  <div class="split-layout">
    <div class="task-main">
      <section class="task-section" aria-labelledby="steps-title">
        <div class="task-section-head">
          <h2 id="steps-title">Steps</h2>
          {#if checklist.length}
            <span class="checklist-progress">
              <span class="tabular">{completedChecklist} of {checklist.length}</span>
              <progress class="progress" value={completedChecklist} max={checklist.length}></progress>
            </span>
          {/if}
        </div>

        {#if checklist.length}
          <div class="checklist">
            {#each checklist as item (item.id)}
              <div class:completed={item.isCompleted} class="checklist-item" data-pending={pendingChecklistIDs.includes(item.id) ? 'true' : undefined}>
                <button class:checked={item.isCompleted} class="custom-checkbox" type="button" onclick={() => toggleChecklist(item.id, item.isCompleted)} disabled={!detail.canEdit || pendingChecklistIDs.includes(item.id)} aria-label={`Toggle “${item.title}”`}><Check size={13} /></button>
                <span>{item.title}</span>
                {#if detail.canEdit}<button class="icon-button checklist-delete" type="button" onclick={() => deleteChecklist(item.id)} disabled={pendingChecklistIDs.includes(item.id)} aria-label={`Remove “${item.title}”`} title="Remove step"><Trash2 size={14} /></button>{/if}
              </div>
            {/each}
          </div>
          {#if detail.canEdit && completedChecklist === checklist.length && completionOption && !isComplete}
            <div class="checklist-complete-hint" role="status">
              <CheckCircle size={18} />
              <span><strong>Every step is done.</strong> Mark the assignment complete?</span>
              <button class="button primary small" type="button" onclick={() => changeStatus(completionOption.value)} disabled={pending}>Mark complete</button>
            </div>
          {/if}
        {:else}
          <p class="section-empty">Break this into the pieces you will actually sit down and do.</p>
        {/if}

        {#if detail.canEdit}
          <form class="checklist-add" onsubmit={addChecklist}>
            <input class="input" name="title" placeholder="Add a step" maxlength="200" required aria-label="New checklist item" />
            <button class="button" type="submit" disabled={pending}><Plus size={14} />Add</button>
          </form>
        {/if}
      </section>

      <section class="task-section" aria-labelledby="notes-title">
        <div class="task-section-head">
          <h2 id="notes-title">Notes</h2>
          {#if detail.canEdit && !detail.task.isCanvasLinked && !notesEditing}
            <button class="button ghost small" type="button" onclick={editNotes}>{detail.task.hasDescription ? 'Edit' : 'Add notes'}</button>
          {/if}
        </div>
        {#if notesEditing}
          <form class="notes-editor" onsubmit={saveNotes}>
            <label class="sr-only" for="task-notes">Assignment notes</label>
            <textarea class="textarea" id="task-notes" name="description" bind:value={notesDraft} maxlength="5000" placeholder="Instructions, links, submission requirements…"></textarea>
            <div class="notes-editor-footer">
              <span>Markdown is supported.</span>
              <div>
                <button class="button small" type="button" onclick={() => (notesEditing = false)}>Cancel</button>
                <button class="button primary small" type="submit" disabled={pending}>Save notes</button>
              </div>
            </div>
          </form>
        {:else if detail.task.hasDescription}
          <div class="task-description markdown">{@html descriptionHTML}</div>
        {:else}
          <p class="section-empty">Instructions, links, and submission requirements.</p>
        {/if}
      </section>

      <section class="task-section" aria-labelledby="files-title">
        <div class="task-section-head">
          <h2 id="files-title">Files</h2>
          {#if detail.hasAttachments}<span class="section-count tabular">{detail.attachments.length}</span>{/if}
        </div>
        {#if detail.hasAttachments}
          <div class="attachment-grid">
            {#each detail.attachments as attachment (attachment.id)}
              <div class="attachment">
                {#if attachment.isImage}<a class="attachment-media attachment-image" href={attachment.previewHref} target="_blank" rel="noopener"><img src={attachment.previewHref} alt="" loading="lazy" /></a>{:else if attachment.isAudio}<div class="attachment-media attachment-audio"><audio controls preload="metadata" src={attachment.previewHref} aria-label={`Preview ${attachment.fileName}`}></audio></div>{:else if attachment.isVideo}<div class="attachment-media attachment-video"><!-- svelte-ignore a11y_media_has_caption --><video controls preload="metadata" src={attachment.previewHref} aria-label={`Preview ${attachment.fileName}`} playsinline></video></div>{:else}<span class="attachment-file-icon"><Paperclip size={20} /></span>{/if}
                <div class="attachment-details"><span class="attachment-copy"><strong title={attachment.fileName}>{attachment.fileName}</strong><small>{attachment.sizeDisplay}</small></span><span class="attachment-actions"><a class="button ghost small" href={attachment.href}><Download size={13} />Download</a>{#if detail.canEdit}<button class="button ghost small attachment-delete" type="button" onclick={() => (deletingAttachment = attachment)}><Trash2 size={13} />Delete</button>{/if}</span></div>
              </div>
            {/each}
          </div>
        {:else}
          <p class="section-empty">Rubrics, readings, and your final upload stay with the assignment.</p>
        {/if}
        {#if detail.canEdit}
          <form class="attachment-upload-form" onsubmit={uploadAttachment}>
            <span class="file-field">
              <label class="button small" aria-disabled={uploadPending}><Upload size={13} />Choose file<input class="sr-only" type="file" name="file" required disabled={uploadPending} onchange={selectAttachment} /></label>
              <span class="file-name">{selectedFileName}</span>
              <button class="button small primary" type="submit" disabled={uploadPending || !!uploadError}>{uploadPending ? 'Uploading…' : 'Upload'}</button>
            </span>
            {#if uploadPending}<div class="upload-progress" aria-live="polite"><div class="upload-progress-meta"><span>Uploading file</span><span class="tabular">{uploadProgress}%</span></div><progress class="upload-progress-bar" max="100" value={uploadProgress}></progress></div>{/if}
            {#if uploadError}<p class="upload-error" role="alert">{uploadError}</p>{/if}
          </form>
        {/if}
      </section>

      <section class="task-section" aria-labelledby="comments-title">
        <div class="task-section-head">
          <h2 id="comments-title">Comments</h2>
          {#if detail.hasComments}<span class="section-count tabular">{detail.comments.length}</span>{/if}
        </div>

        <div class="comment-thread">
          {#if !detail.hasComments}
            <div class="comment-empty"><span><ChatCircle size={18} /></span><div><strong>No comments yet</strong><small>Leave a question or the context you will have forgotten by next week.</small></div></div>
          {/if}
          {#each detail.comments as comment (comment.id)}
            <div class="comment"><Avatar avatar={comment.authorAvatar} /><div><div class="comment-meta"><strong>{comment.authorName}</strong><span>{comment.createdDisplay}</span></div><div class="comment-body">{comment.body}</div>{#if comment.canDelete}<div class="comment-actions"><button class="button ghost small" type="button" onclick={() => mutate(`/api/v1/tasks/${detail.task.id}/comments/${comment.id}`, { method: 'DELETE' }, 'Comment deleted')}>Delete</button></div>{/if}</div></div>
          {/each}
        </div>

        {#if detail.canComment}
          <form class="comment-composer" onsubmit={addComment}>
            <div class="comment-input-shell">
              <label class="sr-only" for="new-comment">Add a comment</label>
              <textarea class="textarea" id="new-comment" value={commentBody} oninput={updateCommentDraft} onkeydown={submitCommentShortcut} maxlength="4000" rows="2" placeholder="Leave a comment…" required></textarea>
              <div class="comment-composer-footer">
                <span class="comment-draft-meta"><span class="tabular">{commentBody.length ? `${commentBody.length} / 4000` : 'Draft saves automatically'}</span><kbd>⌘/Ctrl Enter</kbd></span>
                <button class="button primary small" type="submit" disabled={pending || !commentBody.trim()}><Send size={14} />Send</button>
              </div>
            </div>
          </form>
        {/if}
      </section>
    </div>

    <aside class="task-sidebar" aria-labelledby="details-title">
      <div class="task-section-head">
        <h2 id="details-title">Details</h2>
      </div>

      <dl class="detail-list">
        {#snippet severityValue()}
          <span class={`badge ${detail.task.priorityColorClass}`} style={detail.task.priorityColorStyle}>{detail.task.priorityName}</span>
        {/snippet}
        {#snippet severityEditor()}
          <form class="property-inline-form" onsubmit={(event) => saveInlineProperty(event, 'priority')}>
            <SelectMenu id="inline-priority" name="priority" value={detail.task.priorityValue} options={severityMenuOptions} ariaLabel="Priority" />
            {@render inlineActions()}
          </form>
        {/snippet}
        {@render detailRow('priority', 'Priority', true, severityValue, severityEditor)}

        {#snippet assigneeValue()}<span>{detail.task.assigneeName}</span>{/snippet}
        {#snippet assigneeEditor()}
          <form class="property-inline-form" onsubmit={(event) => saveInlineProperty(event, 'assigneeID')}>
            <SelectMenu id="inline-assignee" name="assigneeID" value={detail.task.assigneeID} options={assigneeMenuOptions} ariaLabel="Assignee" />
            {@render inlineActions()}
          </form>
        {/snippet}
        {@render detailRow('assigneeID', 'Assignee', detail.task.hasAssignee, assigneeValue, assigneeEditor)}

        {#snippet gradeValue()}<span>{detail.task.gradeDisplay}</span>{/snippet}
        {#snippet gradeEditor()}
          <form class="property-inline-form" onsubmit={(event) => saveInlineProperty(event, 'grade')}>
            <div class="property-score-inputs">
              <input class="input" name="gradeEarned" type="number" min="0" max="100000" step="0.1" value={detail.task.hasGrade ? detail.task.gradeEarned : ''} aria-label="Points earned" placeholder="Earned" />
              <span>/</span>
              <input class="input" name="gradePossible" type="number" min="0.1" max="100000" step="0.1" value={detail.task.hasGrade ? detail.task.gradePossible : ''} aria-label="Points possible" placeholder="Possible" />
            </div>
            {@render inlineActions()}
          </form>
        {/snippet}
        {@render detailRow('grade', 'Grade', detail.task.hasGrade || detail.task.hasPointsPossible, gradeValue, gradeEditor, !detail.task.isCanvasLinked)}

        {#snippet startValue()}<span>{detail.task.startDisplay}</span>{/snippet}
        {#snippet startEditor()}
          <form class="property-inline-form" onsubmit={(event) => saveInlineProperty(event, 'startAt')}>
            <DatePicker id="inline-start" name="startAt" value={detail.task.startInput} label="Start date" />
            {@render inlineActions()}
          </form>
        {/snippet}
        {@render detailRow('startAt', 'Start', Boolean(detail.task.startInput), startValue, startEditor)}

        {#if detail.task.hasLabels}
          <div class="detail-row">
            <dt>Labels</dt>
            <dd class="detail-labels">{#each detail.task.labels as label}<span class="badge subtle">{label}</span>{/each}</dd>
          </div>
        {/if}

        {#each detail.properties as property (property.id)}
          {#snippet propertyValue()}<span>{property.value}</span>{/snippet}
          {#snippet propertyEditor()}
            <form class="property-inline-form" onsubmit={(event) => saveCustomProperty(event, property)}>
              {#if property.usesInput}
                {#if property.inputType === 'date'}
                  <DatePicker id={`inline-property-${property.id}`} name={`property-${property.id}`} value={property.inputValue} label={property.name} />
                {:else}
                  <input class="input" type={property.inputType} step="any" id={`inline-property-${property.id}`} name={`property-${property.id}`} value={property.inputValue} />
                {/if}
              {:else if property.usesSelect}
                <SelectMenu id={`inline-property-${property.id}`} name={`property-${property.id}`} value={property.inputValue} ariaLabel={property.name} options={[{ value: '', label: 'No value' }, ...property.options.map((option: TaskPropertyOptionContext) => ({ value: option.id, label: option.name }))]} />
              {:else if property.usesMultiSelect}
                <div class="property-options" id={`inline-property-${property.id}`}>{#each property.options as option}<label class="property-option"><input type="checkbox" name={`property-${property.id}-${option.id}`} checked={option.isSelected} /><span>{option.name}</span></label>{/each}</div>
              {:else if property.usesCheckbox}
                <label class="property-boolean"><input type="checkbox" name={`property-${property.id}`} value="true" checked={property.isChecked} /><span>Checked</span></label>
              {/if}
              {@render inlineActions()}
            </form>
          {/snippet}
          {@render detailRow(property.id, property.name, Boolean(property.value), propertyValue, propertyEditor)}
        {/each}
      </dl>

      {#if detail.canEdit && unsetDetails.length}
        <div class="detail-add">
          {#each unsetDetails as field (field.key)}
            <button class="detail-add-button" type="button" onclick={() => (editingProperty = field.key)}><Plus size={12} />{field.label}</button>
          {/each}
        </div>
      {/if}

      <p class="detail-footnote">Added by {detail.creatorName}</p>
    </aside>
  </div>
</div>

{#if editOpen}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="edit-task-title" tabindex="-1" use:dialogLayer={{ close: () => (editOpen = false) }}>
    <form class="dialog wide" onsubmit={saveTask}>
      <div class="dialog-header"><div><h2 id="edit-task-title">{detail.task.isCanvasLinked ? 'Edit planning' : 'Edit assignment'}</h2><p>{detail.task.isCanvasLinked ? 'Canvas manages the academic fields for this assignment.' : 'Update the assignment and its schedule.'}</p></div><button class="icon-button" type="button" onclick={() => (editOpen = false)} aria-label="Close"><X size={16} /></button></div>
      <div class="dialog-body"><div class="form-grid">
        {#if !detail.task.isCanvasLinked}<div class="field wide"><label for="edit-title">Title</label><input class="input" id="edit-title" name="title" value={detail.task.title} maxlength="120" required data-dialog-focus /></div><div class="field wide"><label for="edit-description">Description</label><textarea class="textarea" id="edit-description" name="description" maxlength="5000">{detail.task.description}</textarea><span class="field-help">Markdown is supported.</span></div>{/if}
        <div class="field"><label for="edit-status">Status</label><SelectMenu id="edit-status" name="status" value={currentStatus} options={statusMenuOptions} ariaLabel="Status" /></div>
        <div class="field"><label for="edit-priority">Priority</label><SelectMenu id="edit-priority" name="priority" value={detail.task.priorityValue} options={severityMenuOptions} ariaLabel="Priority" /></div>
        <div class="field wide"><label for="edit-assignee">Assignee</label><SelectMenu id="edit-assignee" name="assigneeID" value={detail.task.assigneeID} options={assigneeMenuOptions} ariaLabel="Assignee" /></div>
        <div class="field"><label for="edit-start">Start date</label><DatePicker id="edit-start" name="startAt" value={detail.task.startInput} label="Start date" /></div>
        {#if !detail.task.isCanvasLinked}<div class="field"><label for="edit-due">Due date</label><DatePicker id="edit-due" name="dueAt" value={detail.task.dueInput} label="Due date" /></div><div class="field"><label for="edit-time">Due time</label><TimePicker id="edit-time" name="dueTime" value={detail.task.dueTimeInput} label="Due time" /></div>{/if}
        <div class="field"><label for="edit-estimate">Time estimate</label><input class="input" id="edit-estimate" name="estimatedMinutes" type="number" min="5" max="1440" step="5" inputmode="numeric" value={detail.task.hasEstimate ? detail.task.estimatedMinutes : ''} placeholder="Minutes, e.g. 45" /></div>
        {#if !detail.task.isCanvasLinked}<fieldset class="field wide grade-fields"><legend>Grade</legend><div class="grade-input-grid"><label for="edit-grade-earned"><span>Points earned</span><input class="input" id="edit-grade-earned" name="gradeEarned" type="number" min="0" max="100000" step="0.1" inputmode="decimal" value={detail.task.hasGrade ? detail.task.gradeEarned : ''} placeholder="e.g. 87" /></label><label for="edit-grade-possible"><span>Points possible</span><input class="input" id="edit-grade-possible" name="gradePossible" type="number" min="0" max="100000" step="0.1" inputmode="decimal" value={detail.task.hasPointsPossible ? detail.task.gradePossible : ''} placeholder="e.g. 100" /></label></div><span class="field-help">A points value can exist before the assignment receives a score.</span></fieldset>{/if}
        <div class="field wide"><label for="edit-labels">Labels</label><input class="input" id="edit-labels" name="labels" value={detail.task.labelsJoined} maxlength="500" /></div>
      </div></div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (editOpen = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>Save changes</button></div>
    </form>
  </div>
{/if}

{#if remindersOpen}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="task-reminders-title" tabindex="-1" use:dialogLayer={{ close: () => (remindersOpen = false) }}>
    <div class="dialog reminder-dialog">
      <div class="dialog-header"><div><h2 id="task-reminders-title">Assignment reminders</h2><p>Email reminders for this assignment.</p></div><button class="icon-button" type="button" onclick={() => (remindersOpen = false)} aria-label="Close"><X size={16} /></button></div>
      <div class="dialog-body reminder-dialog-body">
        <div class="reminder-recipient"><Alarm size={18} /><span><strong>Send to {currentUserEmail}</strong><small>Each reminder is sent once. You can add up to three.</small></span><span class="badge count tabular">{detail.reminders.length}/3</span></div>

        {#if !detail.notificationsEnabled}
          <p class="reminder-unavailable" role="status">Email delivery is not configured for this workspace.</p>
        {:else}
          {#if detail.reminders.length}
            <div class="reminder-list" aria-label="Scheduled reminders">
              {#each detail.reminders as reminder (reminder.id)}
                <div class="reminder-row"><span class="reminder-icon"><Alarm size={15} /></span><span><strong>{reminder.remindAtDisplay}</strong><small>{reminder.timeZone}</small></span><button class="icon-button" type="button" onclick={() => deleteReminder(reminder.id)} disabled={pending} aria-label={`Remove reminder for ${reminder.remindAtDisplay}`} title="Remove reminder"><Trash2 size={14} /></button></div>
              {/each}
            </div>
          {:else}
            <p class="reminder-empty">No reminders yet. Add one before the deadline gets loud.</p>
          {/if}

          {#if detail.reminders.length < 3}
            <form class="reminder-form" onsubmit={addReminder}>
              <div class="reminder-form-heading"><strong>Add a reminder</strong><span>Times use your current time zone.</span></div>
              <div class="reminder-fields"><div class="field"><label for="reminder-date">Date</label><DatePicker id="reminder-date" name="reminderDate" value={reminderDate} label="Reminder date" required initialFocus /></div><div class="field"><label for="reminder-time">Time</label><TimePicker id="reminder-time" name="reminderTime" value={reminderTime} label="Reminder time" /></div></div>
              <div class="reminder-form-actions"><button class="button primary" type="submit" disabled={pending}><Alarm size={15} />{pending ? 'Saving…' : 'Add reminder'}</button></div>
            </form>
          {/if}
        {/if}
        {#if requestError}<p class="error-message reminder-error" role="alert">{requestError}</p>{/if}
      </div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (remindersOpen = false)}>Done</button></div>
    </div>
  </div>
{/if}

<ConfirmDialog open={Boolean(deletingAttachment)} title={`Delete ${deletingAttachment?.fileName ?? 'this file'}?`} description="This file will be removed from the assignment." confirmLabel="Delete file" pendingLabel="Deleting…" oncancel={() => (deletingAttachment = null)} onconfirm={deleteAttachment} />

{#if deleteOpen}<div class="dialog-layer" role="alertdialog" aria-modal="true" aria-labelledby="delete-task-title" tabindex="-1" use:dialogLayer={{ close: () => (deleteOpen = false), closeOnBackdrop: false }}><div class="dialog"><div class="dialog-header"><div><h2 id="delete-task-title">Delete this assignment?</h2><p>This action cannot be undone.</p></div></div><div class="dialog-footer"><button class="button" type="button" onclick={() => (deleteOpen = false)} data-dialog-focus>Cancel</button><button class="button danger" type="button" onclick={deleteTask} disabled={pending}>Delete assignment</button></div></div></div>{/if}
