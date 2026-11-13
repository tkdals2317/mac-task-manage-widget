<script lang="ts">
  // PR 탭 (Mac PRView): 위 칩(전체·GitHub·Bitbucket)·갱신 시각, 리뷰 요청(상태·저장소·사람 필터), 내 PR.
  import { onMount } from "svelte";
  import Sym from "../lib/Sym.svelte";
  import SectionHeader from "../tasks/SectionHeader.svelte";
  import Popover from "../tasks/Popover.svelte";
  import PRRow from "../pr/PRRow.svelte";
  import { settings, setSetting } from "../lib/settings.svelte";
  import { native } from "../lib/native";
  import { pr, anyEnabled, refreshPR, refreshIfStale, markSeen, probeGitHub } from "../lib/pr.svelte";
  import { facets, filterReviews, statusShort, type Facet, type FacetKind, type PRProvider, type PullRequest, type ReviewStatus } from "../lib/prCore";

  let now = $state(Date.now());
  let expanded = $state<string | null>(null);
  let pop = $state<{ kind: FacetKind; el: HTMLElement } | null>(null);

  const list = (raw: string): string[] => { try { const v = JSON.parse(raw || "[]"); return Array.isArray(v) ? v : []; } catch { return []; } };
  let stateSel = $derived(new Set(list(settings.prReviewStateFilter)));
  let repoSel = $derived(new Set(list(settings.prReviewRepoFilter)));
  let authorSel = $derived(new Set(list(settings.prReviewAuthorFilter)));
  let filtering = $derived(stateSel.size + repoSel.size + authorSel.size > 0);

  // 켜진 제공자가 하나면 그 제공자로 본다
  let filter = $derived(settings.prGitHubEnabled && settings.prBitbucketEnabled ? settings.prFilter : settings.prGitHubEnabled ? "github" : settings.prBitbucketEnabled ? "bitbucket" : "all");
  const byProvider = (l: PullRequest[]) => (filter === "all" ? l : l.filter((p) => p.provider === filter));
  let baseRR = $derived(byProvider(pr.reviewRequests));
  let shownRR = $derived(filterReviews(baseRR, stateSel, repoSel, authorSel));
  let shownMine = $derived(byProvider(pr.mine));
  const count = (p: PRProvider) => pr.reviewRequests.filter((x) => x.provider === p).length + pr.mine.filter((x) => x.provider === p).length;

  // 탭을 연 순간의 "안 본" 목록을 기억해 NEW 를 보여주고, 열자마자 본 것으로 표시한다
  let freshIds = $state(new Set<string>());
  onMount(() => {
    void refreshIfStale();
    if (settings.prGitHubEnabled && pr.github.kind === "off") void probeGitHub();
    const t = setInterval(() => (now = Date.now()), 60_000);
    return () => clearInterval(t);
  });
  $effect(() => {
    if (!pr.reviewRequests.length) return;
    const unseen = pr.reviewRequests.filter((p) => p.reviewRequested && !pr.seen.has(p.id)).map((p) => p.id);
    if (unseen.length) freshIds = new Set([...freshIds, ...unseen]);
    markSeen();
  });

  function setSel(kind: FacetKind, next: Set<string>) {
    const key = kind === "status" ? "prReviewStateFilter" : kind === "repo" ? "prReviewRepoFilter" : "prReviewAuthorFilter";
    setSetting(key, JSON.stringify([...next].sort()));
  }
  const selOf = (k: FacetKind) => (k === "status" ? stateSel : k === "repo" ? repoSel : authorSel);
  function toggleFacet(kind: FacetKind, key: string) {
    const s = new Set(selOf(kind));
    if (!s.delete(key)) s.add(key);
    setSel(kind, s);
  }
  const clearFilters = () => { setSetting("prReviewStateFilter", "[]"); setSetting("prReviewRepoFilter", "[]"); setSetting("prReviewAuthorFilter", "[]"); };

  function chipTitle(kind: FacetKind): string {
    const name = { status: "상태", repo: "저장소", author: "사람" }[kind];
    const sel = selOf(kind);
    if (!sel.size) return name;
    const first = [...sel][0];
    const label = kind === "status" ? statusShort[first as ReviewStatus] : kind === "repo" ? first.split("/").pop() : first;
    return sel.size > 1 ? `${label} 외 ${sel.size - 1}` : (label ?? name);
  }
  let popFacets = $derived<Facet[]>(pop ? facets(baseRR, pop.kind, stateSel, repoSel, authorSel) : []);

  let errors = $derived([pr.githubError && settings.prGitHubEnabled ? `GitHub: ${pr.githubError}` : null, pr.bitbucketError && settings.prBitbucketEnabled ? `Bitbucket: ${pr.bitbucketError}` : null].filter(Boolean) as string[]);
  const time = (t: number) => new Date(t).toLocaleTimeString("ko-KR", { hour: "numeric", minute: "2-digit" });
