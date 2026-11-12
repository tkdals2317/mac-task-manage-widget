<script lang="ts">
  // 작은 선 아이콘 (SF Symbols 대신). 크기는 em 이라 --scale 을 따른다.
  let { name, size = 1 }: {
    name: "chevron-right" | "chevron-down" | "check" | "square" | "square-check" | "circle" | "circle-check" | "x" | "calendar" | "refresh" | "trash" | "list" | "split";
    size?: number;
  } = $props();
</script>

<svg width="{size}em" height="{size}em" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
  {#if name === "chevron-right"}<path d="M6 3l5 5-5 5" />
  {:else if name === "chevron-down"}<path d="M3 6l5 5 5-5" />
  {:else if name === "check"}<path d="M3 8.5l3.5 3.5L13 4.5" />
  {:else if name === "square"}<rect x="2.5" y="2.5" width="11" height="11" rx="2.5" />
  {:else if name === "square-check"}<rect x="2.5" y="2.5" width="11" height="11" rx="2.5" fill="currentColor" /><path d="M5 8.3l2.2 2.2L11 6" stroke="var(--bg)" />
  {:else if name === "circle"}<circle cx="8" cy="8" r="5.5" />
  {:else if name === "circle-check"}<circle cx="8" cy="8" r="5.8" fill="currentColor" /><path d="M5.3 8.2l2 2L10.8 6" stroke="var(--bg)" />
  {:else if name === "x"}<path d="M4 4l8 8M12 4l-8 8" />
  {:else if name === "calendar"}<rect x="2.5" y="3.5" width="11" height="10" rx="2" /><path d="M2.5 6.5h11M5.5 2v3M10.5 2v3" />
  {:else if name === "refresh"}<path d="M13 8a5 5 0 1 1-1.6-3.7M13 2.5v3h-3" />
  {:else if name === "trash"}<path d="M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.6 8.5h5.8l.6-8.5" />
  {:else if name === "list"}<path d="M3 4l1 1 1.6-1.8M3 9l1 1 1.6-1.8M8 4.5h5M8 9.5h5M8 13h5" />
  {:else if name === "split"}<rect x="2.5" y="2.5" width="11" height="11" rx="2" /><path d="M2.5 8h11" />
  {/if}
</svg>
