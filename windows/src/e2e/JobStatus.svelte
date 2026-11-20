<script lang="ts">
  // 이력·상세에서 job 상태 한 덩어리: 실행 중 · 대기 · 판정 수 · 실패/취소. (Mac E2EJobStatusView)
  import { onMount } from "svelte";
  import { e2e } from "../lib/e2e.svelte";
  import { VERDICT_ORDER, verdictCounts, statusLabel, type Job } from "../lib/e2eCore";
  import VerdictBadge from "./VerdictBadge.svelte";

  let { job }: { job: Job } = $props();
  let now = $state(Date.now());
  onMount(() => { const t = setInterval(() => (now = Date.now()), 30_000); return () => clearInterval(t); });

  const res = $derived(e2e.results[job.id]);
  const queuedAt = $derived(e2e.queued.indexOf(job.id));
  const mins = $derived(Math.floor((now - (e2e.runningSince ?? job.createdAt.getTime())) / 60_000));
</script>

{#if e2e.running === job.id}
  <span class="st"><span class="spin dot"></span>실행 중 · {mins < 1 ? "1분 미만" : `${mins}분`}</span>
{:else if queuedAt >= 0}
  <span class="st">대기 {queuedAt + 1}번째</span>
{:else if job.status === "done" && res?.kind === "ok"}
  {@const counts = verdictCounts(res.result)}
  <span class="vbs">
    {#each VERDICT_ORDER as v (v)}{#if counts[v] !== undefined}<VerdictBadge verdict={v} count={counts[v]} />{/if}{/each}
  </span>
{:else}
  <span class="st lbl" class:bad={job.status === "failed"}>{statusLabel(job.status)}</span>
{/if}

<style>
  .st { display: inline-flex; align-items: center; gap: 4px; font-size: 0.88em; color: var(--fg2); white-space: nowrap; }
  .lbl { font-weight: 500; }
  .lbl.bad { color: var(--danger); }
  .vbs { display: inline-flex; gap: 3px; }
  .dot { width: 0.8em; height: 0.8em; border-radius: 50%; border: 2px solid var(--line); border-top-color: var(--accent); }
</style>
