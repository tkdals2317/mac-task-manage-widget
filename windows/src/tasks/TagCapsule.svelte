<script lang="ts">
  import { isGray, safeHex, type Tag } from "../lib/tags";
  let { tag }: { tag: Tag } = $props();
  const hex = $derived(safeHex(tag.colorHex));
  const gray = $derived(isGray(hex));
</script>

<span class="cap" class:gray style="--c:{hex}">{tag.name}</span>

<style>
  .cap {
    font-size: 0.88em; padding: 1px 6px; border-radius: 999px; white-space: nowrap;
    color: var(--c); background: color-mix(in srgb, var(--c) 20%, transparent);
  }
  .cap.gray { color: color-mix(in srgb, var(--fg) 75%, transparent); background: var(--fill2); }
</style>
