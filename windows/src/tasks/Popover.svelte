<script lang="ts">
  // 앵커(요소 또는 좌표) 옆에 position:fixed 로 띄우는 팝오버. 바깥 클릭·Esc 로 닫힌다.
  // 앵커 요소 안의 클릭은 "바깥"으로 치지 않아서 트리거 버튼이 열기/닫기 토글을 맡을 수 있다.
  import type { Snippet } from "svelte";

  type Anchor = HTMLElement | { x: number; y: number };
  let { anchor, align = "end", onclose, children }: {
    anchor: Anchor; align?: "start" | "end"; onclose: () => void; children: Snippet;
  } = $props();

  let el: HTMLDivElement | undefined = $state();
  let pos = $state({ left: 0, top: 0, ready: false });

  function place() {
    if (!el) return;
    const r = anchor instanceof HTMLElement
      ? anchor.getBoundingClientRect()
      : { left: anchor.x, right: anchor.x, top: anchor.y, bottom: anchor.y };
    const w = el.offsetWidth, h = el.offsetHeight, m = 8;
    const wantLeft = align === "end" ? r.right - w : r.left;
    const left = Math.max(m, Math.min(wantLeft, innerWidth - w - m));
    const below = r.bottom + 4;
    const top = below + h <= innerHeight - m ? below : Math.max(m, r.top - h - 4);
    pos = { left, top, ready: true };
  }

  $effect(() => {
    if (!el) return;
    place();
    const ro = new ResizeObserver(place);
    ro.observe(el);
    const down = (e: PointerEvent) => {
      const t = e.target as Node;
      if (el!.contains(t) || (anchor instanceof HTMLElement && anchor.contains(t))) return;
      onclose();
    };
    const key = (e: KeyboardEvent) => {
      if (e.key === "Escape") { e.stopPropagation(); onclose(); } // 패널 숨김으로 번지지 않게
    };
    document.addEventListener("pointerdown", down, true);
    document.addEventListener("keydown", key);
    return () => {
      ro.disconnect();
      document.removeEventListener("pointerdown", down, true);
      document.removeEventListener("keydown", key);
    };
  });
</script>

<div class="popover" bind:this={el} style="position:fixed;left:{pos.left}px;top:{pos.top}px;visibility:{pos.ready ? 'visible' : 'hidden'}">
  {@render children()}
</div>
