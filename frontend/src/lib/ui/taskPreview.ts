import type { StudyAssignmentContext, TaskCardContext } from '$lib/types';
import { writable } from 'svelte/store';

export interface TaskPreviewData {
  title: string;
  boardName: string;
  description: string;
  statusName: string;
  statusColorClass: string;
  statusColorStyle: string;
  priorityName: string;
  priorityColorClass: string;
  priorityColorStyle: string;
  assigneeName: string;
  dueDisplay: string;
}

interface TaskPreviewState {
  anchor: HTMLElement;
  task: TaskPreviewData;
  left: number;
  top: number;
}

export const taskPreviewState = writable<TaskPreviewState | null>(null);

export function previewFromTask(task: TaskCardContext): TaskPreviewData {
  return {
    title: task.title,
    boardName: task.boardName,
    description: task.description,
    statusName: task.statusName,
    statusColorClass: task.statusColorClass,
    statusColorStyle: task.statusColorStyle,
    priorityName: task.priorityName,
    priorityColorClass: task.priorityColorClass,
    priorityColorStyle: task.priorityColorStyle,
    assigneeName: task.assigneeName,
    dueDisplay: task.dueDisplay
  };
}

export function previewFromAssignment(assignment: StudyAssignmentContext): TaskPreviewData {
  return {
    title: assignment.title,
    boardName: assignment.courseName,
    description: assignment.description,
    statusName: assignment.statusName,
    statusColorClass: assignment.statusColorClass,
    statusColorStyle: assignment.statusCustomColor ? `--workflow-color: ${assignment.statusCustomColor}` : '',
    priorityName: assignment.priorityName,
    priorityColorClass: assignment.priorityColorClass,
    priorityColorStyle: assignment.priorityCustomColor ? `--workflow-color: ${assignment.priorityCustomColor}` : '',
    assigneeName: assignment.assigneeName,
    dueDisplay: assignment.dueDisplay
  };
}

export function hideTaskPreview(anchor?: HTMLElement): void {
  taskPreviewState.update((state) => !anchor || state?.anchor === anchor ? null : state);
}

/** Shows a delayed, viewport-bound task summary for pointer and keyboard users. */
export function taskPreview(node: HTMLElement, initialTask: TaskPreviewData) {
  let task = initialTask;
  let showTimer: ReturnType<typeof setTimeout> | undefined;

  function show(): void {
    const bounds = node.getBoundingClientRect();
    const previewWidth = 300;
    const previewHeight = 260;
    const gap = 12;
    const margin = 12;
    let left = bounds.right + gap;
    if (left + previewWidth > window.innerWidth - margin) left = bounds.left - previewWidth - gap;
    left = Math.max(margin, Math.min(left, window.innerWidth - previewWidth - margin));
    const top = Math.max(margin, Math.min(bounds.top, window.innerHeight - previewHeight - margin));
    taskPreviewState.set({ anchor: node, task, left, top });
  }

  function showSoon(): void {
    clearTimeout(showTimer);
    showTimer = setTimeout(show, 180);
  }

  function hide(): void {
    clearTimeout(showTimer);
    hideTaskPreview(node);
  }

  node.addEventListener('pointerenter', showSoon);
  node.addEventListener('pointerleave', hide);
  node.addEventListener('focus', show);
  node.addEventListener('blur', hide);
  node.addEventListener('dragstart', hide);

  return {
    update(nextTask: TaskPreviewData): void {
      task = nextTask;
    },
    destroy(): void {
      hide();
      node.removeEventListener('pointerenter', showSoon);
      node.removeEventListener('pointerleave', hide);
      node.removeEventListener('focus', show);
      node.removeEventListener('blur', hide);
      node.removeEventListener('dragstart', hide);
    }
  };
}
