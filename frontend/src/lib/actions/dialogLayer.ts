const focusableSelector = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled]):not([type="hidden"])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])'
].join(',');

export interface DialogLayerOptions {
  close: () => void;
  closeOnBackdrop?: boolean;
}

// Multiple dialog components can exist in one page, so the shared count keeps
// body scrolling disabled until the final open dialog has closed.
let openDialogCount = 0;

function focusableElements(node: HTMLElement): HTMLElement[] {
  return Array.from(node.querySelectorAll<HTMLElement>(focusableSelector)).filter(
    (element) => !element.hidden && element.getClientRects().length > 0
  );
}

/**
 * Manages one modal layer. It opens the visual state, traps keyboard focus,
 * closes on Escape, locks page scrolling, and restores focus on destroy.
 */
export function dialogLayer(node: HTMLElement, options: DialogLayerOptions) {
  let currentOptions = options;
  const priorFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  openDialogCount += 1;
  document.body.classList.add('no-scroll');

  const focusFrame = requestAnimationFrame(() => {
    node.dataset.open = 'true';
    const requestedFocus = node.querySelector<HTMLElement>('[data-dialog-focus]');
    (requestedFocus ?? focusableElements(node)[0] ?? node).focus();
  });

  function handleKeydown(event: KeyboardEvent): void {
    if (event.key === 'Escape') {
      event.preventDefault();
      currentOptions.close();
      return;
    }
    if (event.key !== 'Tab') return;

    const elements = focusableElements(node);
    if (!elements.length) {
      event.preventDefault();
      node.focus();
      return;
    }

    const first = elements[0];
    const last = elements[elements.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  function handleClick(event: MouseEvent): void {
    if (currentOptions.closeOnBackdrop !== false && event.target === node) currentOptions.close();
  }

  node.addEventListener('keydown', handleKeydown);
  node.addEventListener('click', handleClick);

  return {
    update(nextOptions: DialogLayerOptions): void {
      currentOptions = nextOptions;
    },
    destroy(): void {
      cancelAnimationFrame(focusFrame);
      node.removeEventListener('keydown', handleKeydown);
      node.removeEventListener('click', handleClick);
      openDialogCount = Math.max(0, openDialogCount - 1);
      if (openDialogCount === 0) document.body.classList.remove('no-scroll');
      if (priorFocus?.isConnected) requestAnimationFrame(() => priorFocus.focus());
    }
  };
}
