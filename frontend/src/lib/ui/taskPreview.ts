import type { StudyAssignmentContext, TaskCardContext } from '$lib/types';
import { writable } from 'svelte/store';

export interface TaskPreviewData {
  description: string;
  statusName: string;
  statusColorClass: string;
  statusColorStyle: string;
  priorityName: string;
  priorityColorClass: string;
  priorityColorStyle: string;
  assigneeName: string;
}

interface TaskPreviewState {
  anchor: HTMLElement;
  task: TaskPreviewData;
  left: number;
  top: number;
  side: 'left' | 'right';
  open: boolean;
  motion: boolean;
}

export const taskPreviewState = writable<TaskPreviewState | null>(null);
let removeTimer: ReturnType<typeof setTimeout> | undefined;
let hasShownPreview = false;

export function previewFromTask(task: TaskCardContext): TaskPreviewData {
  return {
    description: task.description,
    statusName: task.statusName,
    statusColorClass: task.statusColorClass,
    statusColorStyle: task.statusColorStyle,
    priorityName: task.priorityName,
    priorityColorClass: task.priorityColorClass,
    priorityColorStyle: task.priorityColorStyle,
    assigneeName: task.assigneeName
  };
}

export function previewFromAssignment(assignment: StudyAssignmentContext): TaskPreviewData {
  return {
    description: assignment.description,
    statusName: assignment.statusName,
    statusColorClass: assignment.statusColorClass,
    statusColorStyle: assignment.statusCustomColor ? `--workflow-color: ${assignment.statusCustomColor}` : '',
    priorityName: assignment.priorityName,
    priorityColorClass: assignment.priorityColorClass,
    priorityColorStyle: assignment.priorityCustomColor ? `--workflow-color: ${assignment.priorityCustomColor}` : '',
    assigneeName: assignment.assigneeName
  };
}

export function hideTaskPreview(anchor?: HTMLElement): void {
  clearTimeout(removeTimer);
  taskPreviewState.update((state) => {
    if (!state || (anchor && state.anchor !== anchor)) return state;
    return { ...state, open: false };
  });

  // Keep the closed preview mounted until its pointer exit transition finishes.
  removeTimer = setTimeout(() => {
    taskPreviewState.update((state) => state?.open ? state : null);
  }, 120);
}

/** Shows a delayed, viewport-bound task summary for pointer and keyboard users. */
export function taskPreview(node: HTMLElement, initialTask: TaskPreviewData) {
  let task = initialTask;
  let showTimer: ReturnType<typeof setTimeout> | undefined;

  function show(motion: boolean): void {
    clearTimeout(removeTimer);
    const bounds = node.getBoundingClientRect();
    const previewWidth = 320;
    const previewHeight = 220;
    const gap = 12;
    const margin = 12;
    let left = bounds.right + gap;
    let side: TaskPreviewState['side'] = 'right';
    if (left + previewWidth > window.innerWidth - margin) {
      left = bounds.left - previewWidth - gap;
      side = 'left';
    }
    left = Math.max(margin, Math.min(left, window.innerWidth - previewWidth - margin));
    const top = Math.max(margin, Math.min(bounds.top, window.innerHeight - previewHeight - margin));
    taskPreviewState.set({ anchor: node, task, left, top, side, open: true, motion });
    hasShownPreview = true;
  }

  function showSoon(): void {
    clearTimeout(showTimer);
    showTimer = setTimeout(() => show(true), hasShownPreview ? 40 : 140);
  }

  function showFromFocus(): void {
    show(false);
  }

  function hide(): void {
    clearTimeout(showTimer);
    hideTaskPreview(node);
  }

  node.addEventListener('pointerenter', showSoon);
  node.addEventListener('pointerleave', hide);
  node.addEventListener('focus', showFromFocus);
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
      node.removeEventListener('focus', showFromFocus);
      node.removeEventListener('blur', hide);
      node.removeEventListener('dragstart', hide);
    }
  };
}
