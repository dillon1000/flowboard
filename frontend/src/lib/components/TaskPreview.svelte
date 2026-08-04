<script lang="ts">
  import { hideTaskPreview, taskPreviewState } from '$lib/ui/taskPreview';
</script>

<svelte:window onscroll={() => hideTaskPreview()} onresize={() => hideTaskPreview()} />

{#if $taskPreviewState}
  {@const preview = $taskPreviewState}
  <aside
    class="task-preview"
    data-open="true"
    style={`left: ${preview.left}px; top: ${preview.top}px`}
    aria-hidden="true"
  >
    <span class="preview-board">{preview.task.boardName}</span>
    <h3>{preview.task.title}</h3>
    <div class="preview-badges">
      <span class={`badge status ${preview.task.statusColorClass}`} style={preview.task.statusColorStyle}>{preview.task.statusName}</span>
      <span class={`badge ${preview.task.priorityColorClass}`} style={preview.task.priorityColorStyle}>{preview.task.priorityName}</span>
    </div>
    {#if preview.task.description}<p class="preview-body">{preview.task.description}</p>{/if}
    <dl><dt>Assignee</dt><dd>{preview.task.assigneeName}</dd><dt>Due</dt><dd>{preview.task.dueDisplay}</dd></dl>
  </aside>
{/if}
