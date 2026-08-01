import { Controller } from '@hotwired/stimulus';
import { autorun, type IReactionDisposer } from 'mobx';
import { appStore } from '../stores/app_store';

export class ThemeController extends Controller {
  static targets = ['label'];

  declare readonly hasLabelTarget: boolean;
  declare readonly labelTarget: HTMLElement;
  private stopObserving?: IReactionDisposer;
  private darkModeQuery?: MediaQueryList;

  connect(): void {
    this.darkModeQuery = matchMedia('(prefers-color-scheme: dark)');
    appStore.setSystemTheme(this.darkModeQuery.matches);
    this.darkModeQuery.addEventListener('change', this.handleSystemThemeChange);
    window.addEventListener('storage', this.handleStorageChange);
    document.addEventListener('turbo:render', this.handleTurboRender);
    this.stopObserving = autorun(() => this.apply(appStore.theme));
  }

  disconnect(): void {
    this.darkModeQuery?.removeEventListener('change', this.handleSystemThemeChange);
    window.removeEventListener('storage', this.handleStorageChange);
    document.removeEventListener('turbo:render', this.handleTurboRender);
    this.stopObserving?.();
  }

  labelTargetConnected(element: HTMLElement): void {
    element.textContent = this.themeLabel(appStore.theme);
  }

  toggle(): void {
    appStore.toggleTheme();
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

  private readonly handleSystemThemeChange = (event: MediaQueryListEvent): void => {
    appStore.setSystemTheme(event.matches);
  };

  private readonly handleStorageChange = (event: StorageEvent): void => {
    appStore.syncStoredPreference(event.key, event.newValue);
  };

  // Turbo retains the root element, so refresh theme-dependent controls after it replaces the body.
  private readonly handleTurboRender = (): void => {
    this.apply(appStore.theme);
  };
}

export class SidebarController extends Controller {
  static targets = ['panel', 'scrim', 'collapseLabel', 'brandLogo'];

  declare readonly panelTarget: HTMLElement;
  declare readonly scrimTarget: HTMLElement;
  declare readonly collapseLabelTargets: HTMLElement[];
  declare readonly brandLogoTargets: HTMLImageElement[];
  private stopObserving?: IReactionDisposer;

  connect(): void {
    document.addEventListener('turbo:render', this.handleTurboRender);
    this.stopObserving = autorun(() => {
      this.applyCollapsed(appStore.sidebarCollapsed);
      this.applyOpen(appStore.sidebarOpen);
    });
  }

  disconnect(): void {
    document.removeEventListener('turbo:render', this.handleTurboRender);
    this.stopObserving?.();
    appStore.closeSidebar();
  }

  collapseLabelTargetConnected(element: HTMLElement): void {
    element.textContent = this.collapseLabel(appStore.sidebarCollapsed);
  }

  // Mobile drawer.
  open(): void {
    appStore.openSidebar();
  }

  close(): void {
    appStore.closeSidebar();
  }

  // Desktop rail. Below the drawer breakpoint the same button opens the drawer,
  // so collapsing is only meaningful when the sidebar is docked.
  toggleCollapse(): void {
    if (matchMedia('(width <= 820px)').matches) {
      this.open();
      return;
    }
    appStore.toggleSidebarCollapsed();
  }

  shortcut(event: KeyboardEvent): void {
    if (event.key.toLowerCase() !== 'b' || !(event.metaKey || event.ctrlKey)) {
      return;
    }
    event.preventDefault();
    this.toggleCollapse();
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

  private applyOpen(open: boolean): void {
    if (open) {
      this.panelTarget.dataset.open = 'true';
    } else {
      delete this.panelTarget.dataset.open;
    }
    this.scrimTarget.hidden = !open;
    document.body.classList.toggle('no-scroll', open);
  }

  // Turbo morphs retained controls after MobX has rendered, so this refreshes
  // their labels and images from the current observable state.
  private readonly handleTurboRender = (): void => {
    this.applyCollapsed(appStore.sidebarCollapsed);
    this.applyOpen(appStore.sidebarOpen);
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
