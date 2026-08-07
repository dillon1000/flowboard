<script lang="ts">
  import { hideTaskPreview, taskPreviewState } from '$lib/ui/taskPreview';
  import { ArrowRightIcon as ArrowRight, NotePencilIcon as Note, UserCircleIcon as User } from 'phosphor-svelte';

  function handleKeydown(event: KeyboardEvent): void {
    if (event.key !== 'Escape' || !$taskPreviewState) return;
    event.preventDefault();
    hideTaskPreview();
  }
</script>

<svelte:window onscroll={() => hideTaskPreview()} onresize={() => hideTaskPreview()} onkeydown={handleKeydown} />

{#if $taskPreviewState}
  {@const preview = $taskPreviewState}
  <aside
    class="task-preview"
    data-open={preview.open}
    data-motion={preview.motion}
    data-side={preview.side}
    style={`left: ${preview.left}px; top: ${preview.top}px`}
    aria-hidden="true"
  >
    <div class="preview-heading">
      <span>Quick context</span>
      <div class="preview-badges">
        <span class={`badge status ${preview.task.statusColorClass}`} style={preview.task.statusColorStyle}>{preview.task.statusName}</span>
        <span class={`badge ${preview.task.priorityColorClass}`} style={preview.task.priorityColorStyle}>{preview.task.priorityName}</span>
      </div>
    </div>
    <div class:empty={!preview.task.description} class="preview-note"><Note size={15} /><span>{preview.task.description || 'No notes have been added yet.'}</span></div>
    <div class="preview-assignee"><User size={16} /><span><small>Assigned to</small><strong>{preview.task.assigneeName}</strong></span></div>
    <span class="preview-open-hint">Open for checklist, files, and discussion <ArrowRight size={14} /></span>
  </aside>
{/if}
