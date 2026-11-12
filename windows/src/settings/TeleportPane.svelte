<script lang="ts">
  // 설정 > Teleport (Mac teleportPane): tsh 경로, 자동 연결·확인 주기, 설정 다시 하기, teleport.json 열기.
  import { onMount } from "svelte";
  import { emit } from "@tauri-apps/api/event";
  import { setSetting, settings, toggledTabs, enabledTabs } from "../lib/settings.svelte";
  import { native } from "../lib/native";
  import Segmented from "./Segmented.svelte";

  let found = $state<[string, string] | null | undefined>(undefined);
  const ALL = ["tasks", "summary", "notes", "pr", "teleport"];

  async function find() { found = await native.which("tsh", settings.tshPath).catch(() => null); }
  onMount(() => { void find(); });

  function redoSetup() {
    if (!enabledTabs(settings.enabledTabs, ALL).includes("teleport")) setSetting("enabledTabs", toggledTabs("teleport", settings.enabledTabs, ALL));
    setSetting("lastTab", "teleport");
    void emit("teleport-setup-requested");
  }
</script>

<div class="pane">
  <h2>Teleport</h2>
  <div class="card">
    <div class="srow">
      <span>tsh</span>
      <span class="hint selectable">{found ? `${found[0]} (${found[1]})` : found === null ? "찾지 못함" : "찾는 중…"}</span>
    </div>
    <div class="srow">
      <span>tsh 경로</span>
      <input class="field narrow mono" placeholder="비우면 자동 탐색 (PATH)" value={settings.tshPath}
        onchange={(e) => { setSetting("tshPath", e.currentTarget.value.trim()); setTimeout(find, 400); void emit("teleport-config-changed"); }} />
    </div>
    <div class="srow col"><div class="actions"><button class="btn" onclick={find}>다시 찾기</button></div></div>
  </div>
  <div class="card">
    <label class="srow">
      <span>ATM 시작 시 마지막에 켜 둔 DB 자동 연결</span>
      <input class="switch" type="checkbox" checked={settings.teleportAutoConnect} onchange={(e) => setSetting("teleportAutoConnect", e.currentTarget.checked)} />
    </label>
    <div class="srow">
      <span>연결 확인 주기</span>
      <Segmented value={settings.teleportCheckSeconds} onpick={(v) => setSetting("teleportCheckSeconds", v)}
        options={[{ value: 30, label: "30초" }, { value: 60, label: "1분" }, { value: 120, label: "2분" }, { value: 300, label: "5분" }]} />
    </div>
  </div>
  <div class="card">
    <div class="srow col">
      <div class="actions">
        <button class="btn" onclick={redoSetup}>설정 다시 하기</button>
        <button class="btn" onclick={() => native.openDataPath("teleport.json", false)}>teleport.json 열기</button>
        <button class="btn" onclick={() => native.openDataPath("logs/teleport-login.log", true)}>로그인 기록</button>
      </div>
      <div class="hint">탭이 꺼져 있으면 켜지고, Teleport 탭에서 설정이 이어집니다. 비밀번호·OTP 키는 {settings.secretStorage === "file" ? "secrets.json" : "Windows 자격 증명 관리자"}에 저장돼요. 그룹 이름은 teleport.json 에서 DB 에 "group" 을 넣어 바꿀 수 있어요.</div>
    </div>
  </div>
</div>

<style>
  .narrow { width: 300px; }
</style>
