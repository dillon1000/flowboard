<script lang="ts">
  import type { TaskCardContext } from '$lib/types';
  import { CalendarDays, CheckSquare, MessageSquare, Paperclip } from '@lucide/svelte';

  let { task, draggable = false, ondragstart } = $props<{
    task: TaskCardContext;
    draggable?: boolean;
    ondragstart?: (event: DragEvent) => void;
  }>();
</script>

<a class="task-card" href={task.href} draggable={draggable} ondragstart={ondragstart} data-task-id={task.id}>
  <h3>{task.title}</h3>
  {#if task.hasDescription}<p>{task.description}</p>{/if}
  <div class="task-meta">
    <span class={`badge ${task.priorityColorClass}`} style={task.priorityColorStyle}>{task.priorityName}</span>
    {#each task.labels as label}<span class="badge subtle">{label}</span>{/each}
    {#if task.hasDueDate}<span class="badge"><CalendarDays size={12} />{task.dueDisplay}</span>{/if}
    <span class="task-badges">
      {#if task.commentCount}<span class="task-badge" title={`${task.commentCount} comments`}><MessageSquare size={12} /><span class="tabular">{task.commentCount}</span></span>{/if}
      {#if task.checklistCount}<span class="task-badge" title="Checklist"><CheckSquare size={12} /><span class="tabular">{task.completedChecklistCount}/{task.checklistCount}</span></span>{/if}
      {#if task.attachmentCount}<span class="task-badge" title={`${task.attachmentCount} attachments`}><Paperclip size={12} /><span class="tabular">{task.attachmentCount}</span></span>{/if}
    </span>
  </div>
</a>
