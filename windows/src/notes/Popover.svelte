<script lang="ts">
  // 앵커(position:relative) 안에 뜨는 작은 창. 바깥 클릭·Esc 는 부모가 처리한다.
  import type { Snippet } from "svelte";
  let { width = 250, children }: { width?: number; children: Snippet } = $props();
</script>

<div class="popover pop" style="width:{width}px" role="dialog">{@render children()}</div>

<style>
  .pop { top: calc(100% + 4px); right: 0; display: flex; flex-direction: column; gap: 8px; padding: 12px; user-select: text; }
  .pop :global(.err) { color: var(--danger); font-size: .8em; }
  .pop :global(.warn) { color: var(--warn); font-size: .8em; }
  .pop :global(h4) { margin: 0; font-size: .96em; font-weight: 600; }
  .pop :global(.lbl) { font-size: .81em; font-weight: 500; color: var(--fg2); }
  .pop :global(.btns) { display: flex; justify-content: flex-end; gap: 6px; }
</style>
