<script lang="ts">
  import { agoText } from "./data";
  import type { StarredPage } from "../lib/confluence";
  import { openMenu } from "./menu.svelte";
  import { copyLink, openLink } from "./openLink";
  import Icon from "./Icon.svelte";
  import LinkLine from "./LinkLine.svelte";
  let { page }: { page: StarredPage } = $props();
</script>

<LinkLine icon="doc" tint="var(--info)" title={page.title} source={page.spaceKey}
  onopen={() => openLink(page.url)}
  oncontext={(e) => openMenu(e, [
    { label: "열기", onclick: () => openLink(page.url) },
    { label: "주소 복사", onclick: () => copyLink(page.url) },
  ])}>
  {#snippet trailing()}
    {#if page.updated}<span class="ago">{agoText(page.updated)}</span>{/if}
    <button class="icon-btn mini" title="주소 복사" onclick={() => copyLink(page.url)}><Icon name="copy" size="1em" /></button>
  {/snippet}
</LinkLine>

<style>
  .ago { font-size: .81em; color: var(--fg2); white-space: nowrap; }
  .mini { width: 1.5em; height: 1.5em; font-size: .78em; }
</style>
