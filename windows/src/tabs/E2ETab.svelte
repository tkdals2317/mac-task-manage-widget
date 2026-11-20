<script lang="ts">
  // E2E 탭 (Mac E2EView): 이슈를 고르고 환경을 골라 Aside 로 검증을 돌린다. 결과를 누르면 같은 자리에서 상세로 바뀐다.
  import { onMount } from "svelte";
  import { openUrl } from "@tauri-apps/plugin-opener";
  import Sym from "../lib/Sym.svelte";
  import Confirm from "../lib/Confirm.svelte";
  import Icon from "../tasks/Icon.svelte";
  import Menu, { type MenuItem } from "../tasks/Menu.svelte";
  import SectionHeader from "../tasks/SectionHeader.svelte";
  import JiraVersionMenu from "../tasks/JiraVersionMenu.svelte";
  import { jira, refreshJira } from "../tasks/jiraState.svelte";
  import { checkAside, cancelJob, job as jobOf, commentableIssues, commentId, deleteJob, e2e, existingScreenshots, isRunning, issueLink, openLog, openResult, reload, retry, revealJob, exportReport, submit } from "../lib/e2e.svelte";
  import { e2eURLKey, setSetting, settings } from "../lib/settings.svelte";
  import { commonPrefix, displayVersion, filterByVersion, groupedByVersion, parseVersionFilter, type JiraIssue } from "../lib/jira";
  import { forcesReadOnly, parseEnv, parseIssueKeys, selectableEnvs, type E2EEnv, type IssueResult, type Job } from "../lib/e2eCore";
  import EnvTag from "../e2e/EnvTag.svelte";
  import JobStatus from "../e2e/JobStatus.svelte";
  import ModelMenu from "../e2e/ModelMenu.svelte";
  import SetupSection from "../e2e/SetupSection.svelte";
  import VerdictBadge from "../e2e/VerdictBadge.svelte";
  import E2EResult from "../e2e/E2EResult.svelte";
  import CommentDialog, { type CommentTarget } from "../e2e/CommentDialog.svelte";
  import { native } from "../lib/native";

  let confirmPR = $state(false);
  /** PR 환경 job 을 다시 실행하기 전 확인 중인 job id */
  let prRetry = $state<string | null>(null);
  let commentTarget = $state<CommentTarget | null>(null);
  let menu = $state<{ job: Job; x: number; y: number } | null>(null);

  /** 저장된 환경이 지금 고를 수 없는 것(PR 을 끈 뒤)이면 ST 로 본다. */
  const env = $derived.by<E2EEnv>(() => {
    const e = parseEnv(settings.e2eEnv) ?? "ST";
    return selectableEnvs(settings.e2eAllowPR).includes(e) ? e : "ST";
  });
  const envURL = $derived(String(settings[e2eURLKey(env)]));

  /** 실행할 키: 목록에서 고른 것(목록 순서) → 목록에 없는 고른 것 → 직접 입력. 중복 없이. */
  const keys = $derived.by(() => {
    const listed = jira.issues.map((i) => i.id), sel = new Set(e2e.draftSelected);
    const ordered = [...listed.filter((k) => sel.has(k)), ...[...sel].filter((k) => !listed.includes(k)).sort(), ...parseIssueKeys(e2e.draftKeys)];
    return [...new Set(ordered)];
  });

  const filtered = $derived(filterByVersion(jira.issues, parseVersionFilter(settings.jiraVersionFilter)));
  const prefix = $derived(commonPrefix(jira.issues.flatMap((i) => i.fixVersions)));

  onMount(() => {
    void reload();
    if (!e2e.report) void checkAside();
    if (!jira.updatedAt) void refreshJira();
  });

  const toggle = (k: string) => { e2e.draftSelected = e2e.draftSelected.includes(k) ? e2e.draftSelected.filter((x) => x !== k) : [...e2e.draftSelected, k]; };

  function doSubmit() {
    const titles = Object.fromEntries(jira.issues.map((i) => [i.id, i.summary]));
    void submit(env, keys, e2e.draftNotes, titles);
  }

  // ---- 이력 ----
  const fmtTime = (d: Date) => `${String(d.getMonth() + 1).padStart(2, "0")}/${String(d.getDate()).padStart(2, "0")} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  const posted = (j: Job, key: string) => { const v = j.jiraComments[key]; return v ? fmtTime(new Date(v)) : null; };
  const links = (j: Job) => j.issues.flatMap((r) => { const url = issueLink(r); return url ? [{ key: r.key, title: r.title, url }] : []; });
  const doRetry = (j: Job) => (forcesReadOnly(j.env) ? (prRetry = j.id) : void retry(j.id));
  async function askComment(j: Job, issue: IssueResult) {
    commentTarget = { job: j, issue, shots: (await existingScreenshots(j.id, issue)).length };
  }
  const open = (url: string) => void openUrl(url).catch(() => {});
  const menuTitle = (j: Job, i: IssueResult) => { const p = posted(j, i.key); return `${i.key} · ${i.verdict ?? "?"}${p ? ` · ${p} 남김` : ""}`; };

  // 행 단위 작은 메뉴 (이슈가 여럿일 때 고른다)
  let pick = $state<{ el: HTMLElement; items: MenuItem[] } | null>(null);
  function pickMenu(e: MouseEvent, items: MenuItem[]) { pick = { el: e.currentTarget as HTMLElement, items }; }

  function rowMenu(j: Job): MenuItem[] {
    const issues = commentableIssues(j), ls = links(j), active = isRunning(j.id);
    const out: MenuItem[] = [{ label: "결과 보기", onselect: () => openResult(j.id) }];
    for (const l of ls) out.push({ label: ls.length === 1 ? "Jira 에서 열기" : `Jira 에서 열기 · ${l.key}`, onselect: () => open(l.url) });
    out.push({ label: "탐색기에서 보기", onselect: () => revealJob(j.id) }, { label: "로그 열기", onselect: () => openLog(j.id) });
    if (active) out.push({ label: "취소", onselect: () => cancelJob(j.id) });
    else {
      out.push({ label: "다시 실행", onselect: () => doRetry(j) });
      for (const i of issues) out.push({ label: issues.length === 1 ? "Jira 댓글로 남기기" : `Jira 댓글로 남기기 · ${menuTitle(j, i)}`, disabled: e2e.commenting !== null, onselect: () => askComment(j, i) });
      out.push({ label: "파일로 내보내기", onselect: () => exportReport(j.id) }, { label: "삭제", onselect: () => deleteJob(j.id) });
    }
    return out;
  }

  const commentNote = (j: Job) => {
    const n = e2e.commentNote;
    const issues = commentableIssues(j);
    const i = n ? issues.find((x) => commentId(j.id, x.key) === n.id) : undefined;
    return n && i ? (issues.length === 1 ? n.text : `${i.key} · ${n.text}`) : null;
  };
</script>

{#if e2e.openJobId && jobOf(e2e.openJobId)}
  <E2EResult job={jobOf(e2e.openJobId)!} />
{:else}
  <div class="tab scroll">
    <div class="envrow">
      {#each selectableEnvs(settings.e2eAllowPR) as e (e)}
        <button class="chip {e === env ? 'soft' : 'plain'}" onclick={() => setSetting("e2eEnv", e)}><Sym name={e === env ? "check" : "dot"} size={0.8} />{e}</button>
      {/each}
      <span class="eurl" class:none={!envURL} title={envURL || "설정 > E2E 에서 환경 주소를 넣어 주세요"}>{envURL || "주소 없음"}</span>
      <span class="grow"></span>
      <button class="icon-btn" title="E2E 설정" aria-label="E2E 설정" onclick={() => native.openSettings("e2e")}><Sym name="gear" size={1} /></button>
    </div>

    <SetupSection {env} />

    <SectionHeader title="이슈 선택" count={keys.length} bind:collapsed={() => settings.e2eIssuesCollapsed, (v) => setSetting("e2eIssuesCollapsed", v)}>
      {#snippet trailing()}
        <JiraVersionMenu />
        <button class="icon-btn mini" title="Jira 새로고침" aria-label="Jira 새로고침" onclick={() => refreshJira()}><Icon name="refresh" size={0.9} /></button>
      {/snippet}
    </SectionHeader>
    {#if !settings.e2eIssuesCollapsed}
      {#if !jira.configured}
        <div class="muted pad">Jira 를 연결하면 내 이슈에서 고를 수 있어요. 아래에 키를 직접 넣어도 돼요.</div>
      {:else}
        {#if settings.jiraGroupByVersion}
          {#each groupedByVersion(filtered) as g (g.title ?? "\u0000none")}
            <div class="ghdr">{g.title === null ? "버전 없음" : displayVersion(g.title, prefix)} · {g.issues.length}</div>
            {#each g.issues as i (i.id)}{@render issueRow(i)}{/each}
          {/each}
        {:else}
          {#each filtered as i (i.id)}{@render issueRow(i)}{/each}
        {/if}
        {#if filtered.length === 0 && jira.updatedAt}<div class="faint pad">보여줄 이슈가 없어요</div>{/if}
        {#if jira.error}<div class="err1">{jira.error}</div>{/if}
      {/if}
    {/if}

    <div class="inputs">
      <textarea class="field" rows="1" placeholder="이슈 키·링크 직접 입력 (쉼표·줄바꿈으로 여러 개)" bind:value={e2e.draftKeys}></textarea>
      <textarea class="field" rows="1" placeholder="Aside 에 추가 요청사항 · 테스트 데이터, 허용할 동작" bind:value={e2e.draftNotes}></textarea>
    </div>

    <div class="run">
      <div class="line">
        <span class="sel">{keys.length === 0 ? "고른 이슈 없음" : keys.join(", ")}</span>
        <ModelMenu />
        {#if e2e.submitting}<span class="spin sp"></span>{/if}
        <button class="chip solid lg" disabled={keys.length === 0 || e2e.submitting} onclick={() => (env === "PR" ? (confirmPR = true) : doSubmit())}>
          <Sym name="play" size={0.8} />{e2e.running === null ? `검증 실행 (${keys.length}건)` : `대기열에 추가 (${keys.length}건)`}
        </button>
      </div>
      {#if e2e.submitError}<div class="err1">{e2e.submitError}</div>{/if}
      <div class="faint sm">실행하면 내 Aside 브라우저가 탭을 열어 직접 조작해요. 결과는 참고용 자동 검증이에요.</div>
    </div>

    <SectionHeader title="이력" count={e2e.jobs.length} bind:collapsed={() => settings.e2eHistoryCollapsed, (v) => setSetting("e2eHistoryCollapsed", v)} />
    {#if !settings.e2eHistoryCollapsed}
      {#if e2e.jobs.length === 0}<div class="faint pad">아직 실행한 검증이 없어요</div>{/if}
      {#each e2e.jobs as j (j.id)}
        {@const issues = commentableIssues(j)}
        {@const ls = links(j)}
        {@const active = isRunning(j.id)}
        {@const done = issues.length > 0 && issues.every((i) => j.jiraComments[i.key])}
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div class="hrow" oncontextmenu={(e) => { e.preventDefault(); menu = { job: j, x: e.clientX, y: e.clientY }; }}>
          <div class="hline">
            <button class="open" onclick={() => openResult(j.id)}>
              <span class="when">{fmtTime(j.createdAt)}</span><EnvTag env={j.env} /><span class="keys">{j.issues.map((i) => i.key).join(", ")}</span>
            </button>
            <button class="open st" onclick={() => openResult(j.id)}><JobStatus job={j} /></button>
            <span class="acts">
              {#if !active}
                {#if e2e.commenting && issues.some((i) => e2e.commenting === commentId(j.id, i.key))}
                  <span class="spin sp"></span>
                {:else if issues.length === 1}
                  <button class="chip {done ? 'plain' : 'soft'}" disabled={e2e.commenting !== null} aria-label="Jira 댓글로 남기기"
                    title={posted(j, issues[0].key) ? `${posted(j, issues[0].key)} Jira 댓글 남김 · 누르면 한 번 더 남겨요` : "Jira 댓글로 남기기 (누르면 한 번 더 물어봐요)"} onclick={() => askComment(j, issues[0])}>
                    <Sym name={done ? "bubble-check" : "bubble"} size={0.9} />
                  </button>
                {:else if issues.length > 1}
                  <button class="chip {done ? 'plain' : 'soft'}" disabled={e2e.commenting !== null} aria-label="Jira 댓글로 남기기" title="이슈를 골라 Jira 댓글로 남기기"
                    onclick={(e) => pickMenu(e, issues.map((i) => ({ label: menuTitle(j, i), onselect: () => askComment(j, i) })))}>
                    <Sym name={done ? "bubble-check" : "bubble"} size={0.9} />
                  </button>
                {/if}
              {/if}
              {#if ls.length === 1}
                <button class="chip plain" aria-label="Jira 에서 열기" title="{ls[0].key} Jira 에서 열기" onclick={() => open(ls[0].url)}><Sym name="external" size={0.9} /></button>
              {:else if ls.length > 1}
                <button class="chip plain" aria-label="이슈를 골라 Jira 에서 열기" title="이슈를 골라 Jira 에서 열기"
                  onclick={(e) => pickMenu(e, ls.map((l) => ({ label: l.title ? `${l.key} · ${l.title}` : l.key, onselect: () => open(l.url) })))}><Sym name="external" size={0.9} /></button>
              {/if}
              {#if active}
                <button class="chip plain" title="취소" aria-label="취소" onclick={() => cancelJob(j.id)}><Sym name="x-circle" size={0.9} /></button>
              {:else if j.status === "failed" || j.status === "cancelled"}
                <button class="chip soft" title="다시 실행 (지금 고른 모델로)" aria-label="다시 실행" onclick={() => doRetry(j)}><Sym name="refresh" size={0.9} /></button>
              {/if}
            </span>
          </div>
          {#if commentNote(j)}<div class="err1 selectable">{commentNote(j)}</div>{/if}
        </div>
      {/each}
    {/if}
  </div>
{/if}

{#snippet issueRow(issue: JiraIssue)}
  {@const on = e2e.draftSelected.includes(issue.id)}
  {@const v = e2e.verdictByKey[issue.id]}
  <button class="irow" onclick={() => toggle(issue.id)}>
    <span class="chk" class:on><Icon name={on ? "square-check" : "square"} size={1} /></span>
    <span class="ikey mono">{issue.id}</span>
    <span class="isum">{issue.summary}</span>
    {#if v}<VerdictBadge verdict={v.verdict} />{/if}
    <span class="ist">{issue.status}</span>
  </button>
{/snippet}

<Confirm bind:open={confirmPR} title="PR(운영) 환경에서 검증할까요?" message="운영 환경에서는 조회만 하고, 쓰기 동작이 필요한 시나리오는 SKIPPED 로 남겨요." confirm="조회만 하고 실행" onconfirm={doSubmit} />
<Confirm bind:open={() => prRetry !== null, (v) => { if (!v) prRetry = null; }} title="PR(운영) 환경에서 검증할까요?" message="운영 환경에서는 조회만 하고, 쓰기 동작이 필요한 시나리오는 SKIPPED 로 남겨요." confirm="조회만 하고 실행"
  onconfirm={() => { const id = prRetry; prRetry = null; if (id) void retry(id); }} />
<CommentDialog bind:target={commentTarget} />
{#if menu}<Menu items={rowMenu(menu.job)} anchor={{ x: menu.x, y: menu.y }} onclose={() => (menu = null)} />{/if}
{#if pick}<Menu items={pick.items} anchor={pick.el} align="end" onclose={() => (pick = null)} />{/if}

<style>
  .tab { flex: 1; min-height: 0; padding: 0 6px 8px 10px; }
  .grow { flex: 1; }
  .envrow { display: flex; align-items: center; gap: 6px; padding-top: 8px; }
  .eurl { font-size: 0.88em; color: var(--fg2); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; direction: rtl; text-align: left; }
  .eurl.none { color: var(--warn); direction: ltr; }
  .pad { padding: 6px 0; }
  .muted { color: var(--fg2); font-size: 0.92em; }
  .faint { color: var(--fg3); }
  .sm { font-size: 0.82em; }
  .err1 { color: var(--danger); font-size: 0.92em; padding: 3px 0; overflow-wrap: anywhere; }
  .ghdr { font-size: 0.9em; font-weight: 600; color: var(--fg2); padding: 8px 0 2px; }
  .irow { display: flex; align-items: center; gap: 6px; width: 100%; padding: 4px 0; border: none; border-bottom: 1px solid var(--line); background: transparent; text-align: left; }
  .chk { color: var(--fg2); display: inline-flex; flex: none; }
  .chk.on { color: var(--accent); }
  .ikey { font-size: 0.88em; color: var(--accent); flex: none; }
  .isum { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .ist { font-size: 0.8em; color: var(--fg2); flex: none; max-width: 30%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .inputs { display: flex; flex-direction: column; gap: 6px; padding-top: 8px; }
  .inputs .field { user-select: text; min-height: 28px; resize: vertical; }
  .run { display: flex; flex-direction: column; gap: 4px; padding-top: 8px; }
  .line { display: flex; align-items: center; gap: 6px; }
  .sel { flex: 1; min-width: 0; font-size: 0.88em; color: var(--fg2); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .sp { width: 0.9em; height: 0.9em; border-radius: 50%; border: 2px solid var(--line); border-top-color: var(--accent); flex: none; }
  .icon-btn.mini { width: 20px; height: 20px; }
  .hrow { border-bottom: 1px solid var(--line); }
  .hline { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; min-height: 30px; }
  .open { display: inline-flex; align-items: center; gap: 6px; border: none; background: transparent; padding: 5px 0; text-align: left; min-width: 0; }
  .open.st { margin-left: auto; }
  .when { font-size: 0.88em; color: var(--fg2); font-variant-numeric: tabular-nums; flex: none; }
  .keys { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 12em; }
  .acts { display: inline-flex; gap: 2px; align-items: center; }
</style>
