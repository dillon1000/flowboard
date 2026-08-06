<script lang="ts">
  import type { TaskCardContext } from '$lib/types';
  import { CheckSquareIcon as CheckSquare, ChatCircleIcon as MessageSquare, PaperclipIcon as Paperclip } from 'phosphor-svelte';
  import { deadlineFrom } from '$lib/ui/deadline';
  import { plainSummary } from '$lib/ui/summary';
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

  const deadline = $derived(deadlineFrom(task.dueInput));
  const summary = $derived(task.hasDescription ? plainSummary(task.description) : '');

  // Severity only earns space on a card when it is raised above the ordinary:
  // the stage rail and the countdown are what a lane is scanned for.
  const isUrgent = $derived(
    /priority-high|priority-urgent|workflow-orange|workflow-red/.test(task.priorityColorClass)
  );
</script>

<a
  class:drop-before={dropPosition === 'before'}
  class:drop-after={dropPosition === 'after'}
  class={`lane-card stage-tint ${task.statusColorClass}`}
  style={task.statusColorStyle}
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
  {#if isUrgent}
    <span class={`lane-flag stage-tint ${task.priorityColorClass}`} style={task.priorityColorStyle}>
      {task.priorityName}
    </span>
  {/if}
  {#if task.isCanvasLinked}<span class="lane-source">Canvas</span>{/if}
  <h3>{task.title}</h3>
  {#if summary}<p>{summary}</p>{/if}
  {#if task.hasLabels}
    <span class="lane-labels">
      {#each task.labels.slice(0, 3) as label}<span>{label}</span>{/each}
      {#if task.labels.length > 3}<span class="lane-labels-more">+{task.labels.length - 3}</span>{/if}
    </span>
  {/if}
  <span class="measures">
    <span class="measure-due" data-tone={deadline.tone} title={deadline.long}>{deadline.short}</span>
    <span class:missing={!task.hasEstimate} class="measure-effort">
      {task.hasEstimate ? task.estimatedDisplay : 'No estimate'}
    </span>
    {#if task.hasGrade || task.hasPointsPossible}<span class="measure-grade" title={task.hasGrade ? `Scored ${task.gradeDisplay}` : task.gradeDisplay}>{task.gradeDisplay}</span>{/if}
    <span class="measure-counts">
      {#if task.commentCount}<span title={`${task.commentCount} comments`}><MessageSquare size={12} />{task.commentCount}</span>{/if}
      {#if task.checklistCount}<span title="Checklist"><CheckSquare size={12} />{task.completedChecklistCount}/{task.checklistCount}</span>{/if}
      {#if task.attachmentCount}<span title={`${task.attachmentCount} files`}><Paperclip size={12} />{task.attachmentCount}</span>{/if}
    </span>
  </span>
</a>
