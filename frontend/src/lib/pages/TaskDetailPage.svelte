<script lang="ts">
  import { goto, invalidateAll } from '$app/navigation';
  import { api, messageFor } from '$lib/api';
  import type { AvatarContext, ChecklistContext, MemberOptionContext, TaskDetailPageContext, TaskOptionContext, TaskPropertyOptionContext } from '$lib/types';
  import confetti from 'canvas-confetti';
  import { ArchiveIcon as Archive, BellIcon as Bell, CalendarDotsIcon as CalendarDays, CheckIcon as Check, DownloadIcon as Download, PaperclipIcon as Paperclip, PlusIcon as Plus, TrashIcon as Trash2, UploadIcon as Upload, UserIcon as User, XIcon as X } from 'phosphor-svelte';
  import Avatar from '$lib/components/Avatar.svelte';
  import DatePicker from '$lib/components/DatePicker.svelte';
  import PromoteMenu from '$lib/components/PromoteMenu.svelte';
  import SelectMenu, { type SelectMenuOption } from '$lib/components/SelectMenu.svelte';
  import { dialogLayer } from '$lib/actions/dialogLayer';
  import { onMount } from 'svelte';
  import { showToast } from '$lib/ui/toast';

  // The API rejects larger request bodies. Keep the browser limit equal to the
  // server limit so a user gets a useful message before an upload starts.
  const maxAttachmentBytes = 10_000_000;

  let { detail, currentUserAvatar, descriptionHTML } = $props<{
    detail: TaskDetailPageContext;
    currentUserAvatar: AvatarContext;
    descriptionHTML: string;
  }>();
  let editOpen = $state(false);
  let deleteOpen = $state(false);
  let pending = $state(false);
  let requestError = $state('');
  let commentBody = $state('');
  let selectedFileName = $state('No file chosen');
  let checklist = $state<ChecklistContext[]>([]);
  let pendingChecklistIDs = $state<string[]>([]);
  let uploadPending = $state(false);
  let uploadProgress = $state(0);
  let uploadError = $state('');

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
  const commentDraftKey = $derived(`flowboard-comment-draft:${detail.task.id}`);

  $effect(() => {
    checklist = detail.checklist.map((item: ChecklistContext) => ({ ...item }));
  });

  onMount(() => {
    commentBody = sessionStorage.getItem(commentDraftKey) ?? '';
  });

  function apiDate(value: FormDataEntryValue | null): string | null {
    const date = String(value ?? '');
    return date ? `${date}T00:00:00Z` : null;
  }

  async function mutate(path: string, init: RequestInit, successMessage = ''): Promise<boolean> {
    pending = true;
    requestError = '';
    try {
      await api(path, init);
      await invalidateAll();
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
    if (await mutate(`/api/v1/tasks/${detail.task.id}`, { method: 'PATCH', body: JSON.stringify({ status }) }, 'Task status updated') && didComplete) {
      confetti({ particleCount: 80, spread: 70, origin: { y: 0.7 } });
    }
  }

  async function toggleFollow(): Promise<void> {
    await mutate(`/api/v1/tasks/${detail.task.id}/followers/me`, {
      method: detail.isFollowing ? 'DELETE' : 'POST'
    }, detail.isFollowing ? 'Task unfollowed' : 'Task followed');
  }

  async function saveTask(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const assigneeID = String(data.get('assigneeID') ?? '');
    const saved = await mutate(`/api/v1/tasks/${detail.task.id}`, {
      method: 'PATCH',
      body: JSON.stringify({
        title: String(data.get('title') ?? ''),
        description: String(data.get('description') ?? '') || null,
        status: String(data.get('status') ?? ''),
        priority: String(data.get('priority') ?? ''),
        assigneeID: assigneeID || null,
        startAt: apiDate(data.get('startAt')),
        dueAt: apiDate(data.get('dueAt')),
        labels: String(data.get('labels') ?? '').split(',').map((label) => label.trim()).filter(Boolean).slice(0, 6)
      })
    }, 'Task updated');
    if (saved) editOpen = false;
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
      await invalidateAll();
      showToast(item.isCompleted ? 'Checklist item completed' : 'Checklist item reopened');
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
    if (await mutate(`/api/v1/tasks/${detail.task.id}/checklist`, { method: 'POST', body: JSON.stringify({ title }) }, 'Checklist item added')) form.reset();
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

  async function saveProperties(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const properties: Record<string, string> = {};
    for (const property of detail.properties) {
      if (property.usesMultiSelect) {
        const selected = property.options
          .filter((option: TaskPropertyOptionContext) => data.has(`property-${property.id}-${option.id}`))
          .map((option: TaskPropertyOptionContext) => option.id);
        if (selected.length) properties[property.id] = JSON.stringify(selected);
      } else {
        const value = String(data.get(`property-${property.id}`) ?? '').trim();
        if (value) properties[property.id] = value;
      }
    }
    await mutate(`/api/v1/tasks/${detail.task.id}`, { method: 'PATCH', body: JSON.stringify({ properties }) }, 'Custom fields saved');
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
      await invalidateAll();
      showToast('Attachment uploaded');
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
    if (await mutate(`/api/v1/tasks/${detail.task.id}`, { method: 'PATCH', body: JSON.stringify({ isArchived: !wasArchived }) }, wasArchived ? 'Task restored' : 'Task archived') && !wasArchived) {
      await goto(detail.boardHref);
    }
  }

  async function deleteTask(): Promise<void> {
    pending = true;
    requestError = '';
    try {
      await api(`/api/v1/tasks/${detail.task.id}`, { method: 'DELETE' });
      showToast('Task deleted');
      await goto(detail.boardHref, { invalidateAll: true });
    } catch (cause) {
      requestError = messageFor(cause);
      pending = false;
    }
  }
</script>

<div class="page task-detail-page">
  <header class="page-header detail-header">
    <div class="page-title">
      <h1>{detail.task.title}</h1>
      <div class="task-facts">
        <span class={`badge status ${detail.task.statusColorClass}`} style={detail.task.statusColorStyle}>{detail.task.statusName}</span>
        <span class={`badge ${detail.task.priorityColorClass}`} style={detail.task.priorityColorStyle}>{detail.task.priorityName}</span>
        {#each detail.task.labels as label}<span class="badge subtle">{label}</span>{/each}
        <span class="fact-divider" aria-hidden="true"></span><span class:muted={!detail.task.hasAssignee} class="fact"><User size={14} />{detail.task.assigneeName}</span><span class:muted={!detail.task.hasDueDate} class="fact"><CalendarDays size={14} />{detail.task.dueDisplay}</span>
      </div>
    </div>
    <div class="page-actions">
      {#if detail.canEdit}<PromoteMenu value={detail.task.statusValue} options={detail.task.statusOptions} disabled={pending} onchange={changeStatus} />{/if}
      <button class="button" type="button" onclick={toggleFollow} disabled={pending}><Bell size={15} />{detail.isFollowing ? 'Unfollow' : 'Follow'}<span class="badge count tabular">{detail.followerCount}</span></button>
      {#if detail.canEdit}<button class="button" type="button" onclick={() => (editOpen = true)}>Edit task</button>{/if}
    </div>
  </header>
  {#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}

  <div class="split-layout">
    <div class="task-main">
      <section class="card"><div class="card-header"><h2>Description</h2></div><div class="card-body">{#if detail.task.hasDescription}<div class="task-description markdown">{@html descriptionHTML}</div>{:else}<div class="task-description empty">No description yet.</div>{/if}</div></section>

      <section class="card">
        <div class="card-header"><h2>Checklist</h2><span class="checklist-progress"><span>{checklist.length ? `${completedChecklist} of ${checklist.length}` : 'No items'}</span><progress class="progress" value={completedChecklist} max={checklist.length || 1}></progress></span></div>
        {#if checklist.length}<div class="card-body"><div class="checklist">{#each checklist as item (item.id)}<div class:completed={item.isCompleted} class="checklist-item" data-pending={pendingChecklistIDs.includes(item.id) ? 'true' : undefined}><button class:checked={item.isCompleted} class="custom-checkbox" type="button" onclick={() => toggleChecklist(item.id, item.isCompleted)} disabled={!detail.canEdit || pendingChecklistIDs.includes(item.id)} aria-label={`Toggle “${item.title}”`}><Check size={13} /></button><span>{item.title}</span></div>{/each}</div></div>{:else}<p class="card-empty">Nothing to check off yet.</p>{/if}
        {#if detail.canEdit}<div class="card-footer"><form class="checklist-add" onsubmit={addChecklist}><input class="input" name="title" placeholder="Add checklist item" maxlength="200" required aria-label="New checklist item" /><button class="button" type="submit" disabled={pending}><Plus size={14} />Add</button></form></div>{/if}
      </section>

      <section class="card">
        <div class="card-header"><h2>Attachments</h2></div>
        {#if detail.hasAttachments}<div class="card-body"><div class="attachment-grid">{#each detail.attachments as attachment (attachment.id)}<div class="attachment">
          {#if attachment.isImage}<a class="attachment-media attachment-image" href={attachment.previewHref} target="_blank" rel="noopener"><img src={attachment.previewHref} alt="" loading="lazy" /></a>{:else if attachment.isAudio}<div class="attachment-media attachment-audio"><audio controls preload="metadata" src={attachment.previewHref} aria-label={`Preview ${attachment.fileName}`}></audio></div>{:else if attachment.isVideo}<div class="attachment-media attachment-video"><!-- svelte-ignore a11y_media_has_caption --><video controls preload="metadata" src={attachment.previewHref} aria-label={`Preview ${attachment.fileName}`} playsinline></video></div>{:else}<span class="attachment-file-icon"><Paperclip size={20} /></span>{/if}
          <div class="attachment-details"><span class="attachment-copy"><strong title={attachment.fileName}>{attachment.fileName}</strong><small>{attachment.sizeDisplay}</small></span><span class="attachment-actions"><a class="button ghost small" href={attachment.href}><Download size={13} />Download</a>{#if detail.canEdit}<button class="button ghost small attachment-delete" type="button" onclick={() => confirm('Delete this attachment?') && mutate(`/api/v1/attachments/${attachment.id}`, { method: 'DELETE' }, 'Attachment deleted')}><Trash2 size={13} />Delete</button>{/if}</span></div>
        </div>{/each}</div></div>{:else}<p class="card-empty">No files attached.</p>{/if}
        {#if detail.canEdit}<div class="card-footer"><form class="attachment-upload-form" onsubmit={uploadAttachment}><span class="file-field"><label class="button small" aria-disabled={uploadPending}><Upload size={13} />Choose file<input class="sr-only" type="file" name="file" required disabled={uploadPending} onchange={selectAttachment} /></label><span class="file-name">{selectedFileName}</span><button class="button small primary" type="submit" disabled={uploadPending || !!uploadError}>{uploadPending ? 'Uploading…' : 'Upload'}</button></span>{#if uploadPending}<div class="upload-progress" aria-live="polite"><div class="upload-progress-meta"><span>Uploading attachment</span><span class="tabular">{uploadProgress}%</span></div><progress class="upload-progress-bar" max="100" value={uploadProgress}></progress></div>{/if}{#if uploadError}<p class="upload-error" role="alert">{uploadError}</p>{/if}</form></div>{/if}
      </section>

      <section class="card">
        <div class="card-header"><h2>Comments</h2><span class="badge count tabular">{detail.comments.length}</span></div>
        {#if !detail.hasComments}<p class="card-empty">No comments yet.</p>{/if}
        <div class="comment-thread">{#each detail.comments as comment (comment.id)}<div class="comment"><Avatar avatar={comment.authorAvatar} /><div><div class="comment-meta"><strong>{comment.authorName}</strong><span>{comment.createdDisplay}</span></div><div class="comment-body">{comment.body}</div>{#if comment.canDelete}<div class="comment-actions"><button class="button ghost small" type="button" onclick={() => mutate(`/api/v1/tasks/${detail.task.id}/comments/${comment.id}`, { method: 'DELETE' }, 'Comment deleted')}>Delete</button></div>{/if}</div></div>{/each}</div>
        {#if detail.canComment}<form class="comment-composer" onsubmit={addComment}><Avatar avatar={currentUserAvatar} /><div><label class="sr-only" for="new-comment">Add a comment</label><textarea class="textarea" id="new-comment" value={commentBody} oninput={updateCommentDraft} onkeydown={submitCommentShortcut} maxlength="4000" placeholder="Leave a comment…" required></textarea><div class="form-actions"><span class="comment-draft-meta"><span class="tabular">{commentBody.length} / 4000</span><kbd>⌘/Ctrl Enter</kbd></span><button class="button primary" type="submit" disabled={pending || !commentBody.trim()}>Comment</button></div></div></form>{/if}
      </section>
    </div>

    <aside class="task-sidebar">
      <div class="card"><div class="card-header"><h2>Properties</h2></div><dl class="property-list"><div class="property-row"><dt>Status</dt><dd><span class={`badge status ${detail.task.statusColorClass}`} style={detail.task.statusColorStyle}>{detail.task.statusName}</span></dd></div><div class="property-row"><dt>Severity</dt><dd><span class={`badge ${detail.task.priorityColorClass}`} style={detail.task.priorityColorStyle}>{detail.task.priorityName}</span></dd></div><div class="property-row"><dt>Assignee</dt><dd>{detail.task.assigneeName}</dd></div><div class="property-row"><dt>Creator</dt><dd>{detail.creatorName}</dd></div><div class="property-row"><dt>Start</dt><dd class="muted">{detail.task.startDisplay}</dd></div><div class="property-row"><dt>Due</dt><dd>{detail.task.dueDisplay}</dd></div>{#each detail.properties as property}<div class="property-row"><dt>{property.name}</dt><dd>{property.value}</dd></div>{/each}</dl></div>

      {#if detail.canEdit && detail.hasProperties}<section class="card"><div class="card-header"><h2>Custom fields</h2></div><form class="card-body" onsubmit={saveProperties}>{#each detail.properties as property}<div class="field"><label for={`property-${property.id}`}>{property.name}</label>{#if property.usesInput}{#if property.inputType === 'date'}<DatePicker id={`property-${property.id}`} name={`property-${property.id}`} value={property.inputValue} label={property.name} />{:else}<input class="input" type={property.inputType} step="any" id={`property-${property.id}`} name={`property-${property.id}`} value={property.inputValue} />{/if}{:else if property.usesSelect}<SelectMenu id={`property-${property.id}`} name={`property-${property.id}`} value={property.inputValue} ariaLabel={property.name} options={[{ value: '', label: 'No value' }, ...property.options.map((option: TaskPropertyOptionContext) => ({ value: option.id, label: option.name }))]} />{:else if property.usesMultiSelect}<div class="property-options" id={`property-${property.id}`}>{#each property.options as option}<label class="property-option"><input type="checkbox" name={`property-${property.id}-${option.id}`} checked={option.isSelected} /><span>{option.name}</span></label>{/each}</div>{:else if property.usesCheckbox}<label class="property-boolean"><input type="checkbox" name={`property-${property.id}`} value="true" checked={property.isChecked} /><span>Checked</span></label>{/if}</div>{/each}<div class="form-actions"><button class="button small" type="submit" disabled={pending}>Save fields</button></div></form></section>{/if}

      {#if detail.canEdit}<section class="card danger-zone"><div class="card-header"><h2>Danger zone</h2></div><div class="card-rows"><div class="panel-row"><span class="panel-row-main"><strong>{detail.task.isArchived ? 'Restore task' : 'Archive task'}</strong><span>Archived tasks leave active views.</span></span><button class="button small" type="button" onclick={archiveTask} disabled={pending}><Archive size={13} />{detail.task.isArchived ? 'Restore' : 'Archive'}</button></div><div class="panel-row"><span class="panel-row-main"><strong>Delete task</strong><span>Permanently remove this task.</span></span><button class="button danger small" type="button" onclick={() => (deleteOpen = true)}>Delete</button></div></div></section>{/if}
    </aside>
  </div>
</div>

{#if editOpen}
  <div class="dialog-layer" role="dialog" aria-modal="true" aria-labelledby="edit-task-title" tabindex="-1" use:dialogLayer={{ close: () => (editOpen = false) }}>
    <form class="dialog wide" onsubmit={saveTask}>
      <div class="dialog-header"><div><h2 id="edit-task-title">Edit task</h2><p>Update the task and its schedule.</p></div><button class="icon-button" type="button" onclick={() => (editOpen = false)} aria-label="Close"><X size={16} /></button></div>
      <div class="dialog-body"><div class="form-grid">
        <div class="field wide"><label for="edit-title">Title</label><input class="input" id="edit-title" name="title" value={detail.task.title} maxlength="120" required data-dialog-focus /></div>
        <div class="field wide"><label for="edit-description">Description</label><textarea class="textarea" id="edit-description" name="description" maxlength="5000">{detail.task.description}</textarea><span class="field-help">Markdown is supported.</span></div>
        <div class="field"><label for="edit-status">Status</label><SelectMenu id="edit-status" name="status" value={detail.task.statusValue} options={statusMenuOptions} ariaLabel="Status" /></div>
        <div class="field"><label for="edit-priority">Severity</label><SelectMenu id="edit-priority" name="priority" value={detail.task.priorityValue} options={severityMenuOptions} ariaLabel="Severity" /></div>
        <div class="field wide"><label for="edit-assignee">Assignee</label><SelectMenu id="edit-assignee" name="assigneeID" value={detail.task.assigneeID} options={assigneeMenuOptions} ariaLabel="Assignee" /></div>
        <div class="field"><label for="edit-start">Start date</label><DatePicker id="edit-start" name="startAt" value={detail.task.startInput} label="Start date" /></div>
        <div class="field"><label for="edit-due">Due date</label><DatePicker id="edit-due" name="dueAt" value={detail.task.dueInput} label="Due date" /></div>
        <div class="field wide"><label for="edit-labels">Labels</label><input class="input" id="edit-labels" name="labels" value={detail.task.labelsJoined} maxlength="500" /></div>
      </div></div>
      <div class="dialog-footer"><button class="button" type="button" onclick={() => (editOpen = false)}>Cancel</button><button class="button primary" type="submit" disabled={pending}>Save changes</button></div>
    </form>
  </div>
{/if}

{#if deleteOpen}<div class="dialog-layer" role="alertdialog" aria-modal="true" aria-labelledby="delete-task-title" tabindex="-1" use:dialogLayer={{ close: () => (deleteOpen = false), closeOnBackdrop: false }}><div class="dialog"><div class="dialog-header"><div><h2 id="delete-task-title">Delete this task?</h2><p>This action cannot be undone.</p></div></div><div class="dialog-footer"><button class="button" type="button" onclick={() => (deleteOpen = false)} data-dialog-focus>Cancel</button><button class="button danger" type="button" onclick={deleteTask} disabled={pending}>Delete task</button></div></div></div>{/if}
