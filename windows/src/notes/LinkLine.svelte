<script lang="ts">
  // 링크 줄 공통 모양: 왼쪽 출처 아이콘 상자 + 한 줄 제목 + 오른쪽 흐린 출처 (호버하면 동작 버튼).
  import type { Snippet } from "svelte";
  import Icon from "./Icon.svelte";
  let { icon, tint = "var(--fg2)", title, source, trailing, onopen, oncontext, forceTrailing = false }: {
    icon: string; tint?: string; title: string; source: string; trailing: Snippet;
    onopen: () => void; oncontext: (e: MouseEvent) => void; forceTrailing?: boolean;
  } = $props();
</script>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="line" class:force={forceTrailing} onclick={onopen} oncontextmenu={oncontext}>
  <span class="ico" style="color:{tint};--t:{tint}"><Icon name={icon} size=".85em" /></span>
  <span class="title" {title}>{title}</span>
  <span class="src">{source}</span>
  <span class="trail" onclick={(e) => e.stopPropagation()}>{@render trailing()}</span>
</div>

<style>
  .line { display: flex; align-items: center; gap: 8px; padding: 5px 0; border-bottom: 1px solid var(--line); cursor: pointer; position: relative; }
  .ico { display: inline-flex; align-items: center; justify-content: center; flex: none; width: 1.55em; height: 1.55em; border-radius: 5px; background: color-mix(in srgb, var(--t) 14%, transparent); }
  .title { flex: 1; min-width: 0; font-size: .96em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .src { flex: none; max-width: 40%; font-size: .81em; color: var(--fg2); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .trail { display: none; flex: none; align-items: center; gap: 7px; cursor: default; }
  .line:hover .src, .line.force .src { display: none; }
  .line:hover .trail, .line.force .trail { display: inline-flex; }
</style>
