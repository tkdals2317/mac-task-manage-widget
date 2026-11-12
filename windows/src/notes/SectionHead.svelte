<script lang="ts">
  import type { Snippet } from "svelte";
  import Icon from "./Icon.svelte";
  let { title, count, collapsed, ontoggle, children }: { title: string; count: number; collapsed: boolean; ontoggle: () => void; children?: Snippet } = $props();
</script>

<div class="head">
  <button class="toggle" onclick={ontoggle} aria-expanded={!collapsed}>
    <Icon name={collapsed ? "right" : "down"} size=".75em" bold />
    <b>{title}</b>
    <span class="n">{count}</span>
  </button>
  <div class="grow"></div>
  {@render children?.()}
</div>

<style>
  .head { display: flex; align-items: center; gap: 6px; padding: 10px 0 4px; color: var(--fg2); }
  .toggle { display: inline-flex; align-items: center; gap: 4px; border: none; background: transparent; color: inherit; cursor: pointer; padding: 0; }
  b { font-size: .85em; font-weight: 600; }
  .n { font-size: .81em; }
  .grow { flex: 1; }
</style>
