<script lang="ts" module>
  // SF Symbols 를 흉내 낸 선 아이콘 모음 (요약·PR·Teleport·설정 화면 공용). 크기는 em 이라 --scale 을 따른다.
  export type SymName =
    | "gear" | "pencil" | "copy" | "refresh" | "book" | "chevron-left" | "chevron-right" | "chevron-down" | "x" | "check"
    | "link" | "globe" | "sparkles" | "tag" | "doc" | "info" | "window" | "palette" | "branch" | "terminal" | "bell"
    | "arrow-right-circle" | "minus-circle" | "lock" | "key" | "folder" | "external" | "plus" | "play" | "stop"
    | "jira" | "notes" | "tabs" | "plug" | "power" | "wand" | "warning" | "check-circle" | "x-circle" | "dot" | "list-check"
    | "arrow-down-circle" | "person" | "eye-slash" | "trash" | "qr";
</script>

<script lang="ts">
  let { name, size = 1, weight = 1.6 }: { name: SymName; size?: number; weight?: number } = $props();
</script>

<svg class="sym" width="{size}em" height="{size}em" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width={weight}
  stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
  {#if name === "gear"}<circle cx="8" cy="8" r="2.2" /><path d="M8 1.6v1.6M8 12.8v1.6M14.4 8h-1.6M3.2 8H1.6M12.5 3.5l-1.1 1.1M4.6 11.4l-1.1 1.1M12.5 12.5l-1.1-1.1M4.6 4.6L3.5 3.5" /><circle cx="8" cy="8" r="4.6" />
  {:else if name === "pencil"}<path d="M10.8 2.7l2.5 2.5-7.6 7.6-3.2.7.7-3.2 7.6-7.6zM9.6 3.9l2.5 2.5" />
  {:else if name === "copy"}<rect x="5.5" y="5.5" width="8" height="8" rx="1.6" /><path d="M10.5 5.5V3.6A1.1 1.1 0 0 0 9.4 2.5H3.6a1.1 1.1 0 0 0-1.1 1.1v5.8a1.1 1.1 0 0 0 1.1 1.1h1.9" />
  {:else if name === "refresh"}<path d="M13 8a5 5 0 1 1-1.6-3.7M13 2.5v3h-3" />
  {:else if name === "book"}<path d="M3 3.2A1.2 1.2 0 0 1 4.2 2H13v10.5H4.2A1.2 1.2 0 0 0 3 13.7zM3 13.7A1.3 1.3 0 0 0 4.3 15H13M6 5h4.5" />
  {:else if name === "chevron-left"}<path d="M10 3L5 8l5 5" />
  {:else if name === "chevron-right"}<path d="M6 3l5 5-5 5" />
  {:else if name === "chevron-down"}<path d="M3 6l5 5 5-5" />
  {:else if name === "x"}<path d="M4 4l8 8M12 4l-8 8" />
  {:else if name === "check"}<path d="M3 8.5l3.5 3.5L13 4.5" />
  {:else if name === "link"}<path d="M6.8 9.2a2.6 2.6 0 0 0 3.7 0l2.2-2.2a2.6 2.6 0 0 0-3.7-3.7l-.9.9M9.2 6.8a2.6 2.6 0 0 0-3.7 0L3.3 9a2.6 2.6 0 0 0 3.7 3.7l.9-.9" />
  {:else if name === "globe"}<circle cx="8" cy="8" r="6" /><path d="M2 8h12M8 2c1.8 1.7 2.6 3.7 2.6 6S9.8 12.3 8 14M8 2C6.2 3.7 5.4 5.7 5.4 8s.8 4.3 2.6 6" />
  {:else if name === "sparkles"}<path d="M7 2.5l1.2 3.3L11.5 7 8.2 8.2 7 11.5 5.8 8.2 2.5 7l3.3-1.2zM12.3 9.8l.5 1.4 1.4.5-1.4.5-.5 1.4-.5-1.4-1.4-.5 1.4-.5zM12 1.8l.4 1 1 .4-1 .4-.4 1-.4-1-1-.4 1-.4z" />
  {:else if name === "tag"}<path d="M2.5 2.5h5.3l6 6-5.3 5.3-6-6zM5.3 5.3h.01" />
  {:else if name === "doc"}<path d="M9.5 1.8H4.3a1 1 0 0 0-1 1v10.4a1 1 0 0 0 1 1h7.4a1 1 0 0 0 1-1V5zM9.5 1.8V5h3.2M5.6 8h4.8M5.6 10.5h4.8" />
  {:else if name === "info"}<circle cx="8" cy="8" r="6" /><path d="M8 7.2v4M8 4.9h.01" />
  {:else if name === "window"}<rect x="1.8" y="3" width="12.4" height="10" rx="1.6" /><path d="M1.8 5.8h12.4M4 4.4h.01M5.6 4.4h.01" />
  {:else if name === "palette"}<path d="M8 1.8a6.2 6.2 0 1 0 0 12.4c.9 0 1.3-.6 1.3-1.2 0-.8-.6-1.1-.6-1.8 0-.7.6-1.2 1.3-1.2h1.5a2.7 2.7 0 0 0 2.7-2.7C14.2 4.3 11.5 1.8 8 1.8z" /><circle cx="5" cy="7" r=".6" /><circle cx="7.2" cy="4.6" r=".6" /><circle cx="10.2" cy="5" r=".6" />
  {:else if name === "branch"}<circle cx="4.5" cy="3.5" r="1.5" /><circle cx="4.5" cy="12.5" r="1.5" /><circle cx="11.5" cy="5" r="1.5" /><path d="M4.5 5v6M11.5 6.5c0 3-7 2.2-7 4.5" />
  {:else if name === "terminal"}<rect x="1.8" y="2.8" width="12.4" height="10.4" rx="1.6" /><path d="M4.5 6.2l2 1.8-2 1.8M8 10h3.5" />
  {:else if name === "bell"}<path d="M4 11.5V7.3a4 4 0 0 1 8 0v4.2l1.2 1.2H2.8zM6.7 14a1.4 1.4 0 0 0 2.6 0" />
  {:else if name === "arrow-right-circle"}<circle cx="8" cy="8" r="6" fill="currentColor" stroke="none" /><path d="M5.3 8h5.2M8.5 5.8L10.7 8l-2.2 2.2" stroke="var(--on-accent, #fff)" />
  {:else if name === "minus-circle"}<circle cx="8" cy="8" r="6" /><path d="M5.3 8h5.4" />
  {:else if name === "lock"}<rect x="3.2" y="7" width="9.6" height="7" rx="1.6" /><path d="M5.3 7V5a2.7 2.7 0 0 1 5.4 0v2" />
  {:else if name === "key"}<circle cx="5.2" cy="10.8" r="2.7" /><path d="M7.2 8.8L13.5 2.5M11.4 4.6l1.6 1.6M9.8 6.2l1.2 1.2" />
  {:else if name === "folder"}<path d="M1.8 4.2a1.2 1.2 0 0 1 1.2-1.2h3.3l1.5 1.6H13a1.2 1.2 0 0 1 1.2 1.2v6.8A1.2 1.2 0 0 1 13 13.8H3a1.2 1.2 0 0 1-1.2-1.2z" />
  {:else if name === "external"}<path d="M9.5 2.5h4v4M13.5 2.5L7.5 8.5M12 9.5v3.3a1.2 1.2 0 0 1-1.2 1.2H3.2A1.2 1.2 0 0 1 2 12.8V5.2A1.2 1.2 0 0 1 3.2 4h3.3" />
  {:else if name === "plus"}<path d="M8 3v10M3 8h10" />
  {:else if name === "play"}<path d="M5 3.2l7.5 4.8L5 12.8z" fill="currentColor" />
  {:else if name === "stop"}<rect x="4" y="4" width="8" height="8" rx="1.2" fill="currentColor" />
  {:else if name === "jira"}<rect x="1.8" y="3.2" width="12.4" height="9.6" rx="1.6" /><path d="M4.5 3.2v9.6M11.5 3.2v9.6M1.8 6.4h2.7M1.8 9.6h2.7M11.5 6.4h2.7M11.5 9.6h2.7" />
  {:else if name === "notes"}<rect x="2.5" y="2" width="11" height="12" rx="1.6" /><path d="M2.5 5h11M5 7.8h6M5 10.4h6" />
  {:else if name === "tabs"}<rect x="1.8" y="3" width="12.4" height="10" rx="1.6" /><path d="M1.8 6h12.4M6 3v3M10 3v3" />
  {:else if name === "plug"}<path d="M5.5 2v3.2M10.5 2v3.2M3.5 5.2h9v1.6a4.5 4.5 0 0 1-9 0zM8 11.3V14" />
  {:else if name === "power"}<path d="M8 2v5.5M4.4 4.4a5 5 0 1 0 7.2 0" />
  {:else if name === "wand"}<path d="M2.5 13.5l8-8M9.3 4.3l2.4 2.4M12 1.8v2M13 2.8h-2M14 6v1.6M14.8 6.8h-1.6M5.6 1.8v1.6M6.4 2.6H4.8" />
  {:else if name === "warning"}<path d="M8 2.2l6.2 11H1.8zM8 6.5v3M8 11.4h.01" />
  {:else if name === "check-circle"}<circle cx="8" cy="8" r="6" /><path d="M5.3 8.2l1.9 1.9 3.6-3.8" />
  {:else if name === "x-circle"}<circle cx="8" cy="8" r="6" /><path d="M5.8 5.8l4.4 4.4M10.2 5.8l-4.4 4.4" />
  {:else if name === "dot"}<circle cx="8" cy="8" r="3.2" fill="currentColor" stroke="none" />
  {:else if name === "list-check"}<path d="M2.5 4l1 1 1.6-1.8M2.5 9l1 1 1.6-1.8M7.5 4.5h6M7.5 9.5h6M7.5 13h6" />
  {:else if name === "arrow-down-circle"}<circle cx="8" cy="8" r="6" /><path d="M8 5v5.5M5.8 8.5L8 10.7l2.2-2.2" />
  {:else if name === "person"}<circle cx="8" cy="5.5" r="2.7" /><path d="M2.8 14a5.2 5.2 0 0 1 10.4 0" />
  {:else if name === "eye-slash"}<path d="M2 8s2.2-4.2 6-4.2S14 8 14 8s-2.2 4.2-6 4.2S2 8 2 8zM2.5 2.5l11 11" /><circle cx="8" cy="8" r="1.8" />
  {:else if name === "trash"}<path d="M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.6 8.5h5.8l.6-8.5" />
  {:else if name === "qr"}<rect x="2" y="2" width="4.5" height="4.5" rx=".6" /><rect x="9.5" y="2" width="4.5" height="4.5" rx=".6" /><rect x="2" y="9.5" width="4.5" height="4.5" rx=".6" /><path d="M9.5 9.5h1.8v1.8M14 9.5v.01M12.2 12.2H14V14M9.5 14h.01" />
  {/if}
</svg>

<style>
  .sym { flex: none; vertical-align: -0.125em; }
</style>
