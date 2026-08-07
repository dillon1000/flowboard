<script lang="ts">
  import { goto } from '$app/navigation';
  import { api, messageFor, refreshAll } from '$lib/api';
  import type { CommonPageContext, CreatedCalendarFeedResponse, SettingsPageContext } from '$lib/types';
  import { CheckIcon as Check, CopyIcon as Copy, SignOutIcon as LogOut } from 'phosphor-svelte';
  import Avatar from '$lib/components/Avatar.svelte';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import SettingsNavigation from '$lib/components/SettingsNavigation.svelte';
  import { showToast } from '$lib/ui/toast';

  let { common, settings } = $props<{ common: CommonPageContext; settings: SettingsPageContext }>();
  let profilePending = $state(false);
  let planningPending = $state(false);
  let calendarPending = $state(false);
  let requestError = $state('');
  let profileSaved = $state(false);
  let planningSaved = $state(false);
  let calendarFeedURL = $state('');
  let calendarCopied = $state(false);
  let timeZoneInput: HTMLInputElement;
  let rotateCalendarOpen = $state(false);
  let disableCalendarOpen = $state(false);

  async function saveProfile(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    const name = String(data.get('name') ?? '');
    const timeZone = String(data.get('timeZone') ?? 'UTC');
    profilePending = true;
    requestError = '';
    profileSaved = false;
    try {
      await api('/api/v1/auth/me', { method: 'PATCH', body: JSON.stringify({ name, timeZone }) });
      profileSaved = true;
      await refreshAll();
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      profilePending = false;
    }
  }

  async function savePlanningEmails(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const data = new FormData(event.currentTarget as HTMLFormElement);
    planningPending = true;
    requestError = '';
    planningSaved = false;
    try {
      await api('/api/v1/auth/me', {
        method: 'PATCH',
        body: JSON.stringify({
          name: common.userName,
          dailyBriefEnabled: data.has('dailyBriefEnabled'),
          weeklyPlanningPromptEnabled: data.has('weeklyPlanningPromptEnabled'),
          planningEmailHour: Number(data.get('planningEmailHour'))
        })
      });
      planningSaved = true;
      await refreshAll();
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      planningPending = false;
    }
  }

  async function rotateCalendarFeed(): Promise<boolean> {
    const wasEnabled = settings.calendarFeed.isEnabled;
    calendarPending = true;
    requestError = '';
    try {
      const created = await api<CreatedCalendarFeedResponse>('/api/v1/auth/calendar-feed', { method: 'POST' });
      calendarFeedURL = `${window.location.origin}/api/v1/calendar-feed/${created.token}/calendar.ics`;
      calendarCopied = false;
      await refreshAll();
      showToast(wasEnabled ? 'Calendar link rotated' : 'Calendar link created');
      return true;
    } catch (cause) {
      requestError = messageFor(cause);
      return false;
    } finally {
      calendarPending = false;
    }
  }

  async function revokeCalendarFeed(): Promise<boolean> {
    calendarPending = true;
    requestError = '';
    try {
      await api('/api/v1/auth/calendar-feed', { method: 'DELETE' });
      calendarFeedURL = '';
      await refreshAll();
      showToast('Calendar feed disabled');
      return true;
    } catch (cause) {
      requestError = messageFor(cause);
      return false;
    } finally {
      calendarPending = false;
    }
  }

  function requestCalendarFeed(): void {
    if (settings.calendarFeed.isEnabled) rotateCalendarOpen = true;
    else void rotateCalendarFeed();
  }

  async function copyCalendarFeed(): Promise<void> {
    requestError = '';
    try {
      await navigator.clipboard.writeText(calendarFeedURL);
      calendarCopied = true;
      showToast('Calendar link copied');
      setTimeout(() => (calendarCopied = false), 1800);
    } catch (cause) {
      requestError = messageFor(cause);
    }
  }

  async function logout(): Promise<void> {
    await api('/api/v1/auth/logout', { method: 'POST' });
    await goto('/login', { invalidateAll: true });
  }
</script>

