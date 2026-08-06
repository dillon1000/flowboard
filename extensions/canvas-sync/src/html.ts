/** Converts Canvas HTML to readable text while preserving useful block breaks. */
export function canvasHTMLToText(html: string | null | undefined): string | null {
  if (!html?.trim()) return null;
  const document = new DOMParser().parseFromString(html, 'text/html');
  document.querySelectorAll('script, style, noscript, template').forEach((node) => node.remove());
  document.querySelectorAll('br').forEach((node) => node.replaceWith(document.createTextNode('\n')));
  document.querySelectorAll('p, div, li, h1, h2, h3, h4, h5, h6, blockquote, pre').forEach((node) => {
    node.append(document.createTextNode('\n'));
  });
  const text = (document.body.textContent ?? '')
    .replace(/\u00a0/g, ' ')
    .split('\n')
    .map((line) => line.replace(/[\t ]+/g, ' ').trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim()
    .slice(0, 5_000)
    .trimEnd();
  return text || null;
}
