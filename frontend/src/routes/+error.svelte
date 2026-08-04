<script lang="ts">
  import { page } from '$app/state';
  import { ArrowLeft, SearchX } from '@lucide/svelte';
</script>

<svelte:head><title>{page.status} · Flowboard</title></svelte:head>
<main class="not-found-page">
  <section class="not-found-card">
    <SearchX size={32} />
    <p class="eyebrow">{page.status}</p>
    <h1>{page.status === 404 ? 'This page does not exist' : 'Flowboard could not load this page'}</h1>
    <p>{page.error?.message ?? 'Try the request again.'}</p>
    <a class="button primary" href="/"><ArrowLeft size={16} />Return to Flowboard</a>
  </section>
</main>
