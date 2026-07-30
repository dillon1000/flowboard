import { Controller } from '@hotwired/stimulus';
import flatpickr from 'flatpickr';
import type { Instance as FlatpickrInstance } from 'flatpickr/dist/types/instance';
import Sortable, { type SortableEvent } from 'sortablejs';

export class ThemeController extends Controller {
  static targets = ['label'];

  declare readonly hasLabelTarget: boolean;
  declare readonly labelTarget: HTMLElement;

  connect(): void {
    document.addEventListener('turbo:render', this.handleTurboRender);
    this.apply(this.savedTheme());
  }

  disconnect(): void {
    document.removeEventListener('turbo:render', this.handleTurboRender);
  }

  labelTargetConnected(element: HTMLElement): void {
    element.textContent = this.themeLabel(this.savedTheme());
  }

  toggle(): void {
    const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    localStorage.setItem('flowboard-theme', next);
    this.apply(next);
  }

  private savedTheme(): 'light' | 'dark' {
    const stored = localStorage.getItem('flowboard-theme');
    if (stored === 'light' || stored === 'dark') {
      return stored;
    }
    return matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  private apply(theme: 'light' | 'dark'): void {
    document.documentElement.dataset.theme = theme;
    document.documentElement.style.colorScheme = theme;
    document.querySelector<HTMLMetaElement>('meta[name="theme-color"]')
      ?.setAttribute('content', theme === 'dark' ? '#0a0a0a' : '#ffffff');
    this.updateLabel(theme);
  }

  private updateLabel(theme: 'light' | 'dark'): void {
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = this.themeLabel(theme);
    }
  }

  private themeLabel(theme: 'light' | 'dark'): string {
    return theme === 'dark' ? 'Use light theme' : 'Use dark theme';
  }

  // Turbo retains the root element, so refresh theme-dependent controls after it replaces the body.
  private readonly handleTurboRender = (): void => {
    this.apply(this.savedTheme());
  };
}

export class SidebarController extends Controller {
  static targets = ['panel', 'scrim'];

  declare readonly panelTarget: HTMLElement;
  declare readonly scrimTarget: HTMLElement;

  open(): void {
    this.panelTarget.dataset.open = 'true';
    this.scrimTarget.hidden = false;
    document.body.classList.add('no-scroll');
  }

  close(): void {
    delete this.panelTarget.dataset.open;
    this.scrimTarget.hidden = true;
    document.body.classList.remove('no-scroll');
  }
}

export class MenuController extends Controller {
  static targets = ['trigger', 'panel', 'input', 'value', 'option'];

  declare readonly triggerTarget: HTMLButtonElement;
  declare readonly panelTarget: HTMLElement;
  declare readonly inputTarget: HTMLInputElement;
  declare readonly valueTarget: HTMLElement;
  declare readonly optionTargets: HTMLElement[];

  connect(): void {
    this.element.addEventListener('keydown', this.handleKeydown);
  }

  disconnect(): void {
    this.element.removeEventListener('keydown', this.handleKeydown);
  }

  toggle(event: Event): void {
    event.stopPropagation();
    this.panelTarget.hidden ? this.open() : this.close();
  }

  choose(event: Event): void {
    const option = event.currentTarget as HTMLElement;
    const value = option.dataset.value ?? '';
    const label = option.dataset.label ?? option.textContent?.trim() ?? '';
    this.inputTarget.value = value;
    this.valueTarget.textContent = label;
    this.optionTargets.forEach((item) => {
      item.setAttribute('aria-selected', String(item === option));
    });
    this.inputTarget.dispatchEvent(new Event('change', { bubbles: true }));
    this.close();
  }

  outside(event: Event): void {
    if (!this.element.contains(event.target as Node)) {
      this.close();
    }
  }

  close(): void {
    this.panelTarget.hidden = true;
    this.triggerTarget.setAttribute('aria-expanded', 'false');
  }

  private open(): void {
    this.panelTarget.hidden = false;
    this.triggerTarget.setAttribute('aria-expanded', 'true');
    this.optionTargets.find((option) => option.getAttribute('aria-selected') === 'true')?.focus();
  }

  private handleKeydown = (event: Event): void => {
    const keyboardEvent = event as KeyboardEvent;
    if (keyboardEvent.key !== 'ArrowDown' && keyboardEvent.key !== 'ArrowUp') {
      return;
    }
    keyboardEvent.preventDefault();
    if (this.panelTarget.hidden) {
      this.open();
      return;
    }
    const currentIndex = this.optionTargets.indexOf(document.activeElement as HTMLElement);
    const delta = keyboardEvent.key === 'ArrowDown' ? 1 : -1;
    const nextIndex = (currentIndex + delta + this.optionTargets.length) % this.optionTargets.length;
    this.optionTargets[nextIndex]?.focus();
  };
}

