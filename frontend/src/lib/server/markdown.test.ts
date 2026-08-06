import { describe, expect, it } from 'vitest';
import { renderMarkdown } from './markdown';

describe('server renderMarkdown', () => {
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
    const result = renderMarkdown(
      '<a href="https://example.com/guide" target="named-frame" rel="opener">Guide</a>'
    );

    expect(result).toContain('href="https://example.com/guide"');
    expect(result).toContain('target="_blank"');
    expect(result).toContain('rel="noopener noreferrer"');
    expect(result).not.toContain('named-frame');
    expect(result).not.toContain('rel="opener"');
  });

  it('renders tables, images, rules, headings, and deleted text', () => {
    const result = renderMarkdown(
      '| Day | Topic |\n| --- | --- |\n| Mon | Algebra |\n\n' +
        '![Course diagram](https://example.com/diagram.png)\n\n---\n\n#### Notes\n\n~~Canceled~~'
    );

    expect(result).toContain('<table>');
    expect(result).toContain('<th>Day</th>');
    expect(result).toContain('<td>Algebra</td>');
    expect(result).toContain(
      '<img src="https://example.com/diagram.png" alt="Course diagram" />'
    );
    expect(result).toContain('<hr />');
    expect(result).toContain('<h4>Notes</h4>');
    expect(result).toContain('<del>Canceled</del>');
  });
});
