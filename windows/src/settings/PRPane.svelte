<script lang="ts">
  // 설정 > PR (Mac PRSettings): GitHub(gh) 켜기·상태, Bitbucket 이메일·토큰·워크스페이스·저장소 선택, 알림, 표시.
  import { onMount } from "svelte";
  import { emit } from "@tauri-apps/api/event";
  import { openUrl } from "@tauri-apps/plugin-opener";
  import { setSetting, settings } from "../lib/settings.svelte";
  import { native } from "../lib/native";
  import PwInput from "./PwInput.svelte";
  import {
    BITBUCKET_SERVICE, pr, probeGitHub, testBitbucket, commitBitbucket, bitbucketRepositories, recentReviewed,
    localBitbucketSlugs, cloneRoots, defaultCloneRoots, bitbucketRepoList, unhideRepo,
  } from "../lib/pr.svelte";

  let email = $state(settings.prBitbucketEmail);
  let token = $state("");
  let hasToken = $state(false);
  let busy = $state(false);
  let bbMsg = $state<{ ok: boolean; text: string } | null>(null);
  let workspaces = $state<{ slug: string; name: string }[]>([]);
  let editRepos = $state(false);
  let repos = $state<{ slug: string; name: string; updatedOn: number | null }[]>([]);
  let draft = $state(new Set<string>());
  let local = $state<string[]>([]);
  let recent = $state<string[]>([]);
  let progress = $state("");
  let query = $state("");
  let roots = $state<string[]>([]);
  let newRoot = $state("");

  const hidden = $derived((() => { try { return JSON.parse(settings.prHiddenRepos || "[]") as string[]; } catch { return []; } })());

  onMount(async () => {
    if (settings.prGitHubEnabled) void probeGitHub();
    hasToken = email ? (await native.secretGet(BITBUCKET_SERVICE, email).catch(() => null)) != null : false;
    roots = await cloneRoots();
  });

  async function test() {
    const e = email.trim();
    if (!e) { bbMsg = { ok: false, text: "이메일을 넣어 주세요" }; return; }
    const t = token.trim() || (await native.secretGet(BITBUCKET_SERVICE, e).catch(() => null)) || "";
    if (!t) { bbMsg = { ok: false, text: "API 토큰을 넣어 주세요" }; return; }
    busy = true; bbMsg = null;
    try {
      const r = await testBitbucket(e, t);
      await commitBitbucket(e, token.trim() || null);
      token = ""; hasToken = true;
      workspaces = r.workspaces;
      if (!settings.prBitbucketWorkspace && r.workspaces.length === 1) setSetting("prBitbucketWorkspace", r.workspaces[0].slug);
      bbMsg = { ok: true, text: `연결됨 · ${r.name} · 워크스페이스 ${r.workspaces.length}개` };
      void emit("pr-config-changed");
    } catch (err) {
      bbMsg = { ok: false, text: err instanceof Error ? err.message : String(err) };
    } finally { busy = false; }
  }

  async function openRepoEditor() {
    const ws = settings.prBitbucketWorkspace;
    if (!ws) return;
    editRepos = true; draft = new Set(bitbucketRepoList()); progress = "저장소 목록을 불러오는 중…";
    try {
      repos = await bitbucketRepositories(ws);
      local = await localBitbucketSlugs(ws);
      progress = "최근 리뷰한 저장소 찾는 중…";
      recent = await recentReviewed(ws, repos.slice(0, 120).map((r) => r.slug), (d, t) => (progress = `최근 리뷰한 저장소 찾는 중… ${d}/${t}`));
      // 처음 고르는 거면 클론된 것 + 최근 리뷰한 것을 미리 고른다
      if (!draft.size) draft = new Set([...local, ...recent].filter((s) => repos.some((r) => r.slug === s)));
      progress = "";
    } catch (e) { progress = e instanceof Error ? e.message : String(e); }
  }

  function saveRepos() {
    setSetting("prBitbucketRepos", [...draft].sort().join(","));
    editRepos = false;
    void emit("pr-config-changed");
  }

  const toggle = (s: string) => { const d = new Set(draft); if (!d.delete(s)) d.add(s); draft = d; };
  let shownRepos = $derived(repos.filter((r) => !query.trim() || r.slug.toLowerCase().includes(query.trim().toLowerCase()) || r.name.toLowerCase().includes(query.trim().toLowerCase())));

  async function setRoots(next: string[]) {
    const def = await defaultCloneRoots();
    setSetting("prCloneRoots", JSON.stringify(next) === JSON.stringify(def) ? "" : JSON.stringify(next));
    roots = next;
  }

  const ghLabel = $derived(
    pr.github.kind === "ok" ? `연결됨 · ${pr.github.login}` : pr.github.kind === "ghMissing" ? "gh CLI 를 찾지 못했어요" :
    pr.github.kind === "loggedOut" ? "gh 로그인이 필요해요" : pr.github.kind === "error" ? pr.github.message : "확인 전");
