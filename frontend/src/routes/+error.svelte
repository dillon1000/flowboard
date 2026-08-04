<script lang="ts">
  import { page } from '$app/state';
  import ThemeToggle from '$lib/components/ThemeToggle.svelte';

  const isNotFound = $derived(page.status === 404);
</script>

<svelte:head><title>{isNotFound ? 'Page not found' : `Error ${page.status}`} · Flowboard</title></svelte:head>

<div class="not-found-page">
  <header class="not-found-header">
    <a class="brand" href="/" aria-label="Flowboard home">
      <img class="brand-wordmark" src="/focalboard-wordmark.webp" alt="" width="112" height="15" />
    </a>
    <ThemeToggle />
  </header>

  <main class="not-found-main">
    <section class="not-found-copy" aria-labelledby="error-title">
      <p class="not-found-kicker"><span>{page.status}</span>{isNotFound ? 'Page not found' : 'Request failed'}</p>
      <h1 id="error-title">{isNotFound ? 'This card isn’t on the board.' : 'This board did not load.'}</h1>
      <p>{isNotFound ? 'The page may have moved, changed its name, or been archived.' : page.error?.message ?? 'Try the request again.'}</p>
      <a class="button primary large" href="/">Return to Flowboard</a>
    </section>

    <div class="not-found-board" aria-hidden="true">
      <section class="not-found-column">
        <div class="not-found-column-title"><span></span>Backlog</div>
        <div class="not-found-task"><strong>Plan the next release</strong><span></span></div>
        <div class="not-found-task short"><strong>Review feedback</strong><span></span></div>
      </section>
      <section class="not-found-column">
        <div class="not-found-column-title"><span></span>In progress</div>
        <div class="not-found-task missing"><b>?</b><strong>Missing task</strong></div>
      </section>
      <section class="not-found-column">
        <div class="not-found-column-title"><span></span>Done</div>
        <div class="not-found-task complete"><strong>Ship the workspace</strong><span></span></div>
      </section>
    </div>
  </main>
</div>
