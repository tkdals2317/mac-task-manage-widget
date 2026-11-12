<script lang="ts">
  import { onMount } from "svelte";
  import { getVersion } from "@tauri-apps/api/app";
  import { openUrl, revealItemInDir } from "@tauri-apps/plugin-opener";
  import { native } from "../lib/native";
  import { checkUpdate, REPO, type UpdateInfo } from "../lib/updater";

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
</div>