</script>

<div class="pane">
  <h2>PR</h2>
  <div class="card-title">GitHub</div>
  <div class="card">
    <label class="srow">
      <span>사용</span>
      <input class="switch" type="checkbox" checked={settings.prGitHubEnabled}
        onchange={(e) => { setSetting("prGitHubEnabled", e.currentTarget.checked); if (e.currentTarget.checked) void probeGitHub(true); void emit("pr-config-changed"); }} />
    </label>
    {#if settings.prGitHubEnabled}
      <div class="srow">
        <span class="hint" class:ok={pr.github.kind === "ok"} class:warn={pr.github.kind !== "ok"}>{ghLabel}</span>
        <button class="btn" onclick={() => probeGitHub(true)}>다시 확인</button>
      </div>
      {#if pr.github.kind === "ghMissing" || pr.github.kind === "loggedOut"}
        <div class="srow col"><div class="hint">PowerShell 에서 <code>winget install GitHub.cli</code> 후 <code>gh auth login</code> 을 실행하고 "다시 확인"을 눌러 주세요.</div></div>
      {/if}
    {/if}
  </div>

  <div class="card-title">Bitbucket</div>
  <div class="card">
    <label class="srow">
      <span>사용</span>
      <input class="switch" type="checkbox" checked={settings.prBitbucketEnabled} onchange={(e) => { setSetting("prBitbucketEnabled", e.currentTarget.checked); void emit("pr-config-changed"); }} />
    </label>
    {#if settings.prBitbucketEnabled}
      <div class="srow"><span>이메일</span><input class="field narrow" placeholder="name@company.com" bind:value={email} /></div>
      <div class="srow">
        <span>API 토큰</span>
        <div class="narrow"><PwInput bind:value={token} label={hasToken ? "저장됨 · 바꾸려면 입력" : "API 토큰"} onenter={test} /></div>
      </div>
      <div class="srow">
        <div class="actions">
          <button class="btn" disabled={busy} onclick={test}>{busy ? "확인 중…" : "연결 확인"}</button>
          <button class="link" onclick={() => openUrl("https://id.atlassian.com/manage-profile/security/api-tokens")}>토큰 만들기 ↗</button>
        </div>
        {#if bbMsg}<span class="hint" class:ok={bbMsg.ok} class:err={!bbMsg.ok}>{bbMsg.text}</span>{/if}
      </div>
      <div class="srow col"><div class="hint">읽기 권한(read:user, read:workspace, read:repository, read:pullrequest)이 필요하고, 바로 승인까지 쓰려면 write:pullrequest:bitbucket 도 체크해요. 토큰은 {settings.secretStorage === "file" ? "secrets.json" : "Windows 자격 증명 관리자"}에 저장돼요.</div></div>
      {#if pr.bbNoWrite}<div class="srow col"><div class="hint warn">지금 토큰엔 쓰기 권한이 없어 승인 버튼이 꺼져 있어요. 쓰기 권한이 있는 토큰으로 다시 연결하면 켜져요.</div></div>{/if}
      <div class="srow">
        <span>워크스페이스</span>
        {#if workspaces.length}
          <select class="field narrow" value={settings.prBitbucketWorkspace} onchange={(e) => { setSetting("prBitbucketWorkspace", e.currentTarget.value); setSetting("prBitbucketRepos", ""); }}>
            <option value="">고르기</option>
            {#each workspaces as w (w.slug)}<option value={w.slug}>{w.name} ({w.slug})</option>{/each}
          </select>
        {:else}
          <input class="field narrow" placeholder="연결 확인 후 고르거나 직접 입력" value={settings.prBitbucketWorkspace} onchange={(e) => setSetting("prBitbucketWorkspace", e.currentTarget.value.trim())} />
        {/if}
      </div>
      {#if settings.prBitbucketWorkspace}
        <div class="srow">
          <span>리뷰 요청 볼 저장소 <span class="faint">{bitbucketRepoList().length}개</span></span>
          <button class="btn" onclick={openRepoEditor}>편집</button>
        </div>
      {/if}
    {/if}
  </div>

  {#if editRepos}
    <div class="card">
      <div class="srow col">
        <input class="field" placeholder="저장소 검색" bind:value={query} />
        <div class="hint">{draft.size}개 선택 {progress ? `· ${progress}` : ""} · 이 PC 에 클론된 저장소 {local.length}개{recent.length ? ` · 최근 30일 리뷰 ${recent.length}개` : ""}</div>
        <div class="repos scroll">
          {#each shownRepos as r (r.slug)}
            <label class="repo">
              <input type="checkbox" checked={draft.has(r.slug)} onchange={() => toggle(r.slug)} />
              <span class="grow">{r.name}</span>
              {#if local.includes(r.slug)}<span class="tag">클론</span>{/if}
              {#if recent.includes(r.slug)}<span class="tag">최근 리뷰</span>{/if}
            </label>
          {/each}
        </div>
        <div class="actions"><button class="btn" onclick={() => (editRepos = false)}>취소</button><button class="btn primary" onclick={saveRepos}>저장</button></div>
      </div>
      <div class="srow col">
        <div class="hint"><b>클론 찾을 폴더</b> (고른 폴더 아래 두 단계까지)</div>
        {#each roots as r (r)}
          <div class="actions"><span class="mono small grow">{r}</span><button class="btn" onclick={() => setRoots(roots.filter((x) => x !== r))}>빼기</button></div>
        {/each}
        <div class="actions">
          <input class="field mono grow" placeholder="C:\work\repos" bind:value={newRoot} />
          <button class="btn" disabled={!newRoot.trim()} onclick={() => { setRoots([...roots, newRoot.trim()]); newRoot = ""; }}>폴더 추가</button>
        </div>
      </div>
    </div>
  {/if}

  <div class="card-title">알림</div>
  <div class="card">
    {#each [["prNotifyNewReview", "새 리뷰 요청"], ["prNotifyApproved", "내 PR 승인 (한 명씩)"], ["prNotifyChanges", "내 PR 변경 요청"], ["prNotifyComments", "내 PR 새 댓글·리뷰"]] as const as [k, label] (k)}
      <label class="srow"><span>{label}</span><input class="switch" type="checkbox" checked={settings[k]} onchange={(e) => setSetting(k, e.currentTarget.checked)} /></label>
    {/each}
    <div class="srow col"><div class="hint">알림이 안 오면 Windows 설정 &gt; 시스템 &gt; 알림 에서 ATM 이 허용돼 있는지 확인해 주세요.</div></div>
  </div>

  <div class="card-title">표시</div>
  <div class="card">
    <div class="srow">
      <span>오래 대기 표시</span>
      <select class="field sel" value={settings.prStaleDays} onchange={(e) => setSetting("prStaleDays", Number(e.currentTarget.value))}>
        {#each [1, 2, 3, 5, 7] as d}<option value={d}>{d}일</option>{/each}
      </select>
    </div>
    <label class="srow"><span>Draft PR 숨기기</span><input class="switch" type="checkbox" checked={settings.prHideDrafts} onchange={(e) => { setSetting("prHideDrafts", e.currentTarget.checked); void emit("pr-config-changed"); }} /></label>
    <div class="srow">
      <span>새로고침</span>
      <select class="field sel" value={settings.prRefreshMinutes} onchange={(e) => setSetting("prRefreshMinutes", Number(e.currentTarget.value))}>
        {#each [2, 5, 10, 15] as m}<option value={m}>{m}분</option>{/each}
      </select>
    </div>
    {#each hidden as r (r)}
      <div class="srow"><span>숨긴 저장소 · {r.split(":").slice(1).join(":")}</span><button class="btn" onclick={() => unhideRepo(r)}>다시 보기</button></div>
    {/each}
  </div>
</div>

<style>
  .narrow { width: 300px; }
  .sel { width: auto; padding: 3px 6px; }
  .repos { max-height: 260px; border: 0.5px solid var(--line2); border-radius: 6px; padding: 4px; }
  .repo { display: flex; align-items: center; gap: 8px; padding: 3px 6px; border-radius: 4px; }
  .repo:hover { background: var(--fill); }
  .grow { flex: 1; min-width: 0; }
  .tag { font-size: 0.78em; padding: 0 6px; border-radius: 999px; background: var(--accent-soft); color: var(--accent-text); }
  .small { font-size: 0.86em; }
  code { font-family: "Cascadia Mono", Consolas, monospace; font-size: 0.92em; }
</style>
