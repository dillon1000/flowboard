import { Controller } from '@hotwired/stimulus';

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
