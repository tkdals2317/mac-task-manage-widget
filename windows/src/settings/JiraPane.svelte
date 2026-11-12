<script lang="ts">
  import { emit } from "@tauri-apps/api/event";
  import { openUrl } from "@tauri-apps/plugin-opener";
  import { native } from "../lib/native";
  import { DEFAULT_JQL, JIRA_KEYCHAIN_SERVICE, JIRA_TOKEN_URL } from "../lib/jira";
  import { setSetting, settings } from "../lib/settings.svelte";
  import Segmented from "./Segmented.svelte";
  import { testJira } from "./jiraTest";

  let { hasToken = $bindable(false) }: { hasToken?: boolean } = $props();

  let token = $state("");
  let status = $state("");
  let statusKind = $state<"" | "ok" | "err">("");
  let busy = $state(false);

  function say(text: string, kind: "" | "ok" | "err" = "") { status = text; statusKind = kind; }

  async function saveToken() {
    const email = settings.jiraEmail.trim();
    const t = token.trim();
    if (!email) return say("이메일을 먼저 입력하세요", "err");
    if (!t) return say("토큰이 비어 있음 — Ctrl+V 로 붙여넣으세요", "err");
    busy = true;
    try {
      await native.secretSet(JIRA_KEYCHAIN_SERVICE, email, t);
      token = ""; // 저장한 토큰은 칸에 다시 보여주지 않는다
      hasToken = true;
      say("저장됨", "ok");
      emit("jira-token-saved").catch(() => {});
    } catch (e) {
      say(`저장 실패: ${e}`, "err");
    } finally { busy = false; }
    if (hasToken) await test();
  }

  async function test() {
    const email = settings.jiraEmail.trim();
    say("확인 중…");
    busy = true;
    try {
      const t = email ? await native.secretGet(JIRA_KEYCHAIN_SERVICE, email).catch(() => null) : null;
      if (!t) return say("토큰 없음", "err");
      const r = await testJira(settings.jiraBaseURL, email, t);
      say(r.text, r.ok ? "ok" : "err");
      if (r.ok) setSetting("onboardingDone", true); // 동작하는 연결이면 첫 안내는 끝
    } finally { busy = false; }
  }
</script>

<div class="pane">
  <h2>Jira</h2>
  {#if !settings.onboardingDone}
    <div class="banner">
      <span>Jira 를 연결하면 할 일 탭에 내 이슈가 보여요</span>
      <button class="btn" onclick={() => setSetting("onboardingDone", true)}>나중에</button>
    </div>
  {/if}

  <div class="card-title">계정</div>
  <div class="card">
    <div class="srow col">
      <input class="field selectable" placeholder="https://your-site.atlassian.net" aria-label="URL" value={settings.jiraBaseURL}
        oninput={(e) => setSetting("jiraBaseURL", e.currentTarget.value.trim())} />
      <input class="field selectable" placeholder="name@company.com" aria-label="이메일" value={settings.jiraEmail}
        oninput={(e) => setSetting("jiraEmail", e.currentTarget.value.trim())}
        onchange={async () => { const m = settings.jiraEmail.trim(); hasToken = m ? (await native.secretGet(JIRA_KEYCHAIN_SERVICE, m).catch(() => null)) != null : false; }} />
      <div class="actions">
        <input class="field selectable" style="flex:1;min-width:160px;width:auto" type="password" autocomplete="off" aria-label="API 토큰"
          placeholder={hasToken ? "API 토큰 (저장됨 · 바꾸려면 입력)" : "API 토큰"} bind:value={token}
          onkeydown={(e) => { if (e.key === "Enter") saveToken(); }} />
        <button class="btn" disabled={busy} onclick={saveToken}>저장</button>
        <button class="link" onclick={() => openUrl(JIRA_TOKEN_URL)}>토큰 발급 ↗</button>
      </div>
      {#if hasToken}<div class="hint ok">토큰 저장됨</div>{/if}
      <div class="hint">Atlassian 계정 &gt; 보안 &gt; API 토큰에서 'API 토큰 만들기' 후 복사해 붙여넣으세요. 토큰은 Windows 자격 증명 관리자에 저장돼요.</div>
      <div class="actions">
        <button class="btn" disabled={busy} onclick={test}>연결 테스트</button>
        <span class="hint selectable" class:ok={statusKind === "ok"} class:err={statusKind === "err"}>{status}</span>
      </div>
    </div>
  </div>

  <div class="card-title">동기화</div>
  <div class="card">
    <div class="srow">
      <span>갱신 주기</span>
      <Segmented value={settings.jiraRefreshMinutes} onpick={(v) => setSetting("jiraRefreshMinutes", v)}
        options={[{ value: 1, label: "1분" }, { value: 5, label: "5분" }, { value: 15, label: "15분" }]} />
    </div>
    <div class="srow col">
      <textarea class="field mono selectable" rows="3" placeholder={DEFAULT_JQL} aria-label="JQL" value={settings.jiraJQL}
        oninput={(e) => setSetting("jiraJQL", e.currentTarget.value)}></textarea>
      <div class="actions">
        <span class="hint selectable grow" style="flex:1">{settings.jiraJQL ? `기본값: ${DEFAULT_JQL}` : "비워 두면 위 기본값으로 조회합니다."}</span>
        {#if settings.jiraJQL}<button class="btn" onclick={() => setSetting("jiraJQL", "")}>기본값으로</button>{/if}
      </div>
    </div>
  </div>
</div>
