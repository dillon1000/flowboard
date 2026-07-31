import { Controller } from '@hotwired/stimulus';

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
    this.statusTarget.className = `badge status ${data.previewStatusClass ?? 'workflow-gray'}`;
    this.applyWorkflowColor(this.statusTarget, data.previewStatusColor);
    this.priorityTarget.textContent = data.previewPriority ?? '';
    this.priorityTarget.className = `badge ${data.previewPriorityClass ?? 'workflow-gray'}`;
    this.applyWorkflowColor(this.priorityTarget, data.previewPriorityColor);
    this.assigneeTarget.textContent = data.previewAssignee ?? '';
    this.dueTarget.textContent = data.previewDue ?? '';
    this.bodyTarget.textContent = data.previewBody ?? '';
    this.bodyTarget.hidden = !data.previewBody;

    this.cardTarget.hidden = false;
    this.position(anchor);
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
