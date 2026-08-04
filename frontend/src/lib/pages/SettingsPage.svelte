<script lang="ts">
  import { goto, invalidateAll } from '$app/navigation';
  import { api, messageFor } from '$lib/api';
  import type { CommonPageContext } from '$lib/types';
  import { LogOut } from '@lucide/svelte';
  import Avatar from '$lib/components/Avatar.svelte';
  import SettingsNavigation from '$lib/components/SettingsNavigation.svelte';

  let { common } = $props<{ common: CommonPageContext }>();
  let pending = $state(false);
  let requestError = $state('');
  let saved = $state(false);

  async function saveProfile(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const name = String(new FormData(event.currentTarget as HTMLFormElement).get('name') ?? '');
    pending = true;
    requestError = '';
    saved = false;
    try {
      await api('/api/v1/auth/me', { method: 'PATCH', body: JSON.stringify({ name }) });
      saved = true;
      await invalidateAll();
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pending = false;
    }
  }

  async function logout(): Promise<void> {
    await api('/api/v1/auth/logout', { method: 'POST' });
    await goto('/login', { invalidateAll: true });
  }
</script>

<div class="page narrow">
  <header class="page-header"><div class="page-title"><h1>Settings</h1><p>Manage your account and workspace preferences.</p></div></header>
  <div class="settings-grid">
    <SettingsNavigation active="profile" />
    <div class="settings-content">
      <section class="section">
        <div class="section-heading"><h2>Profile</h2></div>
        <form class="panel panel-form" onsubmit={saveProfile}>
          <div class="profile-identity"><Avatar avatar={common.userAvatar} large /><span><strong>{common.userName}</strong><small>Profile pictures refresh when you sign in with OAuth.</small></span></div>
          {#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}
          {#if saved}<p class="success-message" role="status">Profile saved.</p>{/if}
          <div class="field"><label for="profile-name">Name</label><input class="input" id="profile-name" name="name" value={common.userName} minlength="2" maxlength="80" required /></div>
          <div class="field"><label for="profile-email">Email</label><input class="input" id="profile-email" value={common.userEmail} disabled /><span class="field-help">Email changes are not available.</span></div>
          <div class="form-actions"><button class="button primary" type="submit" disabled={pending}>{pending ? 'Saving…' : 'Save profile'}</button></div>
        </form>
      </section>
      <section class="section"><div class="section-heading"><h2>Session</h2></div><div class="panel"><div class="panel-row"><span class="panel-row-main"><strong>Log out</strong><span>End this browser session.</span></span><button class="button" type="button" onclick={logout}><LogOut size={15} />Log out</button></div></div></section>
    </div>
  </div>
</div>
