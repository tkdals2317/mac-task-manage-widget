<script lang="ts">
  import { onMount } from "svelte";
  import { getVersion } from "@tauri-apps/api/app";
  import { openUrl, revealItemInDir } from "@tauri-apps/plugin-opener";
  import { native } from "../lib/native";
  import { checkUpdate, REPO, type UpdateInfo } from "../lib/updater";
  import { settings } from "../lib/settings.svelte";
  import { hookStatus } from "../lib/claude";

  let { onopenwizard }: { onopenwizard?: () => void } = $props();
  let diagBusy = $state(false);
  let diagMsg = $state<{ ok: boolean; text: string; path?: string } | null>(null);

  /** 로그·설정 요약 zip (비밀번호·OTP·토큰·노트·할 일 내용은 넣지 않음). */
  async function exportDiag() {
    diagBusy = true; diagMsg = null;
    try {
      const [exe, claude, gh, tsh, git] = await Promise.all([
        native.exePath().catch(() => ""),
        native.which("claude", settings.claudePath).catch(() => null),
        native.which("gh").catch(() => null),
        native.which("tsh", settings.tshPath).catch(() => null),
        native.which("git").catch(() => null),
      ]);
      const hooks = await hookStatus().catch(() => "?");
      const ver = async (p: [string, string] | null, args: string[]) => (p ? (await native.run(p[0], args, { timeoutMs: 8000 }).catch(() => null))?.stdout.split("\n")[0].trim() ?? "" : "없음");
      const lines = [
        `ATM Windows ${version}`, `생성 ${new Date().toString()}`, `실행 파일 ${exe}`, `데이터 폴더 ${dir}`,
        `UA ${navigator.userAgent}`, "",
        `claude ${claude?.[0] ?? "없음"} ${await ver(claude, ["--version"])}`,
        `gh ${gh?.[0] ?? "없음"} ${await ver(gh, ["--version"])}`,
        `tsh ${tsh?.[0] ?? "없음"} ${await ver(tsh, ["version"])}`,
        `git ${git?.[0] ?? "없음"} ${await ver(git, ["--version"])}`,
        `Claude 훅 ${hooks}`, "",
        `탭 ${settings.enabledTabs} · 비밀 저장 ${settings.secretStorage} · 단축키 ${settings.globalHotKeyEnabled ? settings.globalHotKey : "끔"}`,
        `Jira ${settings.jiraBaseURL ? "설정됨" : "없음"} · Confluence ${settings.confluenceBaseURL ? "설정됨" : "없음"}`,
        `PR GitHub ${settings.prGitHubEnabled} · Bitbucket ${settings.prBitbucketEnabled} (저장소 ${settings.prBitbucketRepos.split(",").filter(Boolean).length}개)`,
        `요약 ${settings.summaryHour}:${String(settings.summaryMinute).padStart(2, "0")} 알림 ${settings.summaryNotify}`,
        `Teleport 자동 연결 ${settings.teleportAutoConnect} 주기 ${settings.teleportCheckSeconds}s`,
      ];
      const path = await native.exportDiagnostics(lines.join("\n") + "\n");
      diagMsg = { ok: true, text: `바탕 화면에 만들었어요: ${path.split(/[\\/]/).pop()}`, path };
    } catch (e) {
      diagMsg = { ok: false, text: `만들지 못했어요: ${e}` };
    } finally { diagBusy = false; }
  }

  let version = $state("");
  let dir = $state("");
  let checking = $state(false);
  let checked = $state(false);
  let update = $state<UpdateInfo | null>(null);
  let error = $state("");

  onMount(() => {
    getVersion().then((v) => (version = v), () => {});
    native.dataDir().then((d) => (dir = d), () => {});
  });

  async function check() {
    checking = true; error = ""; checked = false;
    try { update = await checkUpdate(); checked = true; }
    catch (e) { error = `확인하지 못했어요: ${e instanceof Error ? e.message : e}`; }
    finally { checking = false; }
  }
</script>

<div class="pane">
  <h2>정보</h2>
  <div class="card">
    <div class="srow"><span>앱</span><span class="muted">ATM (Ats Task Manager)</span></div>
    <div class="srow"><span>버전</span><span class="muted selectable">{version}</span></div>
    <div class="srow">
      <span>데이터 폴더</span>
      <span class="hint selectable grow" style="text-align:right;word-break:break-all">{dir}</span>
      <button class="btn" disabled={!dir} onclick={() => revealItemInDir(dir)}>폴더 열기</button>
    </div>
    <div class="srow">
      <span>GitHub</span>
      <button class="link" onclick={() => openUrl(`https://github.com/${REPO}`)}>{REPO} ↗</button>
    </div>
  </div>

  <div class="card-title">업데이트</div>
  <div class="card">
    <div class="srow">
      <span>업데이트 확인</span>
      <button class="btn" disabled={checking} onclick={check}>{checking ? "확인 중…" : "업데이트 확인"}</button>
    </div>
    {#if update}
      <div class="srow col">
        <span>새 버전 {update.latest}</span>
        {#if update.notes}<div class="hint selectable" style="white-space:pre-wrap;max-height:180px;overflow:auto">{update.notes}</div>{/if}
        <div class="actions"><button class="btn primary" onclick={() => openUrl(update!.url)}>릴리스 페이지 열기</button></div>
      </div>
    {:else if checked}
      <div class="srow"><span class="muted">최신 버전이에요 ({version})</span></div>
    {/if}
    {#if error}<div class="srow"><span class="hint err selectable">{error}</span></div>{/if}
  </div>

  <div class="card-title">설정 도우미</div>
  <div class="card">
    <div class="srow">
      <span>처음 설정 다시 하기</span>
      <button class="btn" onclick={() => onopenwizard?.()}>설정 도우미 열기</button>
    </div>
    <div class="srow col"><div class="hint">쓸 기능을 고르고 Jira·노트·Claude·PR·Teleport 를 차례로 설정해요. 지금 값이 채워진 채로 열려요.</div></div>
  </div>

  <div class="card-title">문제 해결</div>
  <div class="card">
    <div class="srow">
      <span>진단 정보</span>
      <span class="actions">
        <button class="btn" onclick={() => native.openDataPath("logs")}>로그 폴더</button>
        <button class="btn" disabled={diagBusy} onclick={exportDiag}>{diagBusy ? "만드는 중…" : "진단 정보 내보내기"}</button>
      </span>
    </div>
    {#if diagMsg}
      <div class="srow">
        <span class="hint" class:ok={diagMsg.ok} class:err={!diagMsg.ok}>{diagMsg.text}</span>
        {#if diagMsg.path}<button class="btn" onclick={() => native.revealPath(diagMsg!.path!)}>파일 보기</button>{/if}
      </div>
    {/if}
    <div class="srow col"><div class="hint">로그와 설정 요약을 zip 으로 만들어요. 비밀번호·OTP·토큰은 들어가지 않아요. 이 파일을 개발자에게 보내 주세요.</div></div>
  </div>
</div>
