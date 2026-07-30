import { Controller } from '@hotwired/stimulus';
import confetti from 'canvas-confetti';
import flatpickr from 'flatpickr';
import type { Instance as FlatpickrInstance } from 'flatpickr/dist/types/instance';
import Sortable, { type SortableEvent } from 'sortablejs';

// DONE_STATUS mirrors TaskStatus.done on the server. The event and storage keys
// carry the completion signal across both direct board moves and Turbo redirects.
const DONE_STATUS = 'done';
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
    if (form.dataset.completionStatus !== DONE_STATUS && nextStatus === DONE_STATUS) {
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

const SIDEBAR_STORAGE_KEY = 'flowboard-sidebar';

export class SidebarController extends Controller {
  static targets = ['panel', 'scrim', 'collapseLabel', 'brandLogo'];

  declare readonly panelTarget: HTMLElement;
  declare readonly scrimTarget: HTMLElement;
  declare readonly collapseLabelTargets: HTMLElement[];
  declare readonly brandLogoTargets: HTMLImageElement[];

  connect(): void {
    document.addEventListener('turbo:render', this.handleTurboRender);
    this.applyCollapsed(this.savedCollapsed());
  }

  disconnect(): void {
    document.removeEventListener('turbo:render', this.handleTurboRender);
  }

  collapseLabelTargetConnected(element: HTMLElement): void {
    element.textContent = this.collapseLabel(this.savedCollapsed());
  }

  // Mobile drawer.
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

  // Desktop rail. Below the drawer breakpoint the same button opens the drawer,
  // so collapsing is only meaningful when the sidebar is docked.
  toggleCollapse(): void {
    if (matchMedia('(width <= 820px)').matches) {
      this.open();
      return;
    }
    const next = !this.savedCollapsed();
    localStorage.setItem(SIDEBAR_STORAGE_KEY, next ? 'collapsed' : 'expanded');
    this.applyCollapsed(next);
  }

  shortcut(event: KeyboardEvent): void {
    if (event.key.toLowerCase() !== 'b' || !(event.metaKey || event.ctrlKey)) {
      return;
    }
    event.preventDefault();
    this.toggleCollapse();
  }

  private savedCollapsed(): boolean {
    return localStorage.getItem(SIDEBAR_STORAGE_KEY) === 'collapsed';
  }

  private applyCollapsed(collapsed: boolean): void {
    document.documentElement.dataset.sidebar = collapsed ? 'collapsed' : 'expanded';
    this.collapseLabelTargets.forEach((element) => {
      element.textContent = this.collapseLabel(collapsed);
    });
    this.brandLogoTargets.forEach((element) => {
      this.updateBrandLogo(element, collapsed);
    });
  }

  // One image owns both brand states, so a stale stylesheet cannot expose two
  // logos. Missing data keeps the current source instead of breaking the mark.
  private updateBrandLogo(element: HTMLImageElement, collapsed: boolean): void {
    const source = collapsed ? element.dataset.abbreviationSrc : element.dataset.wordmarkSrc;
    if (source) {
      element.setAttribute('src', source);
    }
    element.width = collapsed ? 24 : 104;
    element.height = 14;
  }

  private collapseLabel(collapsed: boolean): string {
    return collapsed ? 'Expand sidebar' : 'Collapse sidebar';
  }

  // Turbo replaces the body, so re-assert the rail state after every render.
  private readonly handleTurboRender = (): void => {
    this.applyCollapsed(this.savedCollapsed());
  };
}

// Derives checklist progress from the rendered items so the server does not
// have to supply a second, redundant count.
export class ChecklistController extends Controller {
  static targets = ['item', 'bar', 'label'];

  declare readonly itemTargets: HTMLElement[];
  declare readonly barTarget: HTMLProgressElement;
  declare readonly labelTarget: HTMLElement;
  declare readonly hasBarTarget: boolean;
  declare readonly hasLabelTarget: boolean;

  connect(): void {
    this.render();
  }

  itemTargetConnected(): void {
    this.render();
  }

  itemTargetDisconnected(): void {
    this.render();
  }

  private render(): void {
    const total = this.itemTargets.length;
    const done = this.itemTargets.filter((item) => item.classList.contains('completed')).length;
    if (this.hasBarTarget) {
      this.barTarget.max = Math.max(total, 1);
      this.barTarget.value = done;
    }
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = total ? `${done} of ${total}` : 'No items';
    }
  }
}

// Shows the chosen filename next to a file button, which is otherwise silent.
export class FileFieldController extends Controller {
  static targets = ['input', 'name'];

  declare readonly inputTarget: HTMLInputElement;
  declare readonly nameTarget: HTMLElement;

  choose(): void {
    const file = this.inputTarget.files?.[0];
    this.nameTarget.textContent = file ? file.name : 'No file chosen';
  }
}

// Renders a deliberately small Markdown subset. Input is escaped first, so no
// author-supplied HTML can survive — the renderer only ever adds its own tags.
function escapeHTML(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function renderInline(text: string): string {
  return text
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|\W)_([^_]+)_(?=\W|$)/g, '$1<em>$2</em>')
    .replace(/\*([^*]+)\*/g, '<em>$1</em>')
    .replace(/~~([^~]+)~~/g, '<del>$1</del>')
    // Only http(s) links are linkified; anything else stays literal text.
    .replace(
      /\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g,
      '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>',
    );
}

