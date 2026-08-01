import { Controller } from '@hotwired/stimulus';
import { autorun, type IReactionDisposer } from 'mobx';
import {
  appStore,
  type ChecklistItemSnapshot,
  type TaskPageState,
} from '../stores/app_store';

type TurboSubmitEndDetail = {
  success: boolean;
};

/**
 * Coordinates optimistic checklist updates and a navigation-safe comment draft.
 * The server response remains authoritative and failed checklist requests roll back.
 */
export class TaskPageController extends Controller {
  static targets = [
    'checklistBar',
    'checklistItem',
    'checklistLabel',
    'commentCount',
    'commentInput',
    'commentStatus',
    'commentSubmit',
  ];

  declare readonly checklistBarTarget: HTMLProgressElement;
  declare readonly checklistItemTargets: HTMLFormElement[];
  declare readonly checklistLabelTarget: HTMLElement;
  declare readonly commentCountTarget: HTMLElement;
  declare readonly commentInputTarget: HTMLTextAreaElement;
  declare readonly commentStatusTarget: HTMLElement;
  declare readonly commentSubmitTarget: HTMLButtonElement;
  declare readonly hasCommentCountTarget: boolean;
  declare readonly hasCommentInputTarget: boolean;
  declare readonly hasCommentStatusTarget: boolean;
  declare readonly hasCommentSubmitTarget: boolean;
  private stopObserving?: IReactionDisposer;
  private taskID?: string;

  connect(): void {
    const taskID = this.element.getAttribute('data-task-id');
    if (!taskID) {
      return;
    }

    this.taskID = taskID;
    this.loadTaskPageState();
    this.stopObserving = autorun(() => this.render(appStore.taskPage));
  }

  disconnect(): void {
    this.stopObserving?.();
  }

  refresh(): void {
    requestAnimationFrame(() => {
      if (this.element.isConnected) {
        this.loadTaskPageState();
      }
    });
  }

  toggleChecklist(event: SubmitEvent): void {
    const form = event.currentTarget as HTMLFormElement;
    const itemID = form.getAttribute('data-item-id');
    if (!itemID || !appStore.beginChecklistToggle(itemID)) {
      event.preventDefault();
    }
  }

  finishChecklistToggle(event: Event): void {
    const form = event.currentTarget as HTMLFormElement;
    const itemID = form.getAttribute('data-item-id');
    if (!itemID) {
      return;
    }

    const { success } = (event as CustomEvent<TurboSubmitEndDetail>).detail;
    appStore.finishChecklistToggle(itemID, success);
    if (!success) {
      appStore.showNotification('Checklist update failed');
    }
  }

  updateCommentDraft(event: Event): void {
    appStore.updateCommentDraft((event.currentTarget as HTMLTextAreaElement).value);
  }

  commentKeydown(event: KeyboardEvent): void {
    if (event.key !== 'Enter' || (!event.metaKey && !event.ctrlKey)) {
      return;
    }

    event.preventDefault();
    const form = this.commentInputTarget.form;
    if (form?.reportValidity()) {
      form.requestSubmit();
    }
  }

  finishComment(event: Event): void {
    const { success } = (event as CustomEvent<TurboSubmitEndDetail>).detail;
    if (success) {
      appStore.clearCommentDraft();
      appStore.showNotification('Comment posted');
    } else {
      appStore.showNotification('Comment was not posted');
    }
  }

  private loadTaskPageState(): void {
    if (!this.taskID) {
      return;
    }

    const checklistItems: ChecklistItemSnapshot[] = this.checklistItemTargets.flatMap((item) => {
      const id = item.getAttribute('data-item-id');
      return id ? [{ completed: item.dataset.completed === 'true', id }] : [];
    });
    appStore.enterTaskPage(this.taskID, checklistItems);
  }

  private render(state: TaskPageState): void {
    if (state.taskID !== this.taskID) {
      return;
    }

    const { completed, total } = appStore.checklistProgress;
    this.checklistBarTarget.max = Math.max(total, 1);
    this.checklistBarTarget.value = completed;
    this.checklistLabelTarget.textContent = total ? `${completed} of ${total}` : 'No items';

    this.checklistItemTargets.forEach((form) => {
      const itemID = form.getAttribute('data-item-id');
      const item = itemID ? state.checklistItems[itemID] : undefined;
      if (!item) {
        return;
      }

      form.classList.toggle('completed', item.completed);
      form.toggleAttribute('aria-busy', item.pending);
      form.dataset.pending = String(item.pending);
      const button = form.querySelector<HTMLButtonElement>('button[type="submit"]');
      button?.classList.toggle('checked', item.completed);
      if (button) {
        button.disabled = item.pending;
      }
    });

    if (!this.hasCommentInputTarget) {
      return;
    }

    if (this.commentInputTarget.value !== state.commentDraft) {
      this.commentInputTarget.value = state.commentDraft;
    }
    if (this.hasCommentCountTarget) {
      this.commentCountTarget.textContent = `${state.commentDraft.length} / 4000`;
    }
    if (this.hasCommentStatusTarget) {
      this.commentStatusTarget.textContent = state.commentDraft ? 'Draft saved in this tab' : '';
    }
    if (this.hasCommentSubmitTarget) {
      this.commentSubmitTarget.disabled = !state.commentDraft.trim();
    }
  }
}
