<script lang="ts">
  // PASS / FAIL / BLOCKED / SKIPPED 작은 알약. count 를 주면 "FAIL 2". (Mac E2EVerdictBadge)
  import type { Verdict } from "../lib/e2eCore";
  let { verdict, count }: { verdict: Verdict | null; count?: number } = $props();
  const tint = $derived(verdict === "PASS" ? "var(--ok)" : verdict === "FAIL" ? "var(--danger)" : verdict === "BLOCKED" ? "var(--warn)" : "var(--fg2)");
</script>

<span class="vb" style="--t:{tint}">{[verdict ?? "?", count].filter((x) => x !== undefined).join(" ")}</span>

<style>
  .vb {
    flex: none; font-size: 0.78em; font-weight: 700; color: var(--t); padding: 0 6px; border-radius: 999px; line-height: 1.5;
    background: color-mix(in srgb, var(--t) 16%, transparent); white-space: nowrap;
  }
</style>
