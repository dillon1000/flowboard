/**
 * Descriptions are stored as Markdown. Anywhere a description is previewed
 * rather than rendered — a lane card, a gallery brief — the raw syntax is
 * noise, so it is stripped down to the sentence underneath.
 */
export function plainSummary(markdown: string): string {
  return markdown
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`([^`]*)`/g, '$1')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/^\s{0,3}(#{1,6}|>|[-*+]|\d+\.)\s+/gm, '')
    .replace(/[*_~]{1,3}(?=\S)([\s\S]*?\S)[*_~]{1,3}/g, '$1')
    .replace(/\s+/g, ' ')
    .trim();
}
