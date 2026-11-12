<script lang="ts">
  // 오른쪽 클릭 메뉴 / 드롭다운 메뉴. 항목을 누르면 onselect 후 닫힌다.
  import Popover from "./Popover.svelte";

  export interface MenuItem {
    label?: string;
    checked?: boolean;
    header?: boolean;
    separator?: boolean;
    onselect?: () => void;
  }
  let { items, anchor, align = "start", onclose }: {
    items: MenuItem[]; anchor: HTMLElement | { x: number; y: number }; align?: "start" | "end"; onclose: () => void;
  } = $props();
</script>

<Popover {anchor} {align} {onclose}>
  <div class="menu">
    {#each items as it, i (i)}
      {#if it.separator}
        <div class="sep"></div>
      {:else if it.header}
        <div class="hdr">{it.label}</div>
      {:else}
        <button class="item" onclick={() => { it.onselect?.(); onclose(); }}>
          <span class="check">{it.checked ? "✓" : ""}</span>{it.label}
        </button>
      {/if}
    {/each}
  </div>
</Popover>

<style>
  .menu { display: flex; flex-direction: column; min-width: 150px; margin: -6px; padding: 4px 0; }
  .item { display: flex; align-items: center; gap: 4px; padding: 4px 10px; border: none; background: transparent; text-align: left; cursor: pointer; border-radius: 4px; margin: 0 3px; }
  .item:hover { background: var(--fill2); }
  .check { width: 1em; color: var(--accent); font-size: 0.9em; }
  .hdr { padding: 4px 10px 2px; font-size: 0.85em; font-weight: 600; color: var(--fg2); }
  .sep { height: 1px; background: var(--line); margin: 3px 0; }
</style>
