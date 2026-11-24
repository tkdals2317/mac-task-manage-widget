<script lang="ts">
  // 검증 결과 상세: 요약 → 이슈 카드 → 시나리오(단계·기대·실제·스크린샷). (Mac E2EResultView)
  import { openUrl } from "@tauri-apps/plugin-opener";
  import Sym from "../lib/Sym.svelte";
  import Confirm from "../lib/Confirm.svelte";
  import {
    cancelJob, deleteJob, e2e, exportReport, existingScreenshots, isRunning, issueLink, logTail, modelName, openLog, perform, retry, revealJob,
  } from "../lib/e2e.svelte";
  import { VERDICT_ORDER, forcesReadOnly, loginBlockReason, loginBlockSteps, verdictCounts, webURL, type IssueResult, type Job, type LoginBlock } from "../lib/e2eCore";
  import { failureFix, failureMessage, failureOfMessage, failureSteps, fixLabel, type FailureKind } from "../lib/asideCore";
  import { commentId } from "../lib/e2e.svelte";
  import { native } from "../lib/native";
  import EnvTag from "./EnvTag.svelte";
  import JobStatus from "./JobStatus.svelte";
  import VerdictBadge from "./VerdictBadge.svelte";
  import Thumb from "./Thumb.svelte";
  import CommentDialog, { type CommentTarget } from "./CommentDialog.svelte";

  let { job }: { job: Job } = $props();
  let confirmDelete = $state(false);
  let confirmPR = $state(false);
  let commentTarget = $state<CommentTarget | null>(null);
  let tail = $state("");

  const active = $derived(isRunning(job.id));
  const res = $derived(e2e.results[job.id]);
  const failure = $derived<FailureKind | null>(job.error && job.status === "failed" ? failureOfMessage(job.error) : null);
  const fmt = (d: Date) => d.toLocaleString("ko-KR", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
  const when = (iso: string | undefined) => (iso ? fmt(new Date(iso)) : "");

  // 결과가 없거나 읽지 못한 경우에 run.log 마지막 부분을 보여준다
  $effect(() => { if (!active && res && res.kind !== "ok") void logTail(job.id).then((t) => (tail = t)); });

  function doRetry() { const id = job.id; void retry(id).then((ok) => { if (ok) e2e.openJobId = null; }); }
  const onRetry = () => (forcesReadOnly(job.env) ? (confirmPR = true) : doRetry());

  async function askComment(issue: IssueResult) {
    commentTarget = { job, issue, shots: (await existingScreenshots(job.id, issue)).length };
  }
  const openIssue = (u: string | null) => { if (u) void openUrl(u).catch(() => {}); };
  const loginSite = $derived(webURL(job.baseUrl));
  const account = $derived(job.username ? `테스트 계정(${job.username})` : "테스트 계정");
  const blockIsOpen = (b: LoginBlock | null) => b !== null && !active;
</script>

<div class="res scroll">
  <div class="top">
    <button class="chip plain" onclick={() => (e2e.openJobId = null)}><Sym name="chevron-left" size={0.9} />목록</button>
    <span class="grow"></span>
    {#if !active}
      <button class="chip {job.status === 'done' ? 'plain' : 'soft'}" disabled={e2e.submitting} title="같은 이슈·추가 요청사항으로 다시 실행 (지금 고른 모델로)" onclick={onRetry}><Sym name="refresh" size={0.9} />다시 실행</button>
      <button class="chip plain" disabled={e2e.exporting} title="결과를 HTML 파일 하나로 바탕 화면에 저장 (스크린샷 포함 · 이슈 첨부용)" onclick={() => exportReport(job.id)}><Sym name="share" size={0.9} />{e2e.exporting ? "내보내는 중…" : "내보내기"}</button>
    {/if}
    <button class="chip plain" title="job 폴더를 탐색기에서 열기" onclick={() => revealJob(job.id)}><Sym name="folder" size={0.9} />폴더</button>
    <button class="chip plain" title="run.log 열기" onclick={() => openLog(job.id)}><Sym name="doc" size={0.9} />로그</button>
    {#if !active}<button class="chip plain" title="삭제" aria-label="삭제" onclick={() => (confirmDelete = true)}><Sym name="trash" size={0.9} /></button>{/if}
  </div>

  <div class="hd">
    <div class="line">
      <EnvTag env={job.env} /><span class="dim">{fmt(job.createdAt)}</span>
      {#if job.readOnly}<span class="ro">조회만</span>{/if}
      <span class="grow"></span>
      {#if !active}<JobStatus {job} />{/if}
    </div>
    <div class="url dim">{job.baseUrl}</div>
    <div class="dim sm">모델: {modelName(job.model)}</div>
    {#if e2e.submitError}<div class="err">{e2e.submitError}</div>{/if}
    {#if job.notes}<div class="dim selectable">추가 요청사항: {job.notes}</div>{/if}
  </div>

  {#if active}
    <div class="line"><JobStatus {job} /><span class="grow"></span><button class="chip soft" onclick={() => cancelJob(job.id)}><Sym name="stop" size={0.8} />취소</button></div>
  {/if}

  {#if job.error}
    {#if failure}
      {@render help("검증을 돌리지 못했어요", "warning", failureMessage(failure), failureSteps(failure), "")}
    {:else}
      <div class="ebox selectable">{job.error}</div>
    {/if}
  {/if}

  {#if res?.kind === "ok"}
    {@const r = res.result}
    {#if blockIsOpen(r.loginBlocked)}
      {@render help("환경 로그인에서 막혔어요", "key", loginBlockReason(r.loginBlocked!), loginBlockSteps(r.loginBlocked!, account), "비밀번호는 Aside 에서 직접 입력해요. ATM 과 Aside 에이전트는 비밀번호를 보지 않아요.")}
    {/if}
    {@const counts = verdictCounts(r)}
    <div class="card">
      <div class="vbs">{#each VERDICT_ORDER as v (v)}{#if counts[v] !== undefined}<VerdictBadge verdict={v} count={counts[v]} />{/if}{/each}</div>
      {#if r.summary}<div class="selectable">{r.summary}</div>{/if}
    </div>
    {#each r.issues as issue, n (n)}
      {@const ref = job.issues.find((i) => i.key === issue.key)}
      {@const url = ref ? issueLink(ref) : null}
      <div class="card">
        <div class="line">
          <button class="key mono" disabled={!url} title="Jira 에서 열기" onclick={() => openIssue(url)}>{issue.key}</button>
          <span class="ititle">{issue.title || ref?.title || ""}</span>
          <VerdictBadge verdict={issue.verdict} />
        </div>
        {#if issue.assumptions.length}
          <div class="assume"><b>가정</b>{#each issue.assumptions as a, i (i)}<div>· {a}</div>{/each}</div>
        {/if}
        {#each issue.scenarios as s, i (i)}
          <div class="sc">
            <div class="line"><span class="sname">{s.name}</span><span class="grow"></span><VerdictBadge verdict={s.verdict} /></div>
            {#each s.steps as st, k (k)}<div class="step">{k + 1}. {st}</div>{/each}
            {#if s.expected}<div class="lab"><b>기대</b><span class="selectable">{s.expected}</span></div>{/if}
            {#if s.actual}<div class="lab"><b>실제</b><span class="selectable">{s.actual}</span></div>{/if}
            {#if s.screenshots.length}<div class="shots">{#each s.screenshots as name, k (k)}<Thumb jobId={job.id} {name} />{/each}</div>{/if}
          </div>
        {/each}
        {#if issue.notes}<div class="dim selectable">{issue.notes}</div>{/if}
        {#if url && !active}
          {@const id = commentId(job.id, issue.key)}
          {@const posted = job.jiraComments[issue.key]}
          <div class="cm">
            <span class="grow"></span>
            {#if posted}<span class="dim sm">{when(posted)} 댓글 남김</span>{/if}
            <button class="chip plain" disabled={e2e.commenting !== null} title="이 이슈의 검증 결과를 Jira 댓글로 남겨요 (누르면 한 번 더 물어봐요)" onclick={() => askComment(issue)}>
              <Sym name={posted ? "bubble-check" : "bubble"} size={0.9} />{e2e.commenting === id ? "남기는 중…" : posted ? "한 번 더" : "Jira 댓글로 남기기"}
            </button>
          </div>
          {#if e2e.commentNote?.id === id}<div class="err selectable">{e2e.commentNote.text}</div>{/if}
        {/if}
      </div>
    {/each}
  {:else if res?.kind === "invalid"}
    <div class="ebox selectable">result.json 을 읽지 못했어요 ({res.message})</div>
    {@render logBox()}
  {:else if !active}
    {#if !job.error}<div class="dim">결과가 없어요</div>{/if}
    {@render logBox()}
  {:else}
    {#each job.issues as i (i.key)}<div class="ilist">{i.key} {i.title}</div>{/each}
  {/if}
  <div class="faint sm">자동 검증 결과는 참고용이에요. 가정과 스크린샷을 같이 확인해 주세요.</div>
</div>

{#snippet logBox()}
  {#if tail}
    <div class="logb"><div class="dim sm"><b>run.log 마지막 부분</b></div><pre class="selectable">{tail}</pre></div>
  {/if}
{/snippet}

{#snippet help(title: string, icon: "warning" | "key", reason: string, steps: string[], note: string)}
  <div class="help">
    <div class="ht"><Sym name={icon} size={1} />{title}</div>
    <div class="selectable">{reason}</div>
    {#each steps as s, i (i)}<div class="step">{i + 1}. {s}</div>{/each}
    <div class="hb">
      {#if failure}
        {@const fix = failureFix(failure)}
        {#if fix}<button class="chip soft" onclick={() => perform(fix, job.env)}>{fixLabel(fix)}</button>{/if}
      {:else}
        <button class="chip soft" disabled={!loginSite} title={loginSite ? new URL(loginSite).host : "환경 주소를 찾지 못했어요"} onclick={() => loginSite && native.asideOpenUrl(loginSite).catch((e) => (e2e.submitError = String(e)))}><Sym name="external" size={0.9} />Aside 에서 로그인 페이지 열기</button>
      {/if}
      <button class="chip plain" disabled={e2e.submitting} onclick={onRetry}><Sym name="refresh" size={0.9} />다시 실행</button>
    </div>
    {#if note}<div class="faint sm">{note}</div>{/if}
  </div>
{/snippet}

<Confirm bind:open={confirmPR} title="PR(운영) 환경에서 검증할까요?" message="운영 환경에서는 조회만 하고, 쓰기 동작이 필요한 시나리오는 SKIPPED 로 남겨요." confirm="조회만 하고 실행" onconfirm={doRetry} />
<Confirm bind:open={confirmDelete} title="이 검증 기록을 지울까요?" message="결과와 스크린샷 폴더가 함께 지워져요." confirm="삭제" danger onconfirm={() => deleteJob(job.id)} />
<CommentDialog bind:target={commentTarget} />

<style>
  .res { flex: 1; min-height: 0; padding: 8px 6px 10px 10px; display: flex; flex-direction: column; gap: 8px; }
  .top { display: flex; align-items: center; gap: 4px; flex-wrap: wrap; }
  .grow { flex: 1; }
  .line { display: flex; align-items: center; gap: 6px; min-width: 0; }
  .hd { display: flex; flex-direction: column; gap: 3px; }
  .dim { color: var(--fg2); }
  .faint { color: var(--fg3); }
  .sm { font-size: 0.85em; }
  .url { font-size: 0.88em; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .ro { font-size: 0.85em; color: var(--warn); }
  .err { color: var(--danger); font-size: 0.92em; overflow-wrap: anywhere; }
  .ebox { color: var(--danger); background: var(--danger-soft); padding: 5px 8px; border-radius: 6px; font-size: 0.92em; overflow-wrap: anywhere; }
  .card { display: flex; flex-direction: column; gap: 6px; padding: 8px; border-radius: 8px; background: var(--fill); }
  .vbs { display: flex; gap: 4px; }
  .key { border: none; background: none; padding: 0; color: var(--accent); font-size: 0.92em; flex: none; }
  .key:disabled { color: var(--fg2); }
  .key:not(:disabled):hover { text-decoration: underline; }
  .ititle { font-weight: 600; flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; display: -webkit-box; -webkit-line-clamp: 2; line-clamp: 2; -webkit-box-orient: vertical; }
  .assume { color: var(--warn); background: var(--warn-soft); padding: 6px; border-radius: 6px; font-size: 0.92em; }
  .sc { display: flex; flex-direction: column; gap: 3px; border-top: 0.5px solid var(--line2); padding-top: 6px; }
  .sname { font-weight: 500; }
  .step { font-size: 0.92em; color: var(--fg2); }
  .lab { display: flex; gap: 6px; align-items: baseline; }
  .lab b { flex: none; width: 24px; font-size: 0.85em; color: var(--fg2); }
  .shots { display: flex; gap: 6px; overflow-x: auto; padding-bottom: 2px; }
  .cm { display: flex; align-items: center; gap: 6px; }
  .help { display: flex; flex-direction: column; gap: 4px; padding: 8px; border-radius: 8px; background: var(--warn-soft); }
  .ht { display: flex; align-items: center; gap: 5px; font-weight: 600; color: var(--warn); }
  .hb { display: flex; gap: 6px; flex-wrap: wrap; padding-top: 2px; }
  .logb pre { margin: 3px 0 0; padding: 6px; border-radius: 6px; background: var(--fill); font: 0.82em "Cascadia Mono", Consolas, monospace; white-space: pre-wrap; overflow-wrap: anywhere; }
  .ilist { font-size: 0.95em; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
</style>
