<script lang="ts">
  import { enhance } from '$app/forms';
  import { page } from '$app/state';
  import type { AuthActionData } from '$lib/server/auth';
  import type { AuthConfiguration } from '$lib/types';
  import { ColumnsIcon as Columns3, CopyIcon as Copy, SignInIcon as LogIn, UsersIcon as Users } from 'phosphor-svelte';
  import BuildSignature from './BuildSignature.svelte';
  import ThemeToggle from './ThemeToggle.svelte';

  let { mode, configuration, form = null } = $props<{
    mode: 'login' | 'register';
    configuration: AuthConfiguration;
    form?: AuthActionData | null;
  }>();
  let pending = $state(false);

  const isRegister = $derived(mode === 'register');
  const requestError = $derived(pending ? '' : form?.message ?? page.url.searchParams.get('oauth_error') ?? '');
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

      <form method="POST" use:enhance={() => {
        pending = true;
        return async ({ update }) => {
          await update();
          pending = false;
        };
      }}>
        {#if isRegister}
          <div class="field">
            <label for="name">Name</label>
            <input class="input" id="name" name="name" value={form?.values.name ?? ''} autocomplete="name" minlength="2" maxlength="80" required />
          </div>
        {/if}
        <div class="field">
          <label for="email">Email</label>
          <input class="input" id="email" type="email" name="email" value={form?.values.email ?? ''} autocomplete="email" spellcheck="false" placeholder="you@example.com" required />
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
          <li><Columns3 size={18} />Board, table, calendar, Gantt, and gallery views</li>
          <li><Users size={18} />Shared courses with per-role access</li>
          <li><Copy size={18} />Templates, custom fields, and JSON export</li>
        </ul>
        <p class="auth-footer">Your work stays private until you share it.</p>
      </aside>
    {/if}
  </main>
</div>
