<script lang="ts">
  // PR 한 줄 (Mac PRRow): 제공자 칩, 제목, 저장소·작성자·시각, 상태 배지, 리뷰어 동그라미, 변경 규모.
  // 누르면 펼쳐져 리뷰어별 상태·브랜치·열기·브랜치 복사·할 일로·승인.
  import { openUrl } from "@tauri-apps/plugin-opener";
  import Sym from "../lib/Sym.svelte";
  import Menu, { type MenuItem } from "../tasks/Menu.svelte";
  import Popover from "../tasks/Popover.svelte";
  import { copyText, showToast } from "../lib/toast.svelte";
  import { addTodo } from "../lib/todos.svelte";
  import { settings } from "../lib/settings.svelte";
  import { native } from "../lib/native";
  import { approval, checkoutCommand, hasNewCommitsSinceMyReview, isStale, relative, todoTitle, waitDays, type PullRequest, type ReviewState } from "../lib/prCore";
  import { pr as model, approve, approvedByMe, hideRepo } from "../lib/pr.svelte";

  let { p, review, now, isNew, expanded, ontoggle }: {
    p: PullRequest; review: boolean; now: number; isNew: boolean; expanded: boolean; ontoggle: () => void;
  } = $props();

  let menu = $state<{ x: number; y: number } | null>(null);
  let confirm = $state<"approve" | "undo" | null>(null);
  let approveBtn: HTMLElement | undefined = $state();

  let a = $derived(approval(p));
  let reviewedQuiet = $derived(review && p.myReviewAt != null && !hasNewCommitsSinceMyReview(p));
  let mine = $derived(approvedByMe(p));
  let canApprove = $derived(review && !(p.provider === "bitbucket" && model.bbNoWrite && !mine));
  let acting = $derived(model.acting.includes(p.id));

  const open = () => { if (p.url.startsWith("https://")) openUrl(p.url).catch(() => {}); };
  const stateColor = (s: ReviewState) => (s === "approved" ? "var(--ok)" : s === "changesRequested" ? "var(--danger)" : s === "commented" ? "var(--info)" : "var(--fg3)");
  const stateLabel = (s: ReviewState) => ({ approved: "승인", changesRequested: "변경 요청", commented: "댓글", pending: "대기" })[s];
  const initial = (n: string) => [...n.trim()][0]?.toUpperCase() ?? "?";

  function toTodo() {
    addTodo(todoTitle(p, review), p.url);
    showToast("할 일에 추가했어요");
  }

  const menuItems = (): MenuItem[] => [
    { label: "열기", onselect: open },
    { label: "브랜치 복사", onselect: () => copyText(p.sourceBranch, "브랜치 이름을 복사했어요") },
    { label: "체크아웃 명령 복사", onselect: () => copyText(checkoutCommand(p.sourceBranch), "체크아웃 명령을 복사했어요") },
    { label: "할 일로 보내기", onselect: toTodo },
    ...(review && canApprove && !mine ? [{ label: "승인…", onselect: () => { if (!expanded) ontoggle(); setTimeout(() => (confirm = "approve"), 50); } }] : []),
    { separator: true },
    { label: "이 저장소 숨기기", onselect: () => hideRepo(p) },
  ];
</script>

