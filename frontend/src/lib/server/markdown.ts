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
      'img',
      'hr',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'del',
      'table',
      'thead',
      'tbody',
      'tfoot',
      'tr',
      'th',
      'td'
    ],
    allowedAttributes: {
      a: ['href', 'title', 'target', 'rel'],
      img: ['src', 'alt', 'title'],
      th: ['align'],
      td: ['align']
    },
    transformTags: {
      a: (_tagName, attributes) => ({
        tagName: 'a',
        attribs: { ...attributes, target: '_blank', rel: 'noopener noreferrer' }
      })
    },
    allowedSchemes: ['http', 'https', 'mailto']
  });
}
