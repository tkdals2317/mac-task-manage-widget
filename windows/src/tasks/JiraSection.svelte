<script lang="ts">
  import { openUrl } from "@tauri-apps/plugin-opener";
  import {
    JIRA_TOKEN_URL, commonPrefix, filterByVersion, groupedByStatus, groupedByVersion, displayVersion, parseVersionFilter,
  } from "../lib/jira";
  import { native } from "../lib/native";
  import { settings } from "../lib/settings.svelte";
  import { jira, refreshJira } from "./jiraState.svelte";
  import JiraRow from "./JiraRow.svelte";

  const filter = $derived(parseVersionFilter(settings.jiraVersionFilter));
  const filtered = $derived(filterByVersion(jira.issues, filter));
  const prefix = $derived(commonPrefix(jira.issues.flatMap((i) => i.fixVersions)));
  const groupBy = $derived(settings.jiraGroupByVersion);
  // 필터 중엔 버전 칩이 필요 없다. 버전별로 묶었을 땐 버전 칩이 헤더에 있으니 칩을 안 단다 (Mac 은 .status = 칩 없음).
  const trailing = $derived(filter.kind !== "all" || groupBy ? "none" : "version");
  const settled = $derived(jira.error === null && jira.updatedAt !== null);
  const time = $derived(jira.updatedAt?.toLocaleTimeString("ko-KR", { hour: "numeric", minute: "2-digit" }) ?? "");

  // 갱신 주기마다 다시 불러온다 (설정이 바뀌면 타이머를 새로). 패널이 숨겨져 있으면 건너뜀.
  $effect(() => {
    const ms = Math.max(1, settings.jiraRefreshMinutes) * 60_000;
    void refreshJira();
    const t = setInterval(() => { if (document.visibilityState === "visible") void refreshJira(); }, ms);
    return () => clearInterval(t);
  });
</script>

<div class="jira">
  {#if !jira.configured}
    <div class="setup">
      <button class="btn" onclick={() => native.openSettings("jira")}>설정에서 Jira 토큰 입력</button>
      <button class="btn" onclick={() => openUrl(JIRA_TOKEN_URL)}>토큰 발급 ↗</button>
    </div>
  {:else}
    {#if groupBy}
      {#each groupedByVersion(filtered) as g (g.title ?? "\u0000none")}
        <div class="ghdr">{g.title === null ? "버전 없음" : displayVersion(g.title, prefix)} · {g.issues.length}</div>
        {#each g.issues as i (i.id)}<JiraRow issue={i} {prefix} {trailing} />{/each}
      {/each}
    {:else}
      {#each groupedByStatus(filtered) as g (g.status)}
        <div class="ghdr">{g.status} · {g.issues.length}</div>
        {#each g.issues as i (i.id)}<JiraRow issue={i} {prefix} {trailing} />{/each}
      {/each}
    {/if}
    {#if filtered.length === 0 && filter.kind !== "all" && settled}
      <div class="empty muted">이 버전의 미완료 이슈 없음</div>
    {/if}
    {#if jira.issues.length === 0 && filter.kind === "all" && settled}
      <div class="empty faint">미완료 이슈 없음</div>
    {/if}
    {#if jira.truncated}<div class="trunc muted">100건까지만 표시</div>{/if}
    <div class="footer muted">
      {#if jira.error}
        <span class="err">{jira.error}</span>
        <button class="btn mini" onclick={() => native.openSettings("jira")}>설정</button>
      {:else if jira.updatedAt}
        <span>↻ {time} 갱신</span>
      {/if}
      <span class="grow"></span>
      {#if jira.loading}<span class="spin" aria-label="불러오는 중"></span>{/if}
    </div>
  {/if}
</div>

<style>
  .setup { display: flex; gap: 8px; padding: 8px 0; flex-wrap: wrap; }
  .setup .btn { font-size: 0.92em; padding: 2px 10px; }
  .ghdr { font-size: 0.92em; font-weight: 600; color: var(--fg2); padding: 8px 0 2px; }
  .empty { padding: 8px 0; }
  .trunc { font-size: 0.88em; padding-top: 4px; }
  .footer { display: flex; align-items: center; gap: 6px; font-size: 0.92em; padding-top: 6px; }
  .err { color: var(--danger); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; }
  .mini { padding: 0 8px; font-size: 0.9em; flex: none; }
  .grow { flex: 1; }
  .spin { width: 0.9em; height: 0.9em; border-radius: 50%; border: 2px solid var(--line); border-top-color: var(--accent); animation: spin 0.8s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>
