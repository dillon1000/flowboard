<script lang="ts">
  import { invalidateAll } from '$app/navigation';
  import { api, messageFor } from '$lib/api';
  import type { APIKeysPageContext, CreatedAPIKeyResponse } from '$lib/types';
  import { Check, Copy, KeyRound, Plus } from '@lucide/svelte';
  import SettingsNavigation from '$lib/components/SettingsNavigation.svelte';

  let { keys } = $props<{ keys: APIKeysPageContext }>();
  let createdKey = $state('');
  let pending = $state(false);
  let requestError = $state('');
  let copied = $state(false);

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
      createdKey = created.key;
      form.reset();
      await invalidateAll();
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
      await invalidateAll();
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pending = false;
    }
  }

  async function copyKey(): Promise<void> {
    await navigator.clipboard.writeText(createdKey);
    copied = true;
    setTimeout(() => (copied = false), 1800);
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

      <section class="section" aria-labelledby="use-key-title"><div class="section-heading"><div><h2 id="use-key-title">Use an API key</h2><p>Send the key as a Bearer credential on every API request.</p></div></div><div class="panel panel-form api-key-docs"><h3>Authentication header</h3><pre><code>Authorization: Bearer fbk_YOUR_KEY</code></pre><h3>Search tasks</h3><pre><code>curl -H 'Authorization: Bearer fbk_YOUR_KEY' \
  '{keys.apiBaseURL}/tasks/search?q=release&amp;priority=high'</code></pre><h3>Common endpoints</h3><dl class="api-endpoints"><div><dt><code>GET, POST /boards</code></dt><dd>List or create courses.</dd></div><div><dt><code>/boards/&#123;boardID&#125;/views</code></dt><dd>Manage saved board views.</dd></div><div><dt><code>GET, POST /tasks</code></dt><dd>List or create tasks.</dd></div><div><dt><code>/tasks/&#123;taskID&#125;/comments</code></dt><dd>Manage task comments.</dd></div></dl><p>All resource paths start with <code>{keys.apiBaseURL}</code>. API keys use your account and board roles.</p></div></section>
    </div>
  </div>
</div>
