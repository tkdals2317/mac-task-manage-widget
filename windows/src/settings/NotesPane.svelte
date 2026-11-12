<script lang="ts">
  import { onMount } from "svelte";
  import { JIRA_KEYCHAIN_SERVICE } from "../lib/jira";
  import { native } from "../lib/native";
  import { setSetting, settings } from "../lib/settings.svelte";
  import { changePassword, createPassword, disableHello, enableHello, hasLock, resetPassword } from "../lib/notes.svelte";
  import PwInput from "./PwInput.svelte";
  import { testConfluence } from "./jiraTest";

  let pw = $state(""), pw2 = $state(""), oldPw = $state("");
  let showChange = $state(false), confirmReset = $state(false);
  let message = $state(""), isError = $state(false), busy = $state(false);
  let askHello = $state(false), helloPw = $state(""), helloMessage = $state("");
  let helloOk = $state(true);
  let confluenceDraft = $state(settings.confluenceBaseURL);
  let confluenceStatus = $state(""), confluenceOk = $state(false);

  onMount(() => {
    native.helloAvailable().then((v) => (helloOk = v), () => (helloOk = false));
    return commitConfluence; // 창을 닫거나 다른 칸으로 가도 입력한 주소는 저장
  });

  const commitConfluence = () => setSetting("confluenceBaseURL", confluenceDraft.trim());

  async function run(work: () => Promise<string>) {
    busy = true; message = "";
    try { message = await work(); isError = false; }
    catch (e) { message = e instanceof Error ? e.message : String(e); isError = true; }
    finally { busy = false; }
  }
  const clear = () => { oldPw = ""; pw = ""; pw2 = ""; };

  async function turnOnHello() {
    busy = true; helloMessage = "";
    try { await enableHello(helloPw); askHello = false; helloPw = ""; }
    catch (e) { helloMessage = e instanceof Error ? e.message : String(e); }
    finally { busy = false; }
  }
  async function testC() {
    commitConfluence();
    confluenceStatus = "확인 중…"; confluenceOk = false;
    const email = settings.jiraEmail.trim();
    const token = email ? await native.secretGet(JIRA_KEYCHAIN_SERVICE, email).catch(() => null) : null;
    const r = await testConfluence(confluenceDraft, email, token);
    confluenceStatus = r.text; confluenceOk = r.ok;
  }
</script>

<div class="pane">
  <h2>노트</h2>

  <div class="card-title">잠금 비밀번호</div>
  <div class="card">
    <div class="srow col">
      {#if !hasLock()}
        <PwInput label="새 비밀번호" bind:value={pw} />
        <PwInput label="비밀번호 확인" bind:value={pw2} />
        <div class="actions">
          <button class="btn" disabled={busy} onclick={() => run(async () => { await createPassword(pw, pw2); clear(); return "비밀번호를 만들었어요"; })}>만들기</button>
          <span class="hint">4자 이상</span>
        </div>
        <div class="hint warn">비밀번호를 잊으면 잠긴 메모는 되살릴 수 없습니다.</div>
      {:else}
        <div class="actions"><span>상태</span><span class="muted">설정됨</span></div>
        {#if showChange}
          <PwInput label="현재 비밀번호" bind:value={oldPw} />
          <PwInput label="새 비밀번호" bind:value={pw} />
          <PwInput label="새 비밀번호 확인" bind:value={pw2} />
          <div class="actions">
            <button class="btn" disabled={busy} onclick={() => run(async () => { await changePassword(oldPw, pw, pw2); clear(); showChange = false; return "비밀번호를 바꿨어요"; })}>변경</button>
            <button class="btn" onclick={() => { showChange = false; clear(); }}>취소</button>
          </div>
        {:else if confirmReset}
          <div class="hint warn">비밀번호를 초기화할까요? 잠긴 메모는 비밀번호 없이 열 수 없어서 전부 삭제됩니다. 잠기지 않은 메모는 그대로 남아요.</div>
          <div class="actions">
            <button class="btn danger" disabled={busy} onclick={() => run(async () => { await resetPassword(); confirmReset = false; return "초기화했어요"; })}>잠긴 메모를 모두 삭제하고 초기화</button>
            <button class="btn" onclick={() => (confirmReset = false)}>취소</button>
          </div>
        {:else}
          <div class="actions">
            <button class="btn" onclick={() => (showChange = true)}>비밀번호 변경</button>
            <button class="btn danger" onclick={() => (confirmReset = true)}>비밀번호 초기화</button>
          </div>
        {/if}
      {/if}
      {#if message}<div class="hint" class:err={isError}>{message}</div>{/if}
    </div>
  </div>
  <div class="hint">메모마다 잠금을 켤 수 있고, 비밀번호는 모든 잠긴 메모가 함께 씁니다. 잠긴 메모는 패널을 닫거나 5분이 지나면 다시 잠겨요.</div>

  <div class="card-title">Windows Hello</div>
  <div class="card">
    <label class="srow">
      <span>Windows Hello 로 열기</span>
      <input class="switch" type="checkbox" checked={settings.notesHello || askHello} disabled={!hasLock() || !helloOk}
        onchange={(e) => {
          if (e.currentTarget.checked) askHello = true;
          else if (askHello) { askHello = false; helloPw = ""; }
          else disableHello();
        }} />
    </label>
    {#if askHello}
      <div class="srow col">
        <PwInput label="잠금 비밀번호" bind:value={helloPw} onenter={turnOnHello} />
        <div class="actions">
          <button class="btn" disabled={busy} onclick={turnOnHello}>켜기</button>
          <button class="btn" onclick={() => { askHello = false; helloPw = ""; }}>취소</button>
        </div>
      </div>
    {/if}
    {#if helloMessage}<div class="hint err" style="padding-bottom:10px">{helloMessage}</div>{/if}
    {#if !helloOk}
      <div class="hint" style="padding-bottom:10px">이 PC 에서는 Windows Hello 를 쓸 수 없어요</div>
    {:else if !hasLock()}
      <div class="hint" style="padding-bottom:10px">먼저 잠금 비밀번호를 만드세요</div>
    {/if}
  </div>
  <div class="hint">Windows Hello 를 켜면 메모 열쇠가 Windows 자격 증명 관리자에 저장됩니다. 끄면 지워져요.</div>

  <div class="card-title">Confluence</div>
  <div class="card">
    <div class="srow col">
      <input class="field selectable" placeholder="https://your-site.atlassian.net" aria-label="주소" bind:value={confluenceDraft}
        onkeydown={(e) => { if (e.key === "Enter") commitConfluence(); }} onblur={commitConfluence} />
      <div class="actions">
        <button class="btn" disabled={!confluenceDraft.trim()} onclick={testC}>연결 확인</button>
        <span class="hint selectable" class:ok={confluenceOk} class:err={!confluenceOk && confluenceStatus !== "" && confluenceStatus !== "확인 중…"}>{confluenceStatus}</span>
      </div>
    </div>
  </div>
  <div class="hint">Jira 와 같은 Atlassian 계정 토큰을 씁니다. 비워 두면 노트 탭에서 Confluence 별표 문서를 숨겨요.</div>
</div>
