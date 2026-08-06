<script lang="ts">
  import { CalendarDotsIcon as CalendarDays, KeyIcon as KeyRound, PlugsConnectedIcon as PlugsConnected, UserIcon as User } from 'phosphor-svelte';
  let { active } = $props<{ active: 'profile' | 'availability' | 'api-keys' | 'integrations' }>();
</script>

<nav class="settings-menu" aria-label="Account settings">
  <a class:active={active === 'profile'} class="nav-link" href="/app/settings" aria-current={active === 'profile' ? 'page' : undefined}><User size={15} /><span>Profile</span></a>
  <a class:active={active === 'availability'} class="nav-link" href="/app/settings/availability" aria-current={active === 'availability' ? 'page' : undefined}><CalendarDays size={15} /><span>Availability</span></a>
  <a class:active={active === 'api-keys'} class="nav-link" href="/app/settings/api-keys" aria-current={active === 'api-keys' ? 'page' : undefined}><KeyRound size={15} /><span>API keys</span></a>
  <a class:active={active === 'integrations'} class="nav-link" href="/app/settings/integrations" aria-current={active === 'integrations' ? 'page' : undefined}><PlugsConnected size={15} /><span>Integrations</span></a>
</nav>
