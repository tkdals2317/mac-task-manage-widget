<script lang="ts">
  // SF Symbols 대신 쓰는 작은 선 아이콘 (24x24 격자).
  const P: Record<string, string[]> = {
    note: ["M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z", "M14 3v6h6", "M8 13h8", "M8 17h5"],
    pin: ["M12 17v5", "M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"],
    pinoff: ["M12 17v5", "M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z", "M3 3l18 18"],
    lock: ["M5 11h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2z", "M7 11V7a5 5 0 0 1 10 0v4"],
    lockopen: ["M5 11h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2z", "M7 11V7a5 5 0 0 1 9.9-1"],
    x: ["M18 6 6 18", "M6 6l12 12"],
    check: ["M20 6 9 17l-5-5"],
    copy: ["M11 9h9a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-9a2 2 0 0 1-2-2v-9a2 2 0 0 1 2-2z", "M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"],
    pencil: ["M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"],
    refresh: ["M21 12a9 9 0 1 1-3-6.7L21 8", "M21 3v5h-5"],
    down: ["m6 9 6 6 6-6"],
    right: ["m9 6 6 6-6 6"],
    doc: ["M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z", "M14 2v6h6", "M16 13H8", "M16 17H8", "M10 9H8"],
    globe: ["M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0z", "M2 12h20", "M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"],
    code: ["m16 18 6-6-6-6", "M8 6l-6 6 6 6"],
    chart: ["M3 3v18h18", "M7 14l4-4 4 4 5-6"],
    palette: ["M12 22a10 10 0 1 1 10-10c0 3-2 4-4 4h-2a2 2 0 0 0-1.5 3.3A2 2 0 0 1 12 22z"],
    ticket: ["M2 9a3 3 0 0 1 0 6v2a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-2a3 3 0 0 1 0-6V7a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2z", "M13 5v2", "M13 17v2", "M13 11v2"],
    hash: ["M4 9h16", "M4 15h16", "M10 3 8 21", "M16 3l-2 18"],
  };
  let { name, fill = false, size = "1em", bold = false }: { name: string; fill?: boolean; size?: string; bold?: boolean } = $props();
  // docrich / 모르는 이름은 문서·지구본으로
  const key = $derived(name === "docrich" ? "doc" : name in P ? name : "globe");
</script>

<svg width={size} height={size} viewBox="0 0 24 24" fill={fill ? "currentColor" : "none"} stroke="currentColor"
  stroke-width={bold ? 2.6 : 1.8} stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
  {#each P[key] as d}<path {d} />{/each}
</svg>
