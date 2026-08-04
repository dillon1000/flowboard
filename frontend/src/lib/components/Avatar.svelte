<script lang="ts">
  import type { AvatarContext } from '$lib/types';

  let { avatar, large = false } = $props<{ avatar: AvatarContext; large?: boolean }>();
</script>

<span class:large class="avatar">
  {#if avatar.hasProfilePicture}
    <img src={avatar.profilePictureURL} alt="" referrerpolicy="no-referrer" />
  {:else}
    {avatar.initials}
  {/if}
</span>
