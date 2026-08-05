<script lang="ts">
  import type { TaskCardContext } from '$lib/types';
  import { CalendarDotsIcon as CalendarDays, CheckSquareIcon as CheckSquare, ChatCircleIcon as MessageSquare, ClockIcon as Clock, PaperclipIcon as Paperclip } from 'phosphor-svelte';
  import { previewFromTask, taskPreview } from '$lib/ui/taskPreview';

  let {
    task,
    draggable = false,
    moving = false,
    dropPosition = null,
    ondragstart,
    ondragend,
    ondragover,
    ondrop
  } = $props<{
    task: TaskCardContext;
    draggable?: boolean;
    moving?: boolean;
    dropPosition?: 'before' | 'after' | null;
    ondragstart?: (event: DragEvent) => void;
    ondragend?: (event: DragEvent) => void;
    ondragover?: (event: DragEvent) => void;
    ondrop?: (event: DragEvent) => void;
  }>();
</script>

<a
  class:drop-before={dropPosition === 'before'}
  class:drop-after={dropPosition === 'after'}
  class="task-card"
  href={task.href}
  draggable={draggable}
  ondragstart={ondragstart}
  ondragend={ondragend}
  ondragover={ondragover}
  ondrop={ondrop}
  data-moving={moving ? 'true' : undefined}
  data-task-id={task.id}
  use:taskPreview={previewFromTask(task)}
>
  <h3>{task.title}</h3>
  {#if task.hasDescription}<p>{task.description}</p>{/if}
  <div class="task-meta">
    <span class={`badge ${task.priorityColorClass}`} style={task.priorityColorStyle}>{task.priorityName}</span>
    {#each task.labels as label}<span class="badge subtle">{label}</span>{/each}
    {#if task.hasDueDate}<span class="badge"><CalendarDays size={12} />{task.dueDisplay}</span>{/if}
    {#if task.hasEstimate}<span class="badge"><Clock size={12} />{task.estimatedDisplay}</span>{/if}
    <span class="task-badges">
      {#if task.commentCount}<span class="task-badge" title={`${task.commentCount} comments`}><MessageSquare size={12} /><span class="tabular">{task.commentCount}</span></span>{/if}
      {#if task.checklistCount}<span class="task-badge" title="Checklist"><CheckSquare size={12} /><span class="tabular">{task.completedChecklistCount}/{task.checklistCount}</span></span>{/if}
      {#if task.attachmentCount}<span class="task-badge" title={`${task.attachmentCount} attachments`}><Paperclip size={12} /><span class="tabular">{task.attachmentCount}</span></span>{/if}
    </span>
  </div>
</a>
