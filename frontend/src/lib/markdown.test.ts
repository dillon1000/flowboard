import { describe, expect, it } from 'vitest';
import { renderMarkdown } from './markdown';

describe('renderMarkdown', () => {
  it('renders the supported task formatting', () => {
    const result = renderMarkdown('# Release notes\n\n- **Ready**');

    expect(result).toContain('<h1>Release notes</h1>');
    expect(result).toContain('<li><strong>Ready</strong></li>');
  });

  it('removes scripts and unsafe link schemes', () => {
    const result = renderMarkdown(
      '<script>alert("xss")</script>\n\n[unsafe](javascript:alert(1))'
    );

    expect(result).not.toContain('<script');
    expect(result).not.toContain('javascript:');
  });

  it('keeps safe external links', () => {
    expect(renderMarkdown('[Guide](https://example.com/guide)')).toContain(
      'href="https://example.com/guide"'
    );
  });
});
