<script lang="ts">
  import type { Snippet } from "svelte";
  import Icon from "./Icon.svelte";

  let { title, count, collapsed = $bindable(), trailing }: {
    title: string; count: number; collapsed: boolean; trailing?: Snippet;
  } = $props();
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<div class="section-header" role="presentation" onclick={() => (collapsed = !collapsed)}>
  <span class="lead">
    <Icon name={collapsed ? "chevron-right" : "chevron-down"} size={0.75} />
    <b>{title}</b>
    <span class="count">{count}</span>
  </span>
  <span class="grow"></span>
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <span class="trail" role="presentation" onclick={(e) => e.stopPropagation()}>{@render trailing?.()}</span>
</div>

<style>
  .lead { display: inline-flex; align-items: center; gap: 4px; font-size: 0.92em; }
  .count { font-size: 0.9em; font-weight: 400; }
  .grow { flex: 1; }
  .trail { display: inline-flex; align-items: center; gap: 6px; cursor: default; }
</style>