<div class="page narrow">
  <header class="page-header"><div class="page-title"><h1>Settings</h1><p>Manage your account and planning preferences.</p></div></header>
  <div class="settings-grid">
    <SettingsNavigation active="profile" />
    <div class="settings-content">
      {#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}

      <section class="section">
        <div class="section-heading"><h2>Profile</h2></div>
        <form class="panel panel-form" onsubmit={saveProfile}>
          <div class="profile-identity"><Avatar avatar={common.userAvatar} large /><span><strong>{common.userName}</strong><small>Profile pictures refresh when you sign in with OAuth.</small></span></div>
          {#if profileSaved}<p class="success-message" role="status">Profile saved.</p>{/if}
          <div class="field"><label for="profile-name">Name</label><input class="input" id="profile-name" name="name" value={common.userName} minlength="2" maxlength="80" required /></div>
          <div class="field"><label for="profile-email">Email</label><input class="input" id="profile-email" value={common.userEmail} disabled /><span class="field-help">Email changes are not available.</span></div>
          <div class="field"><label for="profile-time-zone">Time zone</label><input class="input" id="profile-time-zone" name="timeZone" value={common.userTimeZone} bind:this={timeZoneInput} required /><span class="field-help">Use an IANA zone such as America/Chicago. <button class="inline-button" type="button" onclick={() => timeZoneInput.value = Intl.DateTimeFormat().resolvedOptions().timeZone}>Use this browser</button></span></div>
          <div class="form-actions"><button class="button primary" type="submit" disabled={profilePending}>{profilePending ? 'Saving…' : 'Save profile'}</button></div>
        </form>
      </section>

      <section class="section" aria-labelledby="planning-email-title">
        <div class="section-heading"><div><h2 id="planning-email-title">Planning emails</h2><p>Use your saved time zone to send a brief at the right local hour.</p></div></div>
        <form class="panel panel-form planning-email-form" onsubmit={savePlanningEmails}>
          {#if planningSaved}<p class="success-message" role="status">Planning email settings saved.</p>{/if}
          {#if !settings.notificationsAvailable}<p class="field-help">Email delivery is not configured on this server.</p>{/if}
          <label class="checkbox-label notification-choice">
            <input class="checkbox-input" type="checkbox" name="dailyBriefEnabled" checked={common.dailyBriefEnabled} disabled={!settings.notificationsAvailable} />
            <span class="checkbox-control" aria-hidden="true"><Check size={13} /></span>
            <span><strong>Daily brief</strong><small>Get today's study sessions and deadlines.</small></span>
          </label>
          <label class="checkbox-label notification-choice">
            <input class="checkbox-input" type="checkbox" name="weeklyPlanningPromptEnabled" checked={common.weeklyPlanningPromptEnabled} disabled={!settings.notificationsAvailable} />
            <span class="checkbox-control" aria-hidden="true"><Check size={13} /></span>
            <span><strong>Weekly planning prompt</strong><small>Get a Monday reminder when work still needs a study session.</small></span>
          </label>
          <div class="field planning-hour-field"><label for="planning-email-hour">Delivery hour</label><input class="input" id="planning-email-hour" name="planningEmailHour" type="number" min="0" max="23" value={common.planningEmailHour} required disabled={!settings.notificationsAvailable} /><span class="field-help">Use local 24-hour time. For example, 7 means 7:00 AM.</span></div>
          <div class="form-actions"><button class="button primary" type="submit" disabled={planningPending || !settings.notificationsAvailable}>{planningPending ? 'Saving…' : 'Save planning emails'}</button></div>
        </form>
      </section>

      <section class="section" aria-labelledby="calendar-feed-title">
        <div class="section-heading"><div><h2 id="calendar-feed-title">Calendar feed</h2><p>Subscribe to a read-only calendar of deadlines and study sessions.</p></div></div>
        {#if calendarFeedURL}
          <div class="panel panel-form calendar-feed-created">
            <code class="api-key-secret">{calendarFeedURL}</code>
            <button class="button small" type="button" onclick={copyCalendarFeed}>{#if calendarCopied}<Check size={14} />Copied{:else}<Copy size={14} />Copy link{/if}</button>
            <p class="api-key-warning">This link grants access to your planning calendar. Add it to your calendar app, and do not share it.</p>
          </div>
        {/if}
        <div class="panel">
          <div class="panel-row calendar-feed-row">
            <span class="panel-row-main">
              <strong>{settings.calendarFeed.isEnabled ? 'Calendar feed active' : 'Calendar feed disabled'}</strong>
              <span>{settings.calendarFeed.isEnabled ? `Current link starts with ${settings.calendarFeed.prefix}…` : 'Create a private subscription link for any calendar app.'}</span>
            </span>
            <span class="calendar-feed-actions">
              <button class="button" type="button" onclick={requestCalendarFeed} disabled={calendarPending}>{settings.calendarFeed.isEnabled ? 'Rotate link' : 'Create link'}</button>
              {#if settings.calendarFeed.isEnabled}<button class="button danger" type="button" onclick={() => (disableCalendarOpen = true)} disabled={calendarPending}>Disable</button>{/if}
            </span>
          </div>
        </div>
      </section>

      <section class="section"><div class="section-heading"><h2>Session</h2></div><div class="panel"><div class="panel-row"><span class="panel-row-main"><strong>Log out</strong><span>End this browser session.</span></span><button class="button" type="button" onclick={logout}><LogOut size={15} />Log out</button></div></div></section>
    </div>
  </div>
</div>

<ConfirmDialog open={rotateCalendarOpen} title="Rotate this calendar link?" description="The current subscription link will stop working." confirmLabel="Rotate link" pendingLabel="Rotating…" tone="primary" oncancel={() => (rotateCalendarOpen = false)} onconfirm={rotateCalendarFeed} />
<ConfirmDialog open={disableCalendarOpen} title="Disable this calendar feed?" description="The current subscription link will stop working." confirmLabel="Disable feed" pendingLabel="Disabling…" oncancel={() => (disableCalendarOpen = false)} onconfirm={revokeCalendarFeed} />
