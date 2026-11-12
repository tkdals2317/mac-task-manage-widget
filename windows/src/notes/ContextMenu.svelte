<script lang="ts">
  import { menu, closeMenu } from "./menu.svelte";
  let el: HTMLDivElement | undefined = $state();
  // 패널 밖으로 나가지 않게 위치를 당긴다.
  const pos = $derived.by(() => {
    const w = el?.offsetWidth ?? 150, h = el?.offsetHeight ?? 120;
    return { x: Math.max(4, Math.min(menu.x, window.innerWidth - w - 4)), y: Math.max(4, Math.min(menu.y, window.innerHeight - h - 4)) };
  });
  function onDown(e: PointerEvent) { if (menu.open && !el?.contains(e.target as Node)) closeMenu(); }
  function onKey(e: KeyboardEvent) { if (menu.open && e.key === "Escape") { e.stopPropagation(); closeMenu(); } }
</script>

<svelte:window onpointerdown={onDown} onkeydown={onKey} onblur={closeMenu} onresize={closeMenu} />

{#if menu.open}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="cmenu" role="menu" tabindex="-1" bind:this={el} style="left:{pos.x}px;top:{pos.y}px" oncontextmenu={(e) => e.preventDefault()}>
    {#each menu.items as it}
      {#if it.sep}
        <div class="sep"></div>
      {:else}
        <button role="menuitem" class:danger={it.danger} disabled={it.disabled} onclick={() => { closeMenu(); it.onclick?.(); }}>{it.label}</button>
      {/if}
    {/each}
  </div>
{/if}

<style>
  .cmenu { position: fixed; z-index: 100; min-width: 130px; padding: 4px; border-radius: 8px; background: var(--bg); border: 1px solid var(--line); box-shadow: 0 8px 24px rgba(0,0,0,.22); }
  button { display: block; width: 100%; text-align: left; padding: 4px 10px; border: none; border-radius: 5px; background: transparent; cursor: pointer; font-size: .92em; }
  button:hover:not(:disabled) { background: var(--accent-soft); }
  button:disabled { color: var(--fg3); cursor: default; }
  button.danger { color: var(--danger); }
  .sep { height: 1px; margin: 4px 2px; background: var(--line); }
</style>
