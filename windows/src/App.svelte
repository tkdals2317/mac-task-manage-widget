<script lang="ts">
  // 패널 셸 (Mac RootView + FloatingPanel): 신호등 버튼(빨강 숨기기·노랑 최소화), 탭 바(미끄러지는 알약 + 배지), 탭 내용, 아래 설정 버튼.
  import { emit } from "@tauri-apps/api/event";
  import { getCurrentWindow } from "@tauri-apps/api/window";
  import { openUrl } from "@tauri-apps/plugin-opener";
  import { settings, setSetting, enabledTabs } from "./lib/settings.svelte";
  import { native } from "./lib/native";
  import { toast } from "./lib/toast.svelte";
  import { hotkeyStatus } from "./lib/hotkeyStatus.svelte";
  import { checkUpdate, type UpdateInfo } from "./lib/updater";
  import { badge } from "./lib/pr.svelte";
  import Sym from "./lib/Sym.svelte";
  import TasksTab from "./tabs/TasksTab.svelte";
  import SummaryTab from "./tabs/SummaryTab.svelte";
  import NotesTab from "./tabs/NotesTab.svelte";
  import PRTab from "./tabs/PRTab.svelte";
  import TeleportTab from "./tabs/TeleportTab.svelte";

  const TABS = [
    { id: "tasks", title: "할 일" },
    { id: "summary", title: "요약" },
    { id: "notes", title: "노트" },
    { id: "pr", title: "PR" },
    { id: "teleport", title: "Teleport" },
  ];

  let enabled = $derived(enabledTabs(settings.enabledTabs, TABS.map((t) => t.id)));
  let current = $derived(enabled.includes(settings.lastTab) ? settings.lastTab : enabled[0]);
  let update = $state<UpdateInfo | null>(null);
  let themed = $derived(settings.themePreset !== "default");
  let prBadge = $derived(badge());

  let bar: HTMLDivElement | undefined = $state();
  let pill = $state({ left: 0, width: 0, ready: false });
  $effect(() => {
    // 선택된 탭 버튼 위치로 알약을 옮긴다 (Mac matchedGeometryEffect)
    void current; void enabled; void settings.fontScale; void prBadge;
    requestAnimationFrame(() => {
      const el = bar?.querySelector<HTMLElement>(`[data-tab="${current}"]`);
      if (el) pill = { left: el.offsetLeft, width: el.offsetWidth, ready: true };
    });
  });

  $effect(() => {
    checkUpdate().then((u) => (update = u)).catch(() => {});
    const t = setInterval(() => checkUpdate().then((u) => (update = u)).catch(() => {}), 6 * 3600_000);
    return () => clearInterval(t);
  });

  // 숨길 때 잠긴 메모를 다시 잠그도록 알린다 (트레이·단축키로 숨길 때는 Rust 가 보낸다).
  function hidePanel() {
    emit("panel-hidden").catch(() => {});
    getCurrentWindow().hide();
  }

  function onKey(e: KeyboardEvent) {
    // Esc: 패널 숨김 (입력 중이거나 대화상자·팝오버가 처리하지 않았을 때)
    const tag = (e.target as HTMLElement)?.tagName;
    if (e.key === "Escape" && !e.defaultPrevented && tag !== "INPUT" && tag !== "TEXTAREA" && !document.querySelector(".modal-back, .popover")) hidePanel();
    if (e.key === "," && e.ctrlKey) native.openSettings();
    // Ctrl+1..5 탭 바꾸기
    if (e.ctrlKey && /^[1-5]$/.test(e.key)) {
      const id = TABS.filter((t) => enabled.includes(t.id))[Number(e.key) - 1]?.id;
      if (id) { e.preventDefault(); setSetting("lastTab", id); }
    }
  }
</script>

<svelte:window onkeydown={onKey} />

