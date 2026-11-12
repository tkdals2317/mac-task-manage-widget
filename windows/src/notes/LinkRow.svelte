<script lang="ts">
  import { deleteLink } from "../lib/notes.svelte";
  import { siteIcon, type SavedLink } from "./data";
  import { clickOutside } from "./clickOutside";
  import { openMenu } from "./menu.svelte";
  import { copyLink, openLink } from "./openLink";
  import Icon from "./Icon.svelte";
  import LinkLine from "./LinkLine.svelte";
  import LinkEditPopover from "./LinkEditPopover.svelte";
  let { link }: { link: SavedLink } = $props();
  let editing = $state(false);
  const host = $derived.by(() => { try { return new URL(link.url).hostname; } catch { return undefined; } });
</script>

<div class="anchor" style="position:relative" use:clickOutside={() => (editing = false)}>
  <LinkLine icon={siteIcon(host)} title={link.title} source={host ?? link.url} forceTrailing={editing}
    onopen={() => openLink(link.url)}
    oncontext={(e) => openMenu(e, [
      { label: "열기", onclick: () => openLink(link.url) },
      { label: "주소 복사", onclick: () => copyLink(link.url) },
      { label: "수정…", onclick: () => (editing = true) },
      { sep: true },
      { label: "삭제", danger: true, onclick: () => deleteLink(link.id) },
    ])}>
    {#snippet trailing()}
      <button class="icon-btn mini" title="주소 복사" onclick={() => copyLink(link.url)}><Icon name="copy" size="1em" /></button>
      <button class="icon-btn mini" title="수정" onclick={() => (editing = true)}><Icon name="pencil" size="1em" /></button>
      <button class="icon-btn mini" title="삭제" onclick={() => deleteLink(link.id)}><Icon name="x" size="1em" bold /></button>
    {/snippet}
  </LinkLine>
  {#if editing}<LinkEditPopover {link} done={() => (editing = false)} />{/if}
</div>

<style>
  .mini { width: 1.5em; height: 1.5em; font-size: .78em; }
</style>