export function renderMarkdown(source: string): string {
  const lines = escapeHTML(source).split('\n');
  const out: string[] = [];
  let list: 'ul' | 'ol' | null = null;
  let paragraph: string[] = [];
  let fence: string[] | null = null;

  const closeList = (): void => {
    if (list) {
      out.push(`</${list}>`);
      list = null;
    }
  };
  const closeParagraph = (): void => {
    if (paragraph.length) {
      out.push(`<p>${renderInline(paragraph.join('<br>'))}</p>`);
      paragraph = [];
    }
  };
  const closeAll = (): void => {
    closeParagraph();
    closeList();
  };

  for (const line of lines) {
    if (line.trimStart().startsWith('```')) {
      if (fence) {
        out.push(`<pre><code>${fence.join('\n')}</code></pre>`);
        fence = null;
      } else {
        closeAll();
        fence = [];
      }
      continue;
    }
    if (fence) {
      fence.push(line);
      continue;
    }

    if (!line.trim()) {
      closeAll();
      continue;
    }

    const heading = /^(#{1,4})\s+(.*)$/.exec(line);
    if (heading) {
      closeAll();
      const level = heading[1].length + 1;
      out.push(`<h${level}>${renderInline(heading[2])}</h${level}>`);
      continue;
    }

    if (/^(-{3,}|\*{3,})$/.test(line.trim())) {
      closeAll();
      out.push('<hr>');
      continue;
    }

    // The line is already escaped, so a blockquote marker reads as &gt;.
    const quote = /^&gt;\s?(.*)$/.exec(line);
    if (quote) {
      closeAll();
      out.push(`<blockquote>${renderInline(quote[1])}</blockquote>`);
      continue;
    }

    const bullet = /^\s*[-*+]\s+(.*)$/.exec(line);
    const ordered = /^\s*\d+\.\s+(.*)$/.exec(line);
    if (bullet || ordered) {
      closeParagraph();
      const wanted = bullet ? 'ul' : 'ol';
      if (list !== wanted) {
        closeList();
        out.push(`<${wanted}>`);
        list = wanted;
      }
      out.push(`<li>${renderInline((bullet ?? ordered)![1])}</li>`);
      continue;
    }

    closeList();
    paragraph.push(line.trim());
  }

  if (fence) {
    out.push(`<pre><code>${fence.join('\n')}</code></pre>`);
  }
  closeAll();
  return out.join('');
}

export class MarkdownController extends Controller {
  connect(): void {
    const source = this.element.textContent ?? '';
    if (!source.trim()) {
      return;
    }
    this.element.innerHTML = renderMarkdown(source);
  }
}

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

  connect(): void {
    if (matchMedia('(hover: none)').matches) {
      return;
    }
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
    this.cardTarget.hidden = true;
    delete this.cardTarget.dataset.open;
  };

  private show(anchor: HTMLElement): void {
    const data = anchor.dataset;
    this.titleTarget.textContent = data.previewTitle ?? '';
    this.boardTarget.textContent = data.previewBoard ?? '';
    this.boardTarget.hidden = !data.previewBoard;
    this.statusTarget.textContent = data.previewStatus ?? '';
    this.statusTarget.className = `badge status status-${data.previewStatusValue ?? 'backlog'}`;
    this.priorityTarget.textContent = data.previewPriority ?? '';
    this.priorityTarget.className = `badge priority-${data.previewPriorityValue ?? 'low'}`;
    this.assigneeTarget.textContent = data.previewAssignee ?? '';
    this.dueTarget.textContent = data.previewDue ?? '';
    this.bodyTarget.textContent = data.previewBody ?? '';
    this.bodyTarget.hidden = !data.previewBody;

    this.cardTarget.hidden = false;
    this.position(anchor);
    this.cardTarget.dataset.open = 'true';
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

export class MenuController extends Controller {
  static targets = ['trigger', 'panel', 'input', 'value', 'option'];

  declare readonly triggerTarget: HTMLButtonElement;
  declare readonly panelTarget: HTMLElement;
  declare readonly inputTarget: HTMLInputElement;
  declare readonly valueTarget: HTMLElement;
  declare readonly hasValueTarget: boolean;
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
    if (this.hasValueTarget) {
      this.valueTarget.textContent = label;
    }
    this.optionTargets.forEach((item) => {
      item.setAttribute('aria-selected', String(item === option));
    });
    this.inputTarget.dispatchEvent(new Event('change', { bubbles: true }));
    this.close();
    // Status popovers opt in to immediate submission. Other menus keep their
    // current behavior and only update the surrounding form field.
    if (this.element instanceof HTMLFormElement && this.element.dataset.submitOnChoose === 'true') {
      this.element.requestSubmit();
    }
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
      dragClass: 'task-card-drag',
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
    const sourceColumn = event.from as HTMLElement;
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
      if (sourceColumn.dataset.status !== DONE_STATUS && status === DONE_STATUS) {
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
