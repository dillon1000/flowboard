<script lang="ts">
  import type { TaskCardContext, TaskOptionContext } from '$lib/types';
  import { CheckIcon as Check, CheckSquareIcon as CheckSquare, ChatCircleIcon as MessageSquare, DotsThreeIcon as DotsThree, PaperclipIcon as Paperclip } from 'phosphor-svelte';
  import { deadlineFrom } from '$lib/ui/deadline';
  import { plainSummary } from '$lib/ui/summary';
  import { previewFromTask, taskPreview } from '$lib/ui/taskPreview';
  import PopoverMenu from './PopoverMenu.svelte';

  let {
    task,
    draggable = false,
    moving = false,
    dropPosition = null,
    moveOptions = [],
    onmove,
    ondragstart,
    ondragend,
    ondragover,
    ondrop
  } = $props<{
    task: TaskCardContext;
    draggable?: boolean;
    moving?: boolean;
    dropPosition?: 'before' | 'after' | null;
    moveOptions?: TaskOptionContext[];
    onmove?: (status: string) => void;
    ondragstart?: (event: DragEvent) => void;
    ondragend?: (event: DragEvent) => void;
    ondragover?: (event: DragEvent) => void;
    ondrop?: (event: DragEvent) => void;
  }>();

  const deadline = $derived(deadlineFrom(task.dueInput));
  const summary = $derived(task.hasDescription ? plainSummary(task.description) : '');

  // Priority only earns space on a card when it is raised above the ordinary:
  // the stage rail and the countdown are what a lane is scanned for.
  const isUrgent = $derived(
    /priority-high|priority-urgent|workflow-orange|workflow-red/.test(task.priorityColorClass)
  );
</script>

<div
  class:drop-before={dropPosition === 'before'}
  class:drop-after={dropPosition === 'after'}
  class={`lane-card stage-tint ${task.statusColorClass}`}
  style={task.statusColorStyle}
  draggable={draggable}
  ondragstart={ondragstart}
  ondragend={ondragend}
  ondragover={ondragover}
  ondrop={ondrop}
  data-moving={moving ? 'true' : undefined}
  data-task-id={task.id}
  role="listitem"
>
  <a class="lane-card-link" href={task.href} use:taskPreview={previewFromTask(task)}>
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

  {#if moveOptions.length && onmove}
    <div class="lane-card-menu">
      <PopoverMenu panelLabel={`Move ${task.title} to stage`} align="right">
        {#snippet trigger(control)}
          <button class="icon-button" type="button" disabled={moving} aria-haspopup="menu" aria-expanded={control.open} aria-label={`Move ${task.title} to another stage`} onclick={control.toggle}><DotsThree size={16} weight="bold" /></button>
        {/snippet}
        {#snippet children(close)}
          <span class="menu-heading">Move to stage</span>
          {#each moveOptions as option (option.value)}
            <button class="menu-option" type="button" role="menuitem" disabled={moving || option.value === task.statusValue} onclick={() => { close(); onmove?.(option.value); }}>
              <span class={`column-dot stage-tint ${option.colorClass}`} style={option.colorStyle}></span>{option.name}{#if option.value === task.statusValue}<Check class="menu-check" size={13} />{/if}
            </button>
          {/each}
        {/snippet}
      </PopoverMenu>
    </div>
  {/if}
</div>