<div class="panel">
  <div class="titlebar" data-tauri-drag-region>
    <div class="lights">
      <button class="light red" aria-label="숨기기" title="숨기기 (트레이에서 다시 열기)" onclick={hidePanel}>
        <svg viewBox="0 0 12 12"><path d="M3.5 3.5l5 5M8.5 3.5l-5 5" /></svg>
      </button>
      <button class="light yellow" aria-label="최소화" title="작업 표시줄로 최소화" onclick={() => native.minimizePanel()}>
        <svg viewBox="0 0 12 12"><path d="M3 6h6" /></svg>
      </button>
    </div>
    <div class="grow" data-tauri-drag-region></div>
    {#if update}
      <button class="chip solid update" title={update.notes.split("\n").slice(0, 5).join("\n")} onclick={() => openUrl(update!.url)}>
        새 버전 {update.latest}
      </button>
    {/if}
  </div>

  {#if hotkeyStatus.error}
    <button class="hotkey-warn" onclick={() => native.openSettings("window")}>
      <Sym name="warning" /> 단축키: {hotkeyStatus.error} · 설정 &gt; 창 에서 바꾸기
    </button>
  {/if}

  {#if enabled.length > 1}
    <div class="tabbar-wrap">
      <div class="tabbar" class:themed bind:this={bar}>
        <div class="pill" class:ready={pill.ready} style="left:{pill.left}px;width:{pill.width}px"></div>
        {#each TABS.filter((t) => enabled.includes(t.id)) as t (t.id)}
          <button class="tab" class:on={t.id === current} data-tab={t.id} onclick={() => setSetting("lastTab", t.id)}>
            {t.title}
            {#if t.id === "pr" && prBadge > 0}<span class="badge">{prBadge > 99 ? "99+" : prBadge}</span>{/if}
          </button>
        {/each}
      </div>
    </div>
    <div class="divider"></div>
  {/if}

  <div class="content">
    {#if current === "notes"}<NotesTab />
    {:else if current === "summary"}<SummaryTab />
    {:else if current === "pr"}<PRTab />
    {:else if current === "teleport"}<TeleportTab />
    {:else}<TasksTab />{/if}
    {#if toast.text}
      <div class="toast" class:raised={current === "summary"}>{toast.text}</div>
    {/if}
  </div>

  <div class="divider"></div>
  <div class="footer">
    <div class="grow"></div>
    <button class="icon-btn" aria-label="설정" title="설정 (Ctrl+,)" onclick={() => native.openSettings()}>
      <Sym name="gear" size={1.1} weight={1.4} />
    </button>
  </div>
</div>

<style>
  .panel {
    display: flex; flex-direction: column; height: 100%;
    background: var(--bg); border-radius: 10px; overflow: hidden;
    border: 0.5px solid var(--line2);
  }
  .grow { flex: 1; align-self: stretch; }
  .titlebar { display: flex; align-items: center; height: 28px; padding: 0 10px; flex: none; }
  .lights { display: flex; gap: 8px; align-items: center; }
  .light { width: 12px; height: 12px; border-radius: 50%; border: 0.5px solid rgba(0, 0, 0, 0.12); padding: 0; display: inline-flex; align-items: center; justify-content: center; }
  .light svg { width: 8px; height: 8px; stroke: rgba(0, 0, 0, 0.55); stroke-width: 1.4; stroke-linecap: round; opacity: 0; }
  .lights:hover .light svg { opacity: 1; }
  .light.red { background: #FF5F57; }
  .light.yellow { background: #FEBC2E; }
  .light:active { filter: brightness(0.85); }
  .update { margin-left: 6px; }
  .tabbar-wrap { padding: 4px 10px 6px; flex: none; }
  .tabbar { position: relative; display: flex; gap: 2px; padding: 2px; border-radius: 8px; background: var(--fill); }
  .pill {
    position: absolute; top: 2px; bottom: 2px; border-radius: 6px; background: var(--seg-on);
    box-shadow: 0 0.5px 2px rgba(0, 0, 0, 0.16), 0 0 0 0.5px rgba(0, 0, 0, 0.04);
  }
  .pill.ready { transition: left 0.25s cubic-bezier(.3,.7,.3,1), width 0.25s cubic-bezier(.3,.7,.3,1); }
  .tabbar.themed .pill { box-shadow: none; }
  .tab {
    position: relative; flex: 1; padding: 4px 0; border: none; background: transparent; border-radius: 6px;
    color: var(--fg2); font-size: 0.97em; display: inline-flex; align-items: center; justify-content: center; gap: 4px; white-space: nowrap;
  }
  .tab:hover:not(.on) { background: var(--fill); }
  .tab.on { color: var(--seg-on-text); font-weight: 500; }
  .badge {
    min-width: 15px; height: 15px; padding: 0 4px; border-radius: 999px; background: #FF3B30; color: #fff;
    font-size: 0.72em; font-weight: 600; display: inline-flex; align-items: center; justify-content: center; font-variant-numeric: tabular-nums;
  }
  .hotkey-warn {
    margin: 0 10px 6px; padding: 5px 10px; border-radius: 6px; border: none; text-align: left;
    background: var(--warn-soft); color: var(--warn); font-size: 0.88em; flex: none; display: flex; align-items: center; gap: 5px;
  }
  .divider { height: 0.5px; background: var(--line2); flex: none; }
  .content { position: relative; flex: 1; min-height: 0; display: flex; flex-direction: column; }
  .footer { display: flex; align-items: center; padding: 3px 8px; flex: none; }
  .toast {
    position: absolute; left: 50%; bottom: 10px; transform: translateX(-50%);
    padding: 5px 14px; border-radius: 999px; background: var(--fg); color: var(--bg); font-size: 0.88em;
    pointer-events: none; box-shadow: 0 4px 14px rgba(0, 0, 0, 0.2); white-space: nowrap;
  }
  .toast.raised { bottom: 52px; }
</style>