<div class="pr" class:quiet={reviewedQuiet}>
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
  <div class="line" onclick={ontoggle} oncontextmenu={(e) => { e.preventDefault(); menu = { x: e.clientX, y: e.clientY }; }}>
    <span class="prov">{p.provider === "github" ? "GH" : "BB"}</span>
    <div class="main">
      <div class="title" title={p.title}>{p.title}</div>
      <div class="meta">
        <span class="sub">{p.repo}{review ? ` · ${p.author}` : ""} · {relative(p.createdAt, now)}</span>
        {#if p.isDraft}<span class="pill gray">Draft</span>{/if}
        {#if review}
          {#if isNew}<span class="pill new">NEW</span>{/if}
          {#if isStale(p, now, settings.prStaleDays) && p.myReviewAt == null}<span class="pill red">{waitDays(p, now)}일째 대기</span>{/if}
          {#if p.myReviewAt != null}<span class="pill green">✓ 리뷰함</span>{/if}
          {#if hasNewCommitsSinceMyReview(p)}<span class="pill orange">새 커밋</span>{/if}
        {:else}
          {#if a.kind === "changesRequested"}<span class="pill red">변경 요청</span>
          {:else if a.kind === "approved"}<span class="pill green">✓ 승인 {a.n}/{a.m}</span><span class="merge">머지 가능</span>
          {:else if a.kind === "waiting"}<span class="pill orange">승인 {a.n}/{a.m}</span>
          {:else}<span class="pill gray">리뷰어 없음</span>{/if}
          <span class="dots">
            {#each p.reviewers as r (r.name)}
              <span class="dot" style="--c:{stateColor(r.state)}" title="{r.name} · {stateLabel(r.state)}">{initial(r.name)}</span>
            {/each}
          </span>
        {/if}
      </div>
    </div>
    {#if p.additions != null || p.deletions != null}
      <span class="diff tnum">
        {#if (p.additions ?? 0) > 0}<span class="add">+{p.additions}</span>{/if}
        {#if (p.deletions ?? 0) > 0}<span class="del">−{p.deletions}</span>{/if}
      </span>
    {/if}
  </div>

  {#if expanded}
    <div class="detail">
      {#if p.reviewers.length}
        <div class="info"><span class="k">리뷰어</span>
          <span class="v revs">
            {#each p.reviewers as r (r.name)}<span><span class="mini" style="background:{stateColor(r.state)}"></span>{r.name} <span class="faint">{stateLabel(r.state)}</span></span>{/each}
          </span>
        </div>
      {/if}
      <div class="info"><span class="k">브랜치</span><span class="v mono selectable">{p.sourceBranch} → {p.targetBranch}</span></div>
      {#if p.changedFiles != null}
        <div class="info"><span class="k">변경</span><span class="v">{p.changedFiles}개 파일 · +{p.additions ?? 0} −{p.deletions ?? 0}</span></div>
      {/if}
      <div class="acts">
        <button class="chip solid" onclick={open}><Sym name="external" />열기</button>
        <button class="chip soft" onclick={() => copyText(p.sourceBranch, "브랜치 이름을 복사했어요")}><Sym name="copy" />브랜치 복사</button>
        <button class="chip soft" onclick={toTodo}><Sym name="list-check" />할 일로</button>
        <span class="grow"></span>
        {#if review}
          {#if mine}
            <span class="pill green">✓ 내가 승인함</span>
            {#if p.provider === "bitbucket"}
              <button class="chip plain" bind:this={approveBtn} disabled={acting} onclick={() => (confirm = "undo")}>승인 취소</button>
            {/if}
          {:else if !canApprove}
            <span class="hint">승인하려면 토큰에 쓰기 권한이 필요해요</span>
            <button class="chip" onclick={() => native.openSettings("pr")}>설정</button>
          {:else}
            <button class="chip soft" bind:this={approveBtn} disabled={acting} onclick={() => (confirm = "approve")}>
              {#if acting}<span class="spin"><Sym name="refresh" /></span>{:else}<Sym name="check-circle" />{/if}승인
            </button>
          {/if}
        {/if}
      </div>
      {#if model.actionError[p.id]}<div class="err">{model.actionError[p.id]}</div>{/if}
    </div>
  {/if}
</div>

{#if menu}<Menu items={menuItems()} anchor={menu} onclose={() => (menu = null)} />{/if}
{#if confirm && approveBtn}
  <Popover anchor={approveBtn} onclose={() => (confirm = null)}>
    <div class="confirm">
      <div class="ct">{confirm === "approve" ? "이 PR 을 승인할까요?" : "승인을 취소할까요?"}</div>
      <div class="cs">{p.repo} · #{p.number}</div>
      <div class="cb">
        <button class="chip plain" onclick={() => (confirm = null)}><Sym name="x" />취소</button>
        <button class="chip solid" onclick={() => { const u = confirm === "undo"; confirm = null; void approve(p, u); }}><Sym name="check" />{confirm === "approve" ? "승인" : "승인 취소"}</button>
      </div>
    </div>
  </Popover>
{/if}

<style>
  .pr { border-bottom: 0.5px solid var(--line); }
  .pr.quiet .title, .pr.quiet .sub { opacity: 0.6; }
  .line { display: flex; align-items: flex-start; gap: 8px; padding: 7px 2px; }
  .line:hover { background: var(--fill); border-radius: 6px; }
  .prov { flex: none; margin-top: 2px; padding: 0 5px; border-radius: 4px; background: var(--fill2); color: var(--fg2); font-size: 0.72em; font-weight: 700; line-height: 1.7; }
  .main { flex: 1; min-width: 0; }
  .title { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; font-weight: 500; }
  .meta { display: flex; align-items: center; gap: 5px; flex-wrap: wrap; margin-top: 2px; font-size: 0.86em; }
  .sub { color: var(--fg2); }
  .pill { padding: 0 6px; border-radius: 999px; font-size: 0.92em; font-weight: 600; line-height: 1.55; white-space: nowrap; }
  .pill.red { background: var(--danger-soft); color: var(--danger); }
  .pill.green { background: var(--ok-soft); color: var(--ok); }
  .pill.orange { background: var(--warn-soft); color: var(--warn); }
  .pill.gray { background: var(--fill2); color: var(--fg2); }
  .pill.new { background: var(--accent); color: var(--on-accent); }
  .merge { color: var(--ok); font-weight: 500; }
  .dots { display: inline-flex; }
  .dot { width: 1.5em; height: 1.5em; border-radius: 50%; border: 1.5px solid var(--c); color: var(--c); font-size: 0.78em; font-weight: 700; display: inline-flex; align-items: center; justify-content: center; background: var(--bg); margin-left: -3px; }
  .dot:first-child { margin-left: 0; }
  .diff { flex: none; font-size: 0.88em; display: flex; gap: 5px; margin-top: 2px; }
  .add { color: var(--ok); }
  .del { color: var(--danger); }
  .detail { padding: 0 2px 8px 30px; display: flex; flex-direction: column; gap: 4px; font-size: 0.88em; }
  .info { display: flex; gap: 8px; }
  .k { width: 44px; flex: none; color: var(--fg2); }
  .v { min-width: 0; word-break: break-all; }
  .revs { display: flex; flex-wrap: wrap; gap: 4px 10px; }
  .mini { display: inline-block; width: 7px; height: 7px; border-radius: 50%; margin-right: 4px; }
  .acts { display: flex; align-items: center; gap: 6px; margin-top: 4px; flex-wrap: wrap; }
  .grow { flex: 1; }
  .hint { color: var(--fg2); }
  .err { color: var(--danger); }
  .confirm { display: flex; flex-direction: column; gap: 4px; min-width: 200px; }
  .ct { font-weight: 600; }
  .cs { font-size: 0.85em; color: var(--fg2); }
  .cb { display: flex; justify-content: flex-end; gap: 6px; margin-top: 6px; }
</style>
