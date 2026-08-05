/**
 * Marks a horizontal scroller with the fade edges that are currently useful.
 * The action observes size and scroll changes, and removes its listeners when
 * Svelte destroys the node. CSS uses the data attributes to draw each fade.
 */
export function scrollFades(node: HTMLElement): { destroy: () => void } {
  const update = (): void => {
    const overflow = node.scrollWidth - node.clientWidth;
    node.dataset.scrollLeft = node.scrollLeft > 2 ? 'true' : 'false';
    node.dataset.scrollRight = overflow - node.scrollLeft > 2 ? 'true' : 'false';
  };

  const observer = new ResizeObserver(update);
  observer.observe(node);
  node.addEventListener('scroll', update, { passive: true });
  requestAnimationFrame(update);

  return {
    destroy: () => {
      observer.disconnect();
      node.removeEventListener('scroll', update);
    }
  };
}
