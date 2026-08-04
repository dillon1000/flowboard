<script lang="ts">
  import { KeyRound, User } from '@lucide/svelte';
  let { active } = $props<{ active: 'profile' | 'api-keys' }>();
</script>

<nav class="settings-menu" aria-label="Account settings">
  <a class:active={active === 'profile'} class="nav-link" href="/app/settings" aria-current={active === 'profile' ? 'page' : undefined}><User size={15} /><span>Profile</span></a>
  <a class:active={active === 'api-keys'} class="nav-link" href="/app/settings/api-keys" aria-current={active === 'api-keys' ? 'page' : undefined}><KeyRound size={15} /><span>API keys</span></a>
</nav>
