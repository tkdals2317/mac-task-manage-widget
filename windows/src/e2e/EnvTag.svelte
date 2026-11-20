<script lang="ts">
  // 환경 표시 (DV / ST / ST2 / PR). PR 은 운영이라 주황. (Mac E2EEnvTag)
  import type { E2EEnv } from "../lib/e2eCore";
  let { env }: { env: E2EEnv } = $props();
</script>

<span class="et" class:pr={env === "PR"}>{env}</span>

<style>
  .et { flex: none; font-size: 0.78em; font-weight: 600; padding: 0 4px; border-radius: 3px; color: color-mix(in srgb, var(--fg) 75%, transparent); background: var(--fill2); }
  .et.pr { color: var(--warn); background: var(--warn-soft); }
</style>
