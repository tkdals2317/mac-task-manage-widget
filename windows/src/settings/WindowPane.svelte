<script lang="ts">
  // 설정 > 창·일반 (Mac windowPane): 창, 탭, 일반(자동 실행·단축키), 비밀 정보 저장.
  import { emit } from "@tauri-apps/api/event";
  import { enabledTabs, setSetting, settings, toggledTabs } from "../lib/settings.svelte";
  import { native } from "../lib/native";
  import Segmented from "./Segmented.svelte";
  import HotKeyRecorder from "./HotKeyRecorder.svelte";
  import { hotkeyStatus, watchHotkeyStatus } from "../lib/hotkeyStatus.svelte";
  $effect(() => watchHotkeyStatus());

  const TABS = [
    { id: "tasks", title: "할 일" }, { id: "summary", title: "요약" }, { id: "notes", title: "노트" },
    { id: "pr", title: "PR" }, { id: "teleport", title: "Teleport" },
  ];
  const ids = TABS.map((t) => t.id);
  const enabled = $derived(enabledTabs(settings.enabledTabs, ids));
  const dev = import.meta.env.DEV;

  let moving = $state(false);
  let moveMsg = $state("");

  /** 저장 위치를 바꾸면 지금 값들을 새 위치로 옮긴다 (Mac SecretStore.migrate). */
  async function setStorage(to: string) {
    if (to === settings.secretStorage) return;
    moving = true; moveMsg = "";
    try {
      const known: [string, string][] = [];
      if (settings.jiraEmail) known.push(["com.lsm0506.TaskWidget.jira", settings.jiraEmail.trim()]);
      if (settings.prBitbucketEmail) known.push(["com.lsm0506.TaskWidget.bitbucket", settings.prBitbucketEmail.trim()]);
      known.push(["com.lsm0506.TaskWidget.teleport", "credentials"], ["com.lsm0506.TaskWidget.notes", "key"]);
      const values: [string, string, string][] = [];
      for (const [s, a] of known) { const v = await native.secretGet(s, a).catch(() => null); if (v) values.push([s, a, v]); }
      setSetting("secretStorage", to);
      for (const [s, a, v] of values) await native.secretSet(s, a, v);
      moveMsg = values.length ? `${values.length}개를 옮겼어요` : "";
      void emit("pr-config-changed");
    } catch (e) {
      moveMsg = `옮기지 못했어요: ${e}`;
    } finally { moving = false; }
  }
</script>

<div class="pane">
  <h2>창 · 일반</h2>
  <div class="card-title">창</div>
  <div class="card">
    <label class="srow">
      <span>항상 위</span>
      <input class="switch" type="checkbox" checked={settings.alwaysOnTop} onchange={(e) => setSetting("alwaysOnTop", e.currentTarget.checked)} />
    </label>
    <label class="srow">
      <span>전역 단축키로 패널 열기/닫기</span>
      <input class="switch" type="checkbox" checked={settings.globalHotKeyEnabled} onchange={(e) => setSetting("globalHotKeyEnabled", e.currentTarget.checked)} />
    </label>
    {#if settings.globalHotKeyEnabled}
      <div class="srow col">
        <HotKeyRecorder />
        <div class="hint">Ctrl·Alt·Win 중 하나를 함께 눌러야 해요.</div>
        {#if hotkeyStatus.error}<div class="hint warn">{hotkeyStatus.error}. 다른 조합으로 바꿔 주세요.</div>{/if}
      </div>
    {/if}
  </div>

  <div class="card-title">탭</div>
  <div class="card">
    {#each TABS as t (t.id)}
      {@const on = enabled.includes(t.id)}
      <label class="srow">
        <span>{t.title}</span>
        <input class="switch" type="checkbox" checked={on} disabled={on && enabled.length === 1}
          onchange={() => setSetting("enabledTabs", toggledTabs(t.id, settings.enabledTabs, ids))} />
      </label>
    {/each}
    {#if enabled.length === 1}<div class="srow col"><div class="hint">최소 1개는 켜져 있어야 합니다</div></div>{/if}
  </div>

  <div class="card-title">일반</div>
  <div class="card">
    <label class="srow">
      <span>Windows 로그인 시 실행</span>
      <input class="switch" type="checkbox" checked={settings.launchAtLogin} disabled={dev} onchange={(e) => setSetting("launchAtLogin", e.currentTarget.checked)} />
    </label>
    {#if dev}<div class="srow col"><div class="hint">개발 실행(tauri dev)에서는 시작 프로그램에 등록하지 않아요. 설치한 앱에서만 바뀌어요.</div></div>{/if}
  </div>

  <div class="card-title">비밀 정보 저장</div>
  <div class="card">
    <div class="srow">
      <span>저장 위치</span>
      <Segmented value={settings.secretStorage} disabled={moving} onpick={setStorage}
        options={[{ value: "credman", label: "자격 증명 관리자 (권장)" }, { value: "file", label: "파일" }]} />
    </div>
    <div class="srow col">
      {#if settings.secretStorage === "file"}
        <div class="hint warn">Jira·Bitbucket 토큰, Teleport 비밀번호·OTP 키, 노트 Windows Hello 열쇠가 데이터 폴더의 secrets.json 에 암호화 없이 저장돼요.</div>
      {:else}
        <div class="hint">Windows 자격 증명 관리자에 저장돼요 (제어판 &gt; 자격 증명 관리자 &gt; Windows 자격 증명).</div>
      {/if}
      {#if moveMsg}<div class="hint ok">{moveMsg}</div>{/if}
    </div>
  </div>
</div>