</script>

<div class="pr-tab">
  {#if !anyEnabled()}
    <div class="connect">
      <Sym name="branch" size={1.6} />
      <div class="ct">PR 을 연결해 보세요</div>
      <div class="cs">나한테 온 리뷰 요청과 내가 올린 PR 의 승인 상태를 모아 보고, 승인되면 알려줘요.</div>
      <div class="rows">
        <div class="crow">
          <div><b>GitHub</b><div class="faint">gh CLI 로그인을 써요 (winget install GitHub.cli → gh auth login)</div></div>
          <button class="chip solid" onclick={() => { setSetting("prGitHubEnabled", true); setTimeout(() => refreshPR(), 50); }}><Sym name="power" />켜기</button>
        </div>
        <div class="crow">
          <div><b>Bitbucket</b><div class="faint">이메일과 API 토큰, 볼 저장소를 골라요</div></div>
          <button class="chip soft" onclick={() => native.openSettings("pr")}><Sym name="link" />연결하기</button>
        </div>
      </div>
    </div>
  {:else}
    <div class="top">
      {#if settings.prGitHubEnabled && settings.prBitbucketEnabled}
        {#each [["all", "전체"], ["github", `GitHub ${count("github")}`], ["bitbucket", `Bitbucket ${count("bitbucket")}`]] as [id, label] (id)}
          <button class="fchip" class:on={filter === id} onclick={() => setSetting("prFilter", id)}>{label}</button>
        {/each}
      {/if}
      <span class="grow"></span>
      {#if pr.lastRefresh}<span class="faint small">{time(pr.lastRefresh)}</span>{/if}
      <button class="icon-btn" title="새로고침" onclick={() => refreshPR()}><span class:spin={pr.loading}><Sym name="refresh" /></span></button>
    </div>
    <div class="list scroll">
      {#each errors as e (e)}<div class="err" title={e}><Sym name="warning" /> {e}</div>{/each}
      {#if settings.prGitHubEnabled && (pr.github.kind === "ghMissing" || pr.github.kind === "loggedOut")}
        <div class="nc">
          <span>{pr.github.kind === "ghMissing" ? "gh CLI 를 찾지 못했어요" : "gh 에 로그인돼 있지 않아요 (gh auth login)"}</span>
          <button class="chip soft" onclick={() => native.openSettings("pr")}><Sym name="gear" />설정</button>
        </div>
      {/if}
      {#if settings.prBitbucketEnabled && pr.bitbucket.kind === "notConfigured"}
        <div class="nc"><span>Bitbucket 이 아직 연결 안 됐어요</span><button class="chip soft" onclick={() => native.openSettings("pr")}><Sym name="gear" />설정</button></div>
      {/if}

      <SectionHeader title="리뷰 요청" count={shownRR.length} bind:collapsed={() => settings.prReviewCollapsed, (v) => setSetting("prReviewCollapsed", v)}>
        {#snippet trailing()}
          {#each ["status", "repo", "author"] as const as k (k)}
            <button class="fchip small" class:on={selOf(k).size > 0} onclick={(e) => (pop = pop?.kind === k ? null : { kind: k, el: e.currentTarget as HTMLElement })}>
              {chipTitle(k)} <Sym name="chevron-down" size={0.8} />
            </button>
          {/each}
          {#if filtering}<button class="icon-btn" title="필터 해제" onclick={clearFilters}><Sym name="x" size={0.85} /></button>{/if}
        {/snippet}
      </SectionHeader>
      {#if filtering && shownRR.length !== baseRR.length}<div class="faint small sub">{shownRR.length}/{baseRR.length}</div>{/if}
      {#if !settings.prReviewCollapsed}
        {#each shownRR as p (p.id)}
          <PRRow {p} review={true} {now} isNew={freshIds.has(p.id)} expanded={expanded === p.id} ontoggle={() => (expanded = expanded === p.id ? null : p.id)} />
        {:else}
          {#if filtering && baseRR.length}
            <div class="empty">조건에 맞는 리뷰 요청이 없어요 <button class="chip soft" onclick={clearFilters}><Sym name="x" />필터 해제</button></div>
          {:else}
            <div class="empty">✓ 밀린 리뷰 없어요</div>
          {/if}
        {/each}
      {/if}

      <SectionHeader title="내 PR" count={shownMine.length} bind:collapsed={() => settings.prMineCollapsed, (v) => setSetting("prMineCollapsed", v)} />
      {#if !settings.prMineCollapsed}
        {#each shownMine as p (p.id)}
          <PRRow {p} review={false} {now} isNew={false} expanded={expanded === p.id} ontoggle={() => (expanded = expanded === p.id ? null : p.id)} />
        {:else}
          <div class="empty">열린 PR 이 없어요</div>
        {/each}
      {/if}
    </div>
  {/if}
</div>

{#if pop}
  <Popover anchor={pop.el} onclose={() => (pop = null)}>
    <div class="facets">
      {#each popFacets as f (f.key)}
        <button class="frow" onclick={() => toggleFacet(pop!.kind, f.key)}>
          <span class="chk">{selOf(pop.kind).has(f.key) ? "✓" : ""}</span>
          <span class="fl">{f.label}{#if f.provider}<span class="faint"> · {f.provider === "github" ? "GH" : "BB"}</span>{/if}</span>
          <span class="faint tnum">{f.count}</span>
        </button>
      {:else}
        <div class="faint">값이 없어요</div>
      {/each}
    </div>
  </Popover>
{/if}

<style>
  .pr-tab { display: flex; flex-direction: column; height: 100%; min-height: 0; }
  .top { display: flex; align-items: center; gap: 6px; padding: 8px 10px 4px; }
  .grow { flex: 1; }
  .small { font-size: 0.82em; }
  .fchip { padding: 2px 9px; border-radius: 999px; border: none; background: var(--fill2); color: var(--fg2); font-size: 0.9em; display: inline-flex; align-items: center; gap: 3px; }
  .fchip.small { font-size: 0.82em; padding: 1px 7px; }
  .fchip.on { background: var(--accent-soft); color: var(--accent-text); font-weight: 600; }
  .list { flex: 1; min-height: 0; padding: 0 6px 10px 10px; }
  .sub { margin: -2px 0 4px 16px; }
  .empty { padding: 8px 2px; color: var(--fg2); font-size: 0.9em; display: flex; align-items: center; gap: 8px; }
  .err { margin: 4px 0; padding: 5px 8px; border-radius: 6px; background: var(--danger-soft); color: var(--danger); font-size: 0.85em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .nc { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin: 4px 0; padding: 6px 8px; border-radius: 6px; background: var(--fill); font-size: 0.88em; color: var(--fg2); }
  .connect { margin: 24px 14px; display: flex; flex-direction: column; align-items: center; gap: 8px; text-align: center; color: var(--accent); }
  .ct { color: var(--fg); font-size: 1.08em; font-weight: 600; }
  .cs { color: var(--fg2); font-size: 0.9em; line-height: 1.5; }
  .rows { width: 100%; display: flex; flex-direction: column; gap: 8px; margin-top: 6px; }
  .crow { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 10px 12px; border-radius: 10px; background: var(--fill); text-align: left; color: var(--fg); }
  .crow .faint { font-size: 0.82em; margin-top: 2px; }
  .facets { display: flex; flex-direction: column; min-width: 190px; max-height: 300px; overflow: auto; margin: -4px; }
  .frow { display: flex; align-items: center; gap: 6px; padding: 4px 8px; border: none; background: transparent; border-radius: 5px; text-align: left; }
  .frow:hover { background: var(--fill2); }
  .chk { width: 1em; color: var(--accent); }
  .fl { flex: 1; }
</style>
