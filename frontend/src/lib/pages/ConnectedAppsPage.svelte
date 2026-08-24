<script lang="ts">
  import { api, messageFor, refreshAll } from '$lib/api';
  import type { ConnectedAppsPageContext } from '$lib/types';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import SettingsNavigation from '$lib/components/SettingsNavigation.svelte';
  import { CopyIcon as Copy, RobotIcon as Robot, ShieldCheckIcon as ShieldCheck } from 'phosphor-svelte';
  import { showToast } from '$lib/ui/toast';

  let { apps } = $props<{ apps: ConnectedAppsPageContext }>();
  let disconnectID = $state('');
  let pending = $state(false);
  let requestError = $state('');

  async function disconnect(clientID: string): Promise<boolean> {
    pending = true;
    requestError = '';
    try {
      await api(`/api/v1/oauth-connections/${clientID}`, { method: 'DELETE' });
      await refreshAll();
      showToast('App disconnected');
      return true;
    } catch (cause) {
      requestError = messageFor(cause);
      return false;
    } finally {
      pending = false;
    }
  }

  async function copyServerURL(): Promise<void> {
    try {
      await navigator.clipboard.writeText(apps.mcpServerURL);
      showToast('MCP server URL copied');
    } catch (cause) {
      requestError = messageFor(cause);
    }
  }
</script>

<div class="page narrow">
  <header class="page-header"><div class="page-title"><h1>Connected apps</h1><p>Review and disconnect AI clients that can read your workspace.</p></div></header>
  <div class="settings-grid">
    <SettingsNavigation active="connected-apps" />
    <div class="settings-content">
      {#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}

      <section class="section" aria-labelledby="connected-apps-title">
        <div class="section-heading"><div><h2 id="connected-apps-title">Authorized clients</h2><p>Disconnecting an app revokes all of its access and refresh tokens immediately.</p></div></div>
        {#if apps.hasConnections}
          <div class="panel">
            {#each apps.connections as connection (connection.id)}
              <div class="panel-row connected-app-row">
                <span class="connected-app-icon" aria-hidden="true"><Robot size={17} /></span>
                <span class="panel-row-main"><strong>{connection.name}</strong><span>{connection.scope} · Connected {connection.connectedAt}</span></span>
                <button class="button danger small" type="button" onclick={() => (disconnectID = connection.id)} disabled={pending}>Disconnect</button>
              </div>
            {/each}
          </div>
        {:else}
          <div class="panel"><div class="panel-row"><span class="connected-app-icon" aria-hidden="true"><ShieldCheck size={17} /></span><span class="panel-row-main"><strong>No connected apps</strong><span>AI clients you authorize through OAuth will appear here.</span></span></div></div>
        {/if}
      </section>

      <section class="section" aria-labelledby="mcp-server-title">
        <div class="section-heading"><div><h2 id="mcp-server-title">Connect another client</h2><p>Add this global MCP server in Claude, Codex, or another compatible client.</p></div></div>
        <div class="panel panel-form connected-app-server">
          <code>{apps.mcpServerURL}</code>
          <button class="button small" type="button" onclick={copyServerURL}><Copy size={14} />Copy URL</button>
          <p>Focalboard will ask you to sign in and approve read-only workspace access. You never need to paste an API key.</p>
        </div>
      </section>
    </div>
  </div>
</div>

<ConfirmDialog open={Boolean(disconnectID)} title="Disconnect this app?" description="The client will lose access immediately and must be authorized again to reconnect." confirmLabel="Disconnect" pendingLabel="Disconnecting…" oncancel={() => (disconnectID = '')} onconfirm={() => disconnect(disconnectID)} />
