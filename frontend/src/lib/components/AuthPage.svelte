<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import { api, messageFor } from '$lib/api';
  import type { AuthConfiguration } from '$lib/types';
  import { Columns3, Copy, LogIn, Users } from '@lucide/svelte';
  import BuildSignature from './BuildSignature.svelte';
  import ThemeToggle from './ThemeToggle.svelte';

  let { mode, configuration } = $props<{
    mode: 'login' | 'register';
    configuration: AuthConfiguration;
  }>();
  let pending = $state(false);
  let requestError = $state(page.url.searchParams.get('oauth_error') ?? '');

  const isRegister = $derived(mode === 'register');

  async function submit(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement;
    const data = new FormData(form);
    const input: Record<string, string> = {
      email: String(data.get('email') ?? ''),
      password: String(data.get('password') ?? '')
    };
    if (isRegister) input.name = String(data.get('name') ?? '');

    pending = true;
    requestError = '';
    try {
      await api(`/api/v1/auth/${mode}`, { method: 'POST', body: JSON.stringify(input) });
      const requested = page.url.searchParams.get('returnTo');
      const destination = requested?.startsWith('/') && !requested.startsWith('//') ? requested : '/app';
      await goto(destination, { invalidateAll: true });
    } catch (cause) {
      requestError = messageFor(cause);
    } finally {
      pending = false;
    }
  }
</script>

<svelte:head><title>{isRegister ? 'Create account' : 'Log in'} · Flowboard</title></svelte:head>

<div class="auth-page">
  <header class="auth-header">
    <a class="brand" href="/" aria-label="Flowboard home">
      <img class="brand-wordmark" src="/focalboard-wordmark.webp" alt="" width="112" height="15" />
    </a>
    <ThemeToggle />
  </header>

  <main class:auth-main-single={!isRegister} class="auth-main">
    <div class="auth-form-pane">
      <section class:auth-card-minimal={!isRegister} class="auth-card" aria-labelledby="page-title">
      <h1 id="page-title">{isRegister ? 'Create your account' : 'Log in'}</h1>
      {#if isRegister}<p>Your workspace and first course are ready after sign-up.</p>{/if}
      {#if requestError}<p class="error-message" role="alert">{requestError}</p>{/if}

      {#if configuration.oauthEnabled}
        <a class="button large block oauth-button" href="/oauth/start">
          <LogIn size={16} />Continue with {configuration.oauthProviderName}
        </a>
        <div class="auth-divider" aria-hidden="true"><span>or</span></div>
      {/if}

      <form onsubmit={submit}>
        {#if isRegister}
          <div class="field">
            <label for="name">Name</label>
            <input class="input" id="name" name="name" autocomplete="name" minlength="2" maxlength="80" required />
          </div>
        {/if}
        <div class="field">
          <label for="email">Email</label>
          <input class="input" id="email" type="email" name="email" autocomplete="email" spellcheck="false" placeholder="you@example.com" required />
        </div>
        <div class="field">
          <label for="password">Password</label>
          <input class="input" id="password" type="password" name="password" autocomplete={isRegister ? 'new-password' : 'current-password'} minlength={isRegister ? 8 : undefined} maxlength="72" required />
          {#if isRegister}<span class="field-help">Use 8 to 72 characters.</span>{/if}
        </div>
        <button class="button primary" type="submit" disabled={pending}>{pending ? 'Working…' : isRegister ? 'Create account' : 'Log in'}</button>
      </form>

      <p class="auth-switch">
        {#if isRegister}Already have an account? <a href="/login">Log in</a>{:else}<a href="/register">Create account</a>{/if}
      </p>
      </section>
      <BuildSignature />
    </div>

    {#if isRegister}
      <aside class="auth-aside">
        <blockquote>Everything your team needs to ship the work.</blockquote>
        <ul class="auth-points">
          <li><Columns3 size={18} />Board, table, calendar, and gallery views</li>
          <li><Users size={18} />Shared courses with per-role access</li>
          <li><Copy size={18} />Templates, custom fields, and JSON export</li>
        </ul>
        <p class="auth-footer">Your work stays private until you share it.</p>
      </aside>
    {/if}
  </main>
</div>
