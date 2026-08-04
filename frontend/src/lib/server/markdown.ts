import { marked } from 'marked';
import sanitizeHtml from 'sanitize-html';

/** Converts user Markdown to the safe HTML subset sent in SSR page data. */
export function renderMarkdown(value: string): string {
  const rendered = marked.parse(value, { async: false }) as string;
  return sanitizeHtml(rendered, {
    allowedTags: [
      'p',
      'br',
      'strong',
      'em',
      'code',
      'pre',
      'ul',
      'ol',
      'li',
      'blockquote',
      'a',
      'h1',
      'h2',
      'h3'
    ],
    allowedAttributes: { a: ['href', 'title', 'target', 'rel'] },
    allowedSchemes: ['http', 'https', 'mailto']
  });
}
