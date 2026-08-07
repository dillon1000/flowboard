/**
 * Reveal highlight — the Fluent Design effect from Windows 10.
 *
 * The rim of the surface under the pointer catches a soft radial highlight, and
 * so do the rims of its close neighbours. Those neighbours are what make a lane
 * of cards read as a set of panes lit from one moving source rather than a row
 * of hover states. Nothing lights up inside a surface — edges only.
 *
 * One document listener drives every surface. Only the hovered element and the
 * siblings close enough to catch light are measured, and their rects are cached
 * until the page scrolls or resizes, so a pointer move costs one animation frame
 * and a handful of custom-property writes.
 *
 * Keep the selector below in step with the one in styles/reveal.css.
 */

/** Surfaces that catch the light. Disabled controls are excluded. */
export const REVEAL_SELECTOR = [
  '.button:not(:disabled)',
  '.card',
  '.panel',
  '.stat',
  '.lane-card',
  '.board-card',
  '.study-assignment',
  '.study-focus-chip',
  '.study-unplanned',
  '.study-unplanned-list button:not(:disabled)',
  '.study-workflow-band',
  '.settings-menu .nav-link',
  '.user-row'
].join(',');

/** How far light spills onto a neighbouring rim, in pixels. */
const REACH = 260;

type Tracked = { element: HTMLElement; rect: DOMRect };

/** Squared edge-to-edge distance between two rects, zero when they overlap. */
function gapSquared(rect: DOMRect, anchor: DOMRect): number {
  const x = Math.max(rect.left - anchor.right, anchor.left - rect.right, 0);
  const y = Math.max(rect.top - anchor.bottom, anchor.top - rect.bottom, 0);
  return x * x + y * y;
}

export function startPointerReveal(): () => void {
  // Touch and pen have no hover, and a highlight that only appears mid-tap is
  // noise. Reduced motion opts out of the pointer-tracking entirely.
  if (
    !matchMedia('(hover: hover) and (pointer: fine)').matches ||
    matchMedia('(prefers-reduced-motion: reduce)').matches
  ) {
    return () => {};
  }

  let hovered: HTMLElement | null = null;
  let tracked: Tracked[] = [];
  let stale = false;
  let pointerX = 0;
  let pointerY = 0;
  let frame = 0;

  const paint = (): void => {
    frame = 0;
    if (stale) {
      for (const entry of tracked) entry.rect = entry.element.getBoundingClientRect();
      stale = false;
    }
    for (const { element, rect } of tracked) {
      element.style.setProperty('--reveal-x', `${pointerX - rect.left}px`);
      element.style.setProperty('--reveal-y', `${pointerY - rect.top}px`);
    }
  };

  const schedule = (): void => {
    if (!frame && tracked.length) frame = requestAnimationFrame(paint);
  };

  const release = (): void => {
    for (const { element } of tracked) {
      element.removeAttribute('data-reveal');
      element.style.removeProperty('--reveal-x');
      element.style.removeProperty('--reveal-y');
    }
    tracked = [];
    hovered = null;
  };

  const enter = (element: HTMLElement): void => {
    release();
    hovered = element;
    const anchor = element.getBoundingClientRect();
    tracked = [{ element, rect: anchor }];
    element.dataset.reveal = '';

    // Gradient falloff already makes the hovered rim the brightest, so a
    // neighbour is lit the same way — it just sits further from the light.
    for (const sibling of element.parentElement?.children ?? []) {
      if (!(sibling instanceof HTMLElement) || sibling === element) continue;
      if (!sibling.matches(REVEAL_SELECTOR)) continue;
      const rect = sibling.getBoundingClientRect();
      if (gapSquared(rect, anchor) > REACH * REACH) continue;
      sibling.dataset.reveal = '';
      tracked.push({ element: sibling, rect });
    }
  };

  const handleMove = (event: PointerEvent): void => {
    const target =
      event.target instanceof Element ? event.target.closest(REVEAL_SELECTOR) : null;
    if (target !== hovered) {
      if (target instanceof HTMLElement) enter(target);
      else release();
    }
    pointerX = event.clientX;
    pointerY = event.clientY;
    schedule();
  };

  // Scrolling moves the surfaces out from under a stationary pointer, so the
  // cached rects have to go — including for scrollers nested in the page.
  const handleShift = (): void => {
    stale = true;
    schedule();
  };

  document.addEventListener('pointermove', handleMove, { passive: true });
  document.addEventListener('pointerleave', release);
  document.addEventListener('scroll', handleShift, { capture: true, passive: true });
  window.addEventListener('resize', handleShift, { passive: true });
  window.addEventListener('blur', release);

  return () => {
    if (frame) cancelAnimationFrame(frame);
    release();
    document.removeEventListener('pointermove', handleMove);
    document.removeEventListener('pointerleave', release);
    document.removeEventListener('scroll', handleShift, { capture: true });
    window.removeEventListener('resize', handleShift);
    window.removeEventListener('blur', release);
  };
}
