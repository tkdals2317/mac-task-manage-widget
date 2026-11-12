<script lang="ts">
  // 선택·복사가 되는 읽기 전용 Markdown. 링크는 브라우저로 연다.
  import { openUrl } from "@tauri-apps/plugin-opener";
  import { renderMarkdown } from "./markdown";
  let { markdown }: { markdown: string } = $props();

  function click(e: MouseEvent) {
    const a = (e.target as HTMLElement).closest("a[data-ext]") as HTMLAnchorElement | null;
    if (!a) return;
    e.preventDefault();
    openUrl(a.href).catch(() => {});
  }
</script>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="md selectable" onclick={click}>{@html renderMarkdown(markdown)}</div>

<style>
  .md { font-size: 0.93em; line-height: 1.5; word-break: break-word; }
  .md :global(h1) { font-size: 1.16em; font-weight: 700; margin: 0 0 7px; }
  .md :global(h2) { font-size: 1em; font-weight: 650; margin: 10px 0 3px; }
  .md :global(h3) { font-size: 0.96em; font-weight: 600; margin: 8px 0 2px; }
  .md :global(p) { margin: 0 0 3px; }
  .md :global(.li) { position: relative; padding-left: 14px; }
  .md :global(.li)::before { content: "•"; position: absolute; left: 3px; color: var(--fg2); }
  .md :global(.li2) { padding-left: 28px; }
  .md :global(.li2)::before { content: "◦"; left: 17px; }
  .md :global(.gap) { height: 2px; }
  .md :global(code) { font-family: "Cascadia Mono", Consolas, monospace; font-size: 0.92em; padding: 0 3px; border-radius: 3px; background: var(--fill2); }
  .md :global(a) { color: var(--accent-text); text-decoration: none; }
  .md :global(a:hover) { text-decoration: underline; }
</style>
