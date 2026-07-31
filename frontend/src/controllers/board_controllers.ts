import { Controller } from '@hotwired/stimulus';
import confetti from 'canvas-confetti';
import { autorun, type IReactionDisposer } from 'mobx';
import Sortable, { type SortableEvent } from 'sortablejs';
import { appStore } from '../stores/app_store';

// The standard value remains a fallback for forms rendered without board metadata.
const DEFAULT_COMPLETION_STATUS = 'done';
const TASK_COMPLETED_EVENT = 'flowboard:task-completed';
const PENDING_COMPLETION_KEY = 'flowboard-pending-completion';

type ConfettiOrigin = {
  x: number;
  y: number;
};

type TaskCompletedDetail = {
  origin?: ConfettiOrigin;
};

// Coordinates one-shot completion effects from direct board moves and Turbo form
// redirects. Failed form submissions never set the pending completion flag.
export class CompletionController extends Controller {
  private pendingForms = new WeakSet<HTMLFormElement>();

  connect(): void {
    document.addEventListener('turbo:submit-start', this.handleSubmitStart);
    document.addEventListener('turbo:submit-end', this.handleSubmitEnd);
    document.addEventListener('turbo:load', this.handleTurboLoad);
    window.addEventListener(TASK_COMPLETED_EVENT, this.handleTaskCompleted);
  }

  disconnect(): void {
    document.removeEventListener('turbo:submit-start', this.handleSubmitStart);
    document.removeEventListener('turbo:submit-end', this.handleSubmitEnd);
    document.removeEventListener('turbo:load', this.handleTurboLoad);
    window.removeEventListener(TASK_COMPLETED_EVENT, this.handleTaskCompleted);
  }

  private readonly handleSubmitStart = (event: Event): void => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement) || !form.dataset.completionStatus) {
      return;
    }

    const nextStatus = new FormData(form).get('status');
    const completionStatuses = (form.dataset.completionStatuses ?? DEFAULT_COMPLETION_STATUS).split(',');
    if (
      !completionStatuses.includes(form.dataset.completionStatus) &&
      typeof nextStatus === 'string' &&
      completionStatuses.includes(nextStatus)
    ) {
      this.pendingForms.add(form);
    } else {
      this.pendingForms.delete(form);
    }
  };

  private readonly handleSubmitEnd = (event: Event): void => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement) || !this.pendingForms.has(form)) {
      return;
    }

    this.pendingForms.delete(form);
    const { success } = (event as CustomEvent<{ success: boolean }>).detail;
    if (success) {
      sessionStorage.setItem(PENDING_COMPLETION_KEY, 'true');
    }
  };

  private readonly handleTurboLoad = (): void => {
    if (sessionStorage.getItem(PENDING_COMPLETION_KEY) !== 'true') {
      return;
    }

    sessionStorage.removeItem(PENDING_COMPLETION_KEY);
    requestAnimationFrame(() => this.celebrate());
  };

  private readonly handleTaskCompleted = (event: Event): void => {
    const detail = (event as CustomEvent<TaskCompletedDetail>).detail;
    this.celebrate(detail.origin);
  };

  private celebrate(origin: ConfettiOrigin = { x: 0.5, y: 0.6 }): void {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
      return;
    }

    void confetti({
      angle: 90,
      colors: ['#0070f3', '#17a673', '#f5a623', '#8e4ec6', '#e5484d'],
      disableForReducedMotion: true,
      gravity: 0.9,
      origin,
      particleCount: 80,
      scalar: 0.85,
      spread: 70,
      startVelocity: 42,
      ticks: 180,
    });
  }
}

export class BoardController extends Controller {
  static targets = ['column'];
  static values = { editable: Boolean };

  declare readonly columnTargets: HTMLElement[];
  declare readonly editableValue: boolean;
  private sortables: Sortable[] = [];
  private stopObserving?: IReactionDisposer;

  connect(): void {
    if (!this.editableValue) {
      return;
    }
    this.stopObserving = autorun(() => {
      this.element.querySelectorAll<HTMLElement>('[data-task-id]').forEach((task) => {
        const taskID = task.dataset.taskId;
        task.toggleAttribute('aria-busy', Boolean(taskID && appStore.pendingTaskMoveIDs.has(taskID)));
      });
    });
    this.sortables = this.columnTargets.map((column) => new Sortable(column, {
      animation: 140,
      draggable: '[data-task-id]',
      dragClass: 'task-card-drag',
      filter: '[aria-busy="true"]',
      ghostClass: 'task-card-ghost',
      group: 'flowboard-tasks',
      onEnd: (event) => void this.persistMove(event),
    }));
  }

  disconnect(): void {
    this.stopObserving?.();
    this.sortables.forEach((sortable) => sortable.destroy());
  }

  private async persistMove(event: SortableEvent): Promise<void> {
    const task = event.item as HTMLElement;
    const column = event.to as HTMLElement;
    const sourceColumn = event.from as HTMLElement;
    const taskID = task.dataset.taskId;
    const status = column.dataset.status;
    if (!taskID || !status) {
      window.location.reload();
      return;
    }

    try {
      await appStore.moveTask({
        csrfToken: document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '',
        status,
        targetIndex: event.newIndex ?? 0,
        taskID,
      });
      if (sourceColumn.dataset.completed !== 'true' && column.dataset.completed === 'true') {
        const rect = task.getBoundingClientRect();
        window.dispatchEvent(new CustomEvent<TaskCompletedDetail>(TASK_COMPLETED_EVENT, {
          detail: {
            origin: {
              x: (rect.left + rect.width / 2) / window.innerWidth,
              y: (rect.top + rect.height / 2) / window.innerHeight,
            },
          },
        }));
      }
      appStore.showNotification('Task moved');
    } catch {
      window.location.reload();
    }
  }
}
