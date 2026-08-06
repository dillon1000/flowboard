<script lang="ts">
  import DOMPurify from 'dompurify';
  import { marked } from 'marked';
  import { tick } from 'svelte';

  let {
    id,
    name,
    value = $bindable(''),
    label,
    placeholder = '',
    maxLength = 5000
  } = $props<{
    id: string;
    name: string;
    value?: string;
    label: string;
    placeholder?: string;
    maxLength?: number;
  }>();

  let textarea = $state<HTMLTextAreaElement>();
  let previewOpen = $state(false);
  const previewHTML = $derived.by(() => {
    const rendered = marked.parse(value, { async: false }) as string;
    const sanitized = DOMPurify.sanitize(rendered, {
      ALLOWED_TAGS: [
        'p', 'br', 'strong', 'em', 'code', 'pre', 'ul', 'ol', 'li', 'blockquote', 'a',
        'img', 'hr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'del', 'table', 'thead',
        'tbody', 'tfoot', 'tr', 'th', 'td'
      ],
      ALLOWED_ATTR: ['href', 'title', 'src', 'alt', 'align']
    });
    return sanitized.replaceAll('<a ', '<a target="_blank" rel="noopener noreferrer" ');
  });

  /** Inserts a Markdown pair around the selection and leaves the replacement selected. */
  async function wrapSelection(before: string, after: string, fallback: string): Promise<void> {
    const field = textarea;
    if (!field) return;
    const start = field.selectionStart;
    const end = field.selectionEnd;
    const selected = value.slice(start, end) || fallback;
    value = `${value.slice(0, start)}${before}${selected}${after}${value.slice(end)}`;
    await tick();
    field.focus();
    field.setSelectionRange(start + before.length, start + before.length + selected.length);
  }

  /** Inserts a complete Markdown block at the cursor and selects its editable example text. */
  async function insertBlock(block: string, selectionStart: number, selectionLength: number): Promise<void> {
    const field = textarea;
    if (!field) return;
    const start = field.selectionStart;
    const prefix = start > 0 && value[start - 1] !== '\n' ? '\n\n' : '';
    const suffix = start < value.length && value[start] !== '\n' ? '\n\n' : '';
    value = `${value.slice(0, start)}${prefix}${block}${suffix}${value.slice(start)}`;
    await tick();
    field.focus();
    const selection = start + prefix.length + selectionStart;
    field.setSelectionRange(selection, selection + selectionLength);
  }

</script>

<div class="markdown-editor">
  <div class="markdown-tabs" role="tablist" aria-label={`${label} mode`}>
    <button class:active={!previewOpen} type="button" role="tab" aria-selected={!previewOpen} onclick={() => (previewOpen = false)}>Write</button>
    <button class:active={previewOpen} type="button" role="tab" aria-selected={previewOpen} onclick={() => (previewOpen = true)}>Preview</button>
  </div>
  {#if previewOpen}
    <input type="hidden" {name} {value} />
    <div class="markdown-preview markdown" role="tabpanel" tabindex="0">
      {#if value.trim()}{@html previewHTML}{:else}<p class="markdown-empty">Nothing to preview yet.</p>{/if}
    </div>
  {:else}
    <div class="markdown-toolbar" aria-label="Markdown formatting">
      <button type="button" title="Bold" aria-label="Bold" onclick={() => wrapSelection('**', '**', 'bold text')}><strong>B</strong></button>
      <button type="button" title="Italic" aria-label="Italic" onclick={() => wrapSelection('*', '*', 'italic text')}><em>I</em></button>
      <button type="button" title="Link" aria-label="Link" onclick={() => wrapSelection('[', '](https://)', 'link text')}>Link</button>
      <button type="button" title="Bulleted list" aria-label="Bulleted list" onclick={() => insertBlock('- List item', 2, 9)}>List</button>
      <button type="button" title="Table" aria-label="Table" onclick={() => insertBlock('| Column | Column |\n| --- | --- |\n| Value | Value |', 2, 6)}>Table</button>
      <button type="button" title="Image" aria-label="Image" onclick={() => wrapSelection('![', '](https://)', 'image description')}>Image</button>
    </div>
    <textarea bind:this={textarea} class="textarea" {id} {name} bind:value maxlength={maxLength} {placeholder} aria-label={label}></textarea>
  {/if}
  <span class="markdown-help">Supports headings, bold, italic, links, lists, quotes, code, tables, images, rules, and strikethrough.</span>
</div>

<style>
  .markdown-editor {
    display: grid;
    min-width: 0;
  }

  .markdown-tabs,
  .markdown-toolbar {
    display: flex;
    align-items: center;
    gap: 3px;
  }

  .markdown-tabs {
    margin-bottom: 6px;
  }

  .markdown-tabs button,
  .markdown-toolbar button {
    border: 0;
    color: var(--text-muted);
    background: transparent;
    font: inherit;
    cursor: pointer;
  }

  .markdown-tabs button {
    border-radius: 6px;
    padding: 5px 9px;
    font-size: 0.78rem;
    font-weight: 700;
  }

  .markdown-tabs button.active {
    color: var(--text);
    background: var(--surface-subtle);
  }

  .markdown-toolbar {
    flex-wrap: wrap;
    padding: 5px;
    border: 1px solid var(--border-strong);
    border-bottom: 0;
    border-radius: 8px 8px 0 0;
    background: var(--surface-subtle);
  }

  .markdown-toolbar button {
    min-height: 28px;
    padding: 3px 7px;
    border-radius: 5px;
    font-size: 0.76rem;
  }

  .markdown-toolbar button:hover,
  .markdown-toolbar button:focus-visible {
    color: var(--text);
    background: var(--surface);
  }

  textarea.textarea {
    min-height: 150px;
    border-radius: 0 0 8px 8px;
  }

  .markdown-preview {
    min-height: 150px;
    max-height: 420px;
    overflow: auto;
    padding: 12px;
    border: 1px solid var(--border-strong);
    border-radius: 8px;
    background: var(--surface);
  }

  .markdown-empty,
  .markdown-help {
    color: var(--text-muted);
  }

  .markdown-help {
    margin-top: 6px;
    font-size: 0.75rem;
    line-height: 1.4;
  }
</style>
