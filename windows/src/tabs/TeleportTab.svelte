<script lang="ts">
  // Teleport 탭 (Mac TeleportView): 로그인 상태·다시 로그인·모두 연결/끊기, 그룹별 DB 토글.
  import { onMount } from "svelte";
  import Sym from "../lib/Sym.svelte";
  import { native } from "../lib/native";
  import { copyText } from "../lib/toast.svelte";
  import TeleportSetup from "../teleport/TeleportSetup.svelte";
  import {
    tp, stateOf, loggedIn, isConfigured, connect, disconnect, connectAll, disconnectAll, relogin, refreshStatus, locateTsh,
  } from "../lib/teleport.svelte";
  import { groupOf, remainingText, type TeleportTunnel } from "../lib/teleportCore";

  let now = $state(Date.now());
  onMount(() => {
    void locateTsh().then(refreshStatus);
    const t = setInterval(() => (now = Date.now()), 30_000);
    return () => clearInterval(t);
  });

  let groups = $derived.by(() => {
    const m = new Map<string, TeleportTunnel[]>();
    for (const t of tp.config.tunnels) m.set(groupOf(t), [...(m.get(groupOf(t)) ?? []), t]);
    return [...m.entries()];
  });

  const dotColor = (t: TeleportTunnel) => {
    const s = stateOf(t).kind;
    return s === "connected" ? "var(--ok)" : s === "connecting" ? "var(--warn)" : s === "failed" || s === "portInUse" ? "var(--danger)" : "var(--fg3)";
  };
  const stateText = (t: TeleportTunnel) => {
    const s = stateOf(t);
    return s.kind === "connected" ? "연결됨" : s.kind === "connecting" ? "연결 중…" : s.kind === "portInUse" ? "포트 사용 중" : s.kind === "failed" ? s.message : "끊김";
  };
  const on = (t: TeleportTunnel) => ["connected", "connecting"].includes(stateOf(t).kind);
  let anyOn = $derived(tp.config.tunnels.some((t) => stateOf(t).kind !== "disconnected"));
</script>

{#if !tp.loaded}
  <div class="empty">불러오는 중…</div>
{:else if tp.setupRequested || !isConfigured()}
  <TeleportSetup />
{:else}
  <div class="tele">
    <div class="top">
      {#if tp.busy}
        <span class="st"><span class="spin"><Sym name="refresh" /></span> {tp.busy}</span>
      {:else if loggedIn()}
        <span class="st ok"><Sym name="check-circle" /> 로그인됨 <span class="faint">· {remainingText(tp.validUntil!, new Date(now))}</span></span>
      {:else}
        <span class="st"><Sym name="minus-circle" /> 로그인 필요</span>
      {/if}
      <span class="grow"></span>
      {#if !loggedIn() && !tp.busy}
        <button class="chip solid" onclick={relogin}><Sym name="arrow-right-circle" />다시 로그인</button>
      {/if}
      <button class="chip soft" disabled={!!tp.busy} onclick={connectAll}><Sym name="link" />모두 연결</button>
      <button class="chip plain" disabled={!anyOn && !loggedIn()} onclick={disconnectAll}><Sym name="x" />모두 끊기</button>
    </div>
    {#if tp.message}<div class="msg">{tp.message} <button class="chip" onclick={() => native.openDataPath("logs/teleport-login.log", true)}>로그</button></div>{/if}
    {#if !tp.tshPath}<div class="msg">tsh 를 찾지 못했어요 · 설정 &gt; Teleport 에서 경로를 지정해 주세요</div>{/if}
    <div class="list scroll">
      {#each groups as [g, ts] (g)}
        <div class="group">{g} <span>{ts.filter((t) => stateOf(t).kind === "connected").length}/{ts.length} 연결</span></div>
        {#each ts as t (t.name)}
          <div class="row">
            <span class="dot" style="background:{dotColor(t)}"></span>
            <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
            <div class="main" title="누르면 접속 주소 복사" onclick={() => copyText(t.kind === "app" ? `http://localhost:${t.port}` : `localhost:${t.port}`, "주소를 복사했어요")}>
              <div class="name">{t.name}{#if t.kind === "app"}<span class="tag">HTTP</span>{/if}</div>
              <div class="sub" class:bad={stateOf(t).kind === "failed" || stateOf(t).kind === "portInUse"}>
                {t.kind === "app" ? "http://" : ""}localhost:{t.port} · {stateText(t)}
                {#if stateOf(t).kind === "failed"}
                  <button class="link" onclick={(e) => { e.stopPropagation(); native.openDataPath(`logs/teleport-${t.name}.log`, true); }}>로그</button>
                {/if}
              </div>
            </div>
            <input class="switch" type="checkbox" checked={on(t)} disabled={stateOf(t).kind === "connecting"}
              onchange={(e) => (e.currentTarget.checked ? connect(t) : disconnect(t))} aria-label="{t.name} 연결" />
          </div>
        {/each}
      {/each}
    </div>
  </div>
{/if}

<style>
  .empty { padding: 20px; color: var(--fg2); }
  .tele { display: flex; flex-direction: column; height: 100%; min-height: 0; }
  .top { display: flex; align-items: center; gap: 6px; padding: 8px 12px; border-bottom: 0.5px solid var(--line2); flex: none; }
  .st { display: inline-flex; align-items: center; gap: 5px; font-weight: 600; color: var(--fg2); }
  .st.ok { color: var(--ok); }
  .grow { flex: 1; }
  .msg { margin: 6px 12px 0; padding: 6px 8px; border-radius: 6px; background: var(--warn-soft); color: var(--warn); font-size: 0.85em; line-height: 1.45; }
  .list { flex: 1; min-height: 0; padding: 4px 8px 12px 12px; }
  .group { margin: 12px 0 4px; font-size: 0.85em; font-weight: 700; color: var(--fg2); }
  .group span { font-weight: 600; margin-left: 6px; }
  .row { display: flex; align-items: center; gap: 10px; padding: 5px 0; }
  .dot { width: 9px; height: 9px; border-radius: 50%; flex: none; }
  .main { flex: 1; min-width: 0; }
  .name { font-weight: 500; display: flex; align-items: center; gap: 6px; }
  .tag { font-size: 0.72em; font-weight: 700; padding: 0 5px; border-radius: 4px; background: var(--fill2); color: var(--fg2); }
  .sub { font-size: 0.85em; color: var(--fg2); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .sub.bad { color: var(--danger); }
  .link { border: none; background: none; color: var(--accent-text); padding: 0; margin-left: 4px; font-size: inherit; }
</style>
