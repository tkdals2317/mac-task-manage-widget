<script lang="ts">
  // 상태 변경 팝오버: 맨 위에 지금 상태(✓), 아래에 바꿀 수 있는 상태를 종류 색 점과 함께.
  // 목록 조회 때 같이 받은 transitions 가 있으면 바로 보여주고, 없을 때만 따로 받는다.
  import { onMount } from "svelte";
  import { JiraError, type JiraIssue, type JiraTransition } from "../lib/jira";
  import { loadTransitions, transitionJira } from "./jiraState.svelte";
  import Icon from "./Icon.svelte";
  import Popover from "./Popover.svelte";
  import { statusColor } from "./statusColor";

  let { issue, anchor, onclose }: { issue: JiraIssue; anchor: HTMLElement; onclose: () => void } = $props();
  let items = $state<JiraTransition[] | undefined>(undefined);
  let error = $state<string | null>(null);

  const list = $derived(items ?? issue.transitions);
  const next = $derived((list ?? []).filter((t) => t.toName !== issue.status));

  onMount(async () => {
    if (issue.transitions) return;
    try { items = await loadTransitions(issue.id); }
    catch (e) { error = e instanceof JiraError ? e.userMessage : e instanceof Error ? e.message : String(e); }
  });
</script>

<Popover {anchor} {onclose}>
  <div class="tr">
    <div class="hdr">현재</div>
    <div class="item cur">
      <span class="dot" style="background:{statusColor(issue.statusCategory)}"></span>
      <span class="name">{issue.status}</span>
      <span class="grow"></span><Icon name="check" size={0.85} />
    </div>
    <div class="hdr second">바꾸기</div>
    {#if error}
      <div class="note err">{error}</div>
    {:else if list}
      {#if next.length === 0}<div class="note muted">가능한 전환 없음</div>{/if}
      {#each next as t (t.id)}
        <button class="item" onclick={() => { onclose(); void transitionJira(issue.id, t); }}>
          <span class="dot" style="background:{statusColor(t.toCategory)}"></span>
          <span class="name">{t.toName}</span>
        </button>
      {/each}
    {:else}
      <div class="note muted">불러오는 중…</div>
    {/if}
  </div>
</Popover>

<style>
  .tr { display: flex; flex-direction: column; gap: 1px; min-width: 150px; margin: -4px; }
  .hdr { font-size: 0.88em; font-weight: 500; color: var(--fg2); padding: 2px 8px 1px; }
  .second { margin-top: 4px; }
  .item { display: flex; align-items: center; gap: 7px; padding: 5px 8px; border-radius: 6px; border: none; background: transparent; cursor: pointer; text-align: left; }
  .item:hover { background: var(--fill2); }
  .item.cur { background: var(--accent-soft); color: var(--accent); font-weight: 600; cursor: default; }
  .dot { width: 7px; height: 7px; border-radius: 50%; flex: none; }
  .grow { flex: 1; min-width: 8px; }
  .note { padding: 4px 8px; max-width: 220px; }
  .err { color: var(--danger); font-size: 0.92em; }
</style>
