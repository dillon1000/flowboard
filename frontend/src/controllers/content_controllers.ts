import { Controller } from '@hotwired/stimulus';
import { autorun, type IReactionDisposer } from 'mobx';
import {
  appStore,
  type TaskPreview,
  type ToastNotification,
} from '../stores/app_store';

const PREVIEW_DELAY = 340;

// One delegated listener drives task previews in every view, so adding a new
// view only means adding data-preview-* attributes to its links.
export class TaskPreviewController extends Controller {
  static targets = ['card', 'title', 'board', 'status', 'priority', 'assignee', 'due', 'body'];

  declare readonly cardTarget: HTMLElement;
  declare readonly titleTarget: HTMLElement;
  declare readonly boardTarget: HTMLElement;
  declare readonly statusTarget: HTMLElement;
  declare readonly priorityTarget: HTMLElement;
  declare readonly assigneeTarget: HTMLElement;
  declare readonly dueTarget: HTMLElement;
  declare readonly bodyTarget: HTMLElement;

  private timer = 0;
  private anchor: HTMLElement | null = null;
  private stopObserving?: IReactionDisposer;

  connect(): void {
    if (matchMedia('(hover: none)').matches) {
      return;
    }
    this.stopObserving = autorun(() => this.render(appStore.taskPreview));
    document.addEventListener('pointerover', this.handleOver);
    document.addEventListener('pointerout', this.handleOut);
    document.addEventListener('focusin', this.handleOver);
    document.addEventListener('focusout', this.handleOut);
    window.addEventListener('scroll', this.dismiss, true);
    document.addEventListener('keydown', this.handleKeydown);
  }

  disconnect(): void {
    document.removeEventListener('pointerover', this.handleOver);
    document.removeEventListener('pointerout', this.handleOut);
    document.removeEventListener('focusin', this.handleOver);
    document.removeEventListener('focusout', this.handleOut);
    window.removeEventListener('scroll', this.dismiss, true);
    document.removeEventListener('keydown', this.handleKeydown);
    window.clearTimeout(this.timer);
    this.stopObserving?.();
    appStore.hideTaskPreview();
  }

  private readonly handleOver = (event: Event): void => {
    const target = (event.target as HTMLElement | null)?.closest<HTMLElement>('[data-preview-title]');
    if (!target || target === this.anchor) {
      return;
    }
    window.clearTimeout(this.timer);
    this.anchor = target;
    this.timer = window.setTimeout(() => this.show(target), PREVIEW_DELAY);
  };

  private readonly handleOut = (event: Event): void => {
    const target = (event.target as HTMLElement | null)?.closest<HTMLElement>('[data-preview-title]');
    if (!target || target !== this.anchor) {
      return;
    }
    this.dismiss();
  };

  private readonly handleKeydown = (event: KeyboardEvent): void => {
    if (event.key === 'Escape') {
      this.dismiss();
    }
  };

  private readonly dismiss = (): void => {
    window.clearTimeout(this.timer);
    this.anchor = null;
    appStore.hideTaskPreview();
  };

  private show(anchor: HTMLElement): void {
    const data = anchor.dataset;
    appStore.showTaskPreview({
      assignee: data.previewAssignee ?? '',
      board: data.previewBoard ?? '',
      body: data.previewBody ?? '',
      due: data.previewDue ?? '',
      priority: data.previewPriority ?? '',
      priorityClass: data.previewPriorityClass ?? 'workflow-gray',
      priorityColor: data.previewPriorityColor,
      status: data.previewStatus ?? '',
      statusClass: data.previewStatusClass ?? 'workflow-gray',
      statusColor: data.previewStatusColor,
      title: data.previewTitle ?? '',
    });
  }

  private render(preview: TaskPreview | null): void {
    if (!preview || !this.anchor) {
      this.cardTarget.hidden = true;
      delete this.cardTarget.dataset.open;
      return;
    }

    this.titleTarget.textContent = preview.title;
    this.boardTarget.textContent = preview.board;
    this.boardTarget.hidden = !preview.board;
    this.statusTarget.textContent = preview.status;
    this.statusTarget.className = `badge status ${preview.statusClass}`;
    this.applyWorkflowColor(this.statusTarget, preview.statusColor);
    this.priorityTarget.textContent = preview.priority;
    this.priorityTarget.className = `badge ${preview.priorityClass}`;
    this.applyWorkflowColor(this.priorityTarget, preview.priorityColor);
    this.assigneeTarget.textContent = preview.assignee;
    this.dueTarget.textContent = preview.due;
    this.bodyTarget.textContent = preview.body;
    this.bodyTarget.hidden = !preview.body;

    this.cardTarget.hidden = false;
    this.position(this.anchor);
    this.cardTarget.dataset.open = 'true';
  }

  private applyWorkflowColor(target: HTMLElement, color: string | undefined): void {
    target.style.removeProperty('--workflow-color');
    if (color) {
      target.style.setProperty('--workflow-color', color);
    }
  }

  // Prefer sitting to the right of the anchor; flip or clamp at the edges.
  private position(anchor: HTMLElement): void {
    const card = this.cardTarget;
    card.style.left = '0px';
    card.style.top = '0px';
    const rect = anchor.getBoundingClientRect();
    const size = card.getBoundingClientRect();
    const margin = 12;

    let left = rect.right + 8;
    if (left + size.width > window.innerWidth - margin) {
      left = rect.left - size.width - 8;
    }
    left = Math.max(margin, Math.min(left, window.innerWidth - size.width - margin));

    let top = rect.top;
    top = Math.max(margin, Math.min(top, window.innerHeight - size.height - margin));

    card.style.left = `${Math.round(left)}px`;
    card.style.top = `${Math.round(top)}px`;
  }
}

export class ToastController extends Controller {
  static targets = ['message'];

  declare readonly messageTarget: HTMLElement;
  private timer?: number;
  private stopObserving?: IReactionDisposer;

  connect(): void {
    this.stopObserving = autorun(() => this.render(appStore.notification));
  }

  disconnect(): void {
    this.stopObserving?.();
    window.clearTimeout(this.timer);
  }

  private render(notification: ToastNotification | null): void {
    window.clearTimeout(this.timer);
    if (!notification) {
      delete (this.element as HTMLElement).dataset.visible;
      this.element.setAttribute('hidden', '');
      return;
    }

    this.messageTarget.textContent = notification.message;
    this.element.removeAttribute('hidden');
    (this.element as HTMLElement).dataset.visible = 'true';
    this.timer = window.setTimeout(() => appStore.dismissNotification(notification.id), 2200);
  }
}
