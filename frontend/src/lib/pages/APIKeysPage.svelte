<script lang="ts">
  import { api, messageFor, refreshAll } from '$lib/api';
  import type { APIKeysPageContext, CreatedAPIKeyResponse } from '$lib/types';
  import { CheckIcon as Check, CopyIcon as Copy, KeyIcon as KeyRound, PlusIcon as Plus } from 'phosphor-svelte';
  import SettingsNavigation from '$lib/components/SettingsNavigation.svelte';
  import { showToast } from '$lib/ui/toast';

  let { keys } = $props<{ keys: APIKeysPageContext }>();
  let createdKeyOverride = $state('');
  let pending = $state(false);
  let requestError = $state('');
  let copied = $state(false);
  const createdKey = $derived(createdKeyOverride || keys.createdKey);

  async function createKey(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const name = String(new FormData(form).get('name') ?? '');
    pending = true;
    requestError = '';
    try {
      const created = await api<CreatedAPIKeyResponse>('/api/v1/auth/api-keys', {
        method: 'POST',
        body: JSON.stringify({ name, expiresAt: null })
      });
      createdKeyOverride = created.key;
      form.reset();
      await refreshAll();
      showToast('API key created');
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pending = false;
    }
  }

  async function revoke(keyID: string): Promise<void> {
    if (!confirm('Revoke this API key?')) return;
    pending = true;
    requestError = '';
    try {
      await api(`/api/v1/auth/api-keys/${keyID}`, { method: 'DELETE' });
      await refreshAll();
      showToast('API key revoked');
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pending = false;
    }
  }

  async function copyKey(): Promise<void> {
    requestError = '';
    try {
      await navigator.clipboard.writeText(createdKey);
      copied = true;
      showToast('API key copied');
      setTimeout(() => (copied = false), 1800);
    } catch (cause) {
      requestError = messageFor(cause);
    }
  }
</script>

<div class="page narrow">
  <header class="page-header"><div class="page-title"><h1>API keys</h1><p>Connect scripts and services to your Flowboard workspace.</p></div></header>
  <div class="settings-grid">
    <SettingsNavigation active="api-keys" />
    <div class="settings-content">
      {#if requestError || keys.hasError}<p class="error-message" role="alert">{requestError || keys.error}</p>{/if}
      {#if createdKey}
        <section class="section api-key-created" aria-labelledby="created-key-title"><div class="section-heading"><div><h2 id="created-key-title">Copy your new key</h2><p>This secret will not appear again after you leave this page.</p></div></div><div class="panel panel-form"><code class="api-key-secret">{createdKey}</code><button class="button small" type="button" onclick={copyKey}>{#if copied}<Check size={14} />Copied{:else}<Copy size={14} />Copy key{/if}</button><p class="api-key-warning">Store this key in a secret manager. Do not add it to source control or client-side code.</p></div></section>
      {/if}

      <section class="section" aria-labelledby="create-key-title"><div class="section-heading"><div><h2 id="create-key-title">Create a key</h2><p>Use a name that identifies the script or service.</p></div></div><form class="panel panel-form" onsubmit={createKey}><div class="field"><label for="api-key-name">Name</label><input class="input" id="api-key-name" name="name" placeholder="Release automation" minlength="1" maxlength="80" required /></div><div class="form-actions"><button class="button primary" type="submit" disabled={pending}><Plus size={14} />Create key</button></div></form></section>

      <section class="section" aria-labelledby="active-keys-title"><div class="section-heading"><div><h2 id="active-keys-title">Active keys</h2><p>Revoke a key when a service no longer needs access.</p></div></div>
        {#if keys.hasKeys}<div class="panel">{#each keys.keys as key (key.id)}<div class="panel-row api-key-row"><KeyRound size={16} /><span class="panel-row-main"><strong>{key.name} · <code>{key.prefix}…</code></strong><span>Created {key.createdAt} · Expires {key.expiresAt} · Last used {key.lastUsedAt}</span></span><button class="button danger small" type="button" onclick={() => revoke(key.id)} disabled={pending}>Revoke</button></div>{/each}</div>{:else}<div class="panel"><div class="panel-row"><span class="panel-row-main"><strong>No API keys</strong><span>Create a key when you are ready to connect an integration.</span></span></div></div>{/if}
      </section>

      <section class="section" aria-labelledby="use-key-title">
        <div class="section-heading"><div><h2 id="use-key-title">Use an API key</h2><p>Send the key as a Bearer credential on every API request.</p></div></div>
        <div class="panel panel-form api-key-docs">
          <h3>Authentication header</h3>
          <pre><code>Authorization: Bearer fbk_YOUR_KEY</code></pre>
          <h3>Search tasks</h3>
          <pre><code>curl -H 'Authorization: Bearer fbk_YOUR_KEY' \
  '{keys.apiBaseURL}/tasks/search?q=release&amp;priority=high'</code></pre>
          <h3>Common endpoints</h3>
          <dl class="api-endpoints">
            <div><dt><code>GET, POST /boards</code></dt><dd>List accessible boards or create a board.</dd></div>
            <div><dt><code>GET, PATCH, DELETE /boards/&#123;boardID&#125;</code></dt><dd>Read, update, or delete one board.</dd></div>
            <div><dt><code>/boards/&#123;boardID&#125;/members</code></dt><dd>List, add, change, or remove board members.</dd></div>
            <div><dt><code>/boards/&#123;boardID&#125;/views</code></dt><dd>Manage saved Board, Table, Calendar, Gantt, and Gallery views.</dd></div>
            <div><dt><code>/boards/&#123;boardID&#125;/templates</code></dt><dd>Manage task templates and create tasks from them.</dd></div>
            <div><dt><code>GET, POST /tasks</code></dt><dd>List filtered tasks or create a task.</dd></div>
            <div><dt><code>GET /tasks/search?q=query</code></dt><dd>Search task titles, descriptions, and public IDs.</dd></div>
            <div><dt><code>GET, PATCH, DELETE /tasks/&#123;taskID&#125;</code></dt><dd>Read, partially update, or delete one task.</dd></div>
            <div><dt><code>POST /tasks/&#123;taskID&#125;/move</code></dt><dd>Move a task to a status and zero-based index.</dd></div>
            <div><dt><code>/tasks/&#123;taskID&#125;/comments</code></dt><dd>List, create, update, or delete comments.</dd></div>
            <div><dt><code>/tasks/&#123;taskID&#125;/checklist</code></dt><dd>Manage and reorder checklist items.</dd></div>
            <div><dt><code>/tasks/&#123;taskID&#125;/followers</code></dt><dd>List followers or follow and unfollow a visible task.</dd></div>
          </dl>
          <p>All resource paths start with <code>{keys.apiBaseURL}</code>. Task list and search requests accept <code>page</code>, <code>per</code>, <code>boardID</code>, <code>status</code>, <code>priority</code>, <code>assigneeID</code>, and <code>archived</code>. Board lists accept <code>q</code> and <code>archived</code>.</p>
          <p>PATCH requests change only supplied fields, and JSON <code>null</code> clears nullable values. API keys use your account and board roles. A key cannot create or revoke another key.</p>
        </div>
      </section>
    </div>
  </div>
</div>
