<script lang="ts">
  import { api, messageFor, refreshAll } from '$lib/api';
  import SettingsNavigation from '$lib/components/SettingsNavigation.svelte';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import type { CanvasIntegrationsPageContext, CreatedCanvasConnectionResponse } from '$lib/types';
  import { CheckIcon as Check, CopyIcon as Copy, PlugsConnectedIcon as PlugsConnected, PlusIcon as Plus } from 'phosphor-svelte';
  import { showToast } from '$lib/ui/toast';

  let { integrations } = $props<{ integrations: CanvasIntegrationsPageContext }>();
  let createdSecret = $state('');
  let createdOrigin = $state('');
  let pending = $state(false);
  let requestError = $state('');
  let copied = $state(false);
  let rotateConnection = $state<{ id: string; origin: string } | null>(null);
  let disconnectConnectionID = $state('');

  async function createConnection(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const canvasOrigin = String(new FormData(form).get('canvasOrigin') ?? '');
    pending = true;
    requestError = '';
    try {
      const created = await api<CreatedCanvasConnectionResponse>('/api/v1/auth/canvas-connections', {
        method: 'POST',
        body: JSON.stringify({ canvasOrigin })
      });
      createdSecret = created.syncKey;
      createdOrigin = created.connection.canvasOrigin;
      form.reset();
      await refreshAll();
      showToast('Canvas connection created');
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pending = false;
    }
  }

  async function rotate(connectionID: string, canvasOrigin: string): Promise<boolean> {
    pending = true;
    requestError = '';
    try {
      const created = await api<CreatedCanvasConnectionResponse>(`/api/v1/auth/canvas-connections/${connectionID}/rotate`, { method: 'POST' });
      createdSecret = created.syncKey;
      createdOrigin = canvasOrigin;
      await refreshAll();
      showToast('Canvas sync key rotated');
      return true;
    } catch (cause) {
      requestError = messageFor(cause);
      return false;
    } finally {
      pending = false;
    }
  }

  async function disconnect(connectionID: string): Promise<boolean> {
    pending = true;
    requestError = '';
    try {
      await api(`/api/v1/auth/canvas-connections/${connectionID}`, { method: 'DELETE' });
      createdSecret = '';
      createdOrigin = '';
      await refreshAll();
      showToast('Canvas disconnected');
      return true;
    } catch (cause) {
      requestError = messageFor(cause);
      return false;
    } finally {
      pending = false;
    }
  }

  function confirmRotation(): Promise<boolean> {
    if (!rotateConnection) return Promise.resolve(false);
    return rotate(rotateConnection.id, rotateConnection.origin);
  }

  async function copySecret(): Promise<void> {
    requestError = '';
    try {
      await navigator.clipboard.writeText(createdSecret);
      copied = true;
      showToast('Canvas sync key copied');
      setTimeout(() => (copied = false), 1800);
    } catch (cause) {
      requestError = messageFor(cause);
    }
  }
</script>

<div class="page narrow">
  <header class="page-header"><div class="page-title"><h1>Integrations</h1><p>Import your courses and assignments from your signed-in Canvas page.</p></div></header>
  <div class="settings-grid">
    <SettingsNavigation active="integrations" />
    <div class="settings-content">
      {#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}

      {#if createdSecret}
        <section class="section canvas-secret-section" aria-labelledby="canvas-secret-title">
          <div class="section-heading"><div><h2 id="canvas-secret-title">Copy your Canvas sync key</h2><p>Enter this key in the extension for {createdOrigin}. It will not appear again.</p></div></div>
          <div class="panel panel-form"><code class="api-key-secret">{createdSecret}</code><button class="button small" type="button" onclick={copySecret}>{#if copied}<Check size={14} />Copied{:else}<Copy size={14} />Copy key{/if}</button><p class="api-key-warning">The key can use only the Canvas status and sync routes. Store it only in the private extension.</p></div>
        </section>
      {/if}

      <section class="section" aria-labelledby="connect-canvas-title">
        <div class="section-heading"><div><h2 id="connect-canvas-title">Connect Canvas</h2><p>Enter the exact HTTPS origin that you use to sign in, with no path.</p></div></div>
        <form class="panel panel-form" onsubmit={createConnection}>
          <div class="field"><label for="canvas-origin">Canvas origin</label><input class="input" id="canvas-origin" name="canvasOrigin" type="url" inputmode="url" placeholder="https://school.instructure.com" required /></div>
          <p class="canvas-use-warning">Confirm that your school permits read-only automation of data in your Canvas account.</p>
          <div class="form-actions"><button class="button primary" type="submit" disabled={pending}><Plus size={14} />Create connection</button></div>
        </form>
      </section>

      <section class="section" aria-labelledby="canvas-connections-title">
        <div class="section-heading"><div><h2 id="canvas-connections-title">Canvas connections</h2><p>Each connection has a restricted key for one Canvas origin.</p></div></div>
        {#if integrations.hasConnections}
          <div class="panel">
            {#each integrations.connections as connection (connection.id)}
              <div class="panel-row canvas-connection-row">
                <PlugsConnected size={17} />
                <span class="panel-row-main"><strong>{connection.canvasOrigin}</strong><span><code>{connection.keyPrefix}…</code> · Last sync {connection.lastSyncDisplay}</span><span class:canvas-status-error={connection.hasError}>{connection.statusName}: {connection.statusDetail}</span></span>
                <span class="canvas-connection-actions"><button class="button small" type="button" onclick={() => (rotateConnection = { id: connection.id, origin: connection.canvasOrigin })} disabled={pending}>Rotate key</button><button class="button danger small" type="button" onclick={() => (disconnectConnectionID = connection.id)} disabled={pending}>Disconnect</button></span>
              </div>
            {/each}
          </div>
        {:else}
          <div class="panel"><div class="panel-row"><span class="panel-row-main"><strong>No Canvas connection</strong><span>Create one before you configure the extension.</span></span></div></div>
        {/if}
      </section>

      <section class="section" aria-labelledby="canvas-install-title">
        <div class="section-heading"><div><h2 id="canvas-install-title">Install the private extension</h2><p>The first release is an unpacked extension for Chrome-based browsers.</p></div></div>
        <div class="panel panel-form api-key-docs canvas-install-steps">
          <ol><li>Build <code>extensions/canvas-sync</code> with <code>pnpm build</code>.</li><li>Open <code>chrome://extensions</code>, enable Developer mode, and select Load unpacked.</li><li>Select the extension <code>dist</code> folder.</li><li>Open the extension and enter your Canvas origin, <code>{integrations.focalpointOrigin}</code> as the Focalpoint origin, and the one-time sync key.</li><li>Open a signed-in Canvas page or select Sync now.</li></ol>
          <p>The extension reads documented Canvas APIs through your current browser session. It does not read or store your password or Canvas session cookie.</p>
        </div>
      </section>
    </div>
  </div>
</div>

<ConfirmDialog open={Boolean(rotateConnection)} title="Rotate this Canvas sync key?" description="The current extension key will stop working." confirmLabel="Rotate key" pendingLabel="Rotating…" tone="primary" oncancel={() => (rotateConnection = null)} onconfirm={confirmRotation} />
<ConfirmDialog open={Boolean(disconnectConnectionID)} title="Disconnect Canvas?" description="Imported courses and assignments will remain as local data." confirmLabel="Disconnect" pendingLabel="Disconnecting…" oncancel={() => (disconnectConnectionID = '')} onconfirm={() => disconnect(disconnectConnectionID)} />