export class DialogController extends Controller {
  static targets = ['panel', 'initial'];

  declare readonly panelTarget: HTMLElement;
  declare readonly hasInitialTarget: boolean;
  declare readonly initialTarget: HTMLElement;

  open(): void {
    this.panelTarget.hidden = false;
    document.body.classList.add('no-scroll');
    requestAnimationFrame(() => {
      this.panelTarget.dataset.open = 'true';
      (this.hasInitialTarget ? this.initialTarget : this.panelTarget).focus();
    });
  }

  close(): void {
    delete this.panelTarget.dataset.open;
    document.body.classList.remove('no-scroll');
    setTimeout(() => {
      this.panelTarget.hidden = true;
    }, 120);
  }

  backdrop(event: Event): void {
    if (event.target === this.panelTarget) {
      this.close();
    }
  }
}

export class DatePickerController extends Controller {
  static targets = ['input'];

  declare readonly inputTarget: HTMLInputElement;
  private picker?: FlatpickrInstance;

  connect(): void {
    this.picker = flatpickr(this.inputTarget, {
      allowInput: false,
      altInput: true,
      altFormat: 'M j, Y',
      dateFormat: 'Y-m-d',
      disableMobile: true,
      monthSelectorType: 'static',
      nextArrow: '<span aria-hidden="true">→</span>',
      prevArrow: '<span aria-hidden="true">←</span>',
    });
  }

  disconnect(): void {
    this.picker?.destroy();
  }

  clear(): void {
    this.picker?.clear();
  }
}

export class BoardController extends Controller {
  static targets = ['column'];
  static values = { editable: Boolean };

  declare readonly columnTargets: HTMLElement[];
  declare readonly editableValue: boolean;
  private sortables: Sortable[] = [];

  connect(): void {
    if (!this.editableValue) {
      return;
    }
    this.sortables = this.columnTargets.map((column) => new Sortable(column, {
      animation: 140,
      draggable: '[data-task-id]',
      ghostClass: 'task-card-ghost',
      group: 'flowboard-tasks',
      onEnd: (event) => void this.persistMove(event),
    }));
  }

  disconnect(): void {
    this.sortables.forEach((sortable) => sortable.destroy());
  }

  private async persistMove(event: SortableEvent): Promise<void> {
    const task = event.item as HTMLElement;
    const column = event.to as HTMLElement;
    const taskID = task.dataset.taskId;
    const status = column.dataset.status;
    if (!taskID || !status) {
      window.location.reload();
      return;
    }

    try {
      const response = await fetch(`/api/v1/tasks/${taskID}/move`, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-TOKEN': document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '',
        },
        body: JSON.stringify({ status, targetIndex: event.newIndex ?? 0 }),
      });
      if (!response.ok) {
        throw new Error('The task move was rejected.');
      }
      window.dispatchEvent(new CustomEvent('flowboard:notify', {
        detail: { message: 'Task moved' },
      }));
    } catch {
      window.location.reload();
    }
  }
}

export class ToastController extends Controller {
  static targets = ['message'];

  declare readonly messageTarget: HTMLElement;
  private timer?: number;

  show(event: Event): void {
    const detail = (event as CustomEvent<{ message: string }>).detail;
    this.messageTarget.textContent = detail.message;
    this.element.removeAttribute('hidden');
    (this.element as HTMLElement).dataset.visible = 'true';
    window.clearTimeout(this.timer);
    this.timer = window.setTimeout(() => {
      delete (this.element as HTMLElement).dataset.visible;
      this.element.setAttribute('hidden', '');
    }, 2200);
  }
}

export class SearchController extends Controller {
  static targets = ['input'];

  declare readonly inputTarget: HTMLInputElement;

  shortcut(event: Event): void {
    const keyboardEvent = event as KeyboardEvent;
    if (keyboardEvent.key.toLowerCase() === 'k' && (keyboardEvent.metaKey || keyboardEvent.ctrlKey)) {
      keyboardEvent.preventDefault();
      this.inputTarget.focus();
      this.inputTarget.select();
    }
    if (keyboardEvent.key === 'Escape' && document.activeElement === this.inputTarget) {
      this.inputTarget.blur();
    }
  }
}
