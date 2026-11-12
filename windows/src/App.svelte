<script lang="ts">
  // 패널 셸: 맨 위 끌기 줄(− ✕), 탭 바(미끄러지는 알약), 탭 내용, 아래 설정 버튼, 복사 알림.
  import { getCurrentWindow } from "@tauri-apps/api/window";
  import { openUrl } from "@tauri-apps/plugin-opener";
  import { settings, setSetting, enabledTabs } from "./lib/settings.svelte";
  import { native } from "./lib/native";
  import { toast } from "./lib/toast.svelte";
  import { checkUpdate, type UpdateInfo } from "./lib/updater";
  import TasksTab from "./tabs/TasksTab.svelte";
  import NotesTab from "./tabs/NotesTab.svelte";

  // 1단계 탭. 요약·PR·Teleport 는 다음 단계에서 여기에 한 줄씩 추가한다.
  const TABS = [
    { id: "tasks", title: "할 일" },
    { id: "notes", title: "노트" },
  ];

  const win = getCurrentWindow();
  let enabled = $derived(enabledTabs(settings.enabledTabs, TABS.map((t) => t.id)));
  let current = $derived(enabled.includes(settings.lastTab) ? settings.lastTab : enabled[0]);
  let update = $state<UpdateInfo | null>(null);

  let bar: HTMLDivElement | undefined = $state();
  let pill = $state({ left: 0, width: 0 });
  $effect(() => {
    // 선택된 탭 버튼 위치로 알약을 옮긴다 (Mac 탭 바 슬라이드 애니메이션)
    void current;
    void enabled;
    void settings.fontScale;
    const el = bar?.querySelector<HTMLElement>(`[data-tab="${current}"]`);
    if (el) pill = { left: el.offsetLeft, width: el.offsetWidth };
  });

  $effect(() => {
    checkUpdate().then((u) => (update = u)).catch(() => {});
    const t = setInterval(() => checkUpdate().then((u) => (update = u)).catch(() => {}), 6 * 3600_000);
    return () => clearInterval(t);
  });

  function onKey(e: KeyboardEvent) {
    // Esc: 패널 숨김 (입력 중이 아닐 때)
    const tag = (e.target as HTMLElement)?.tagName;
    if (e.key === "Escape" && tag !== "INPUT" && tag !== "TEXTAREA") win.hide();
    if (e.key === "," && e.ctrlKey) native.openSettings();
  }
</script>

<svelte:window onkeydown={onKey} />

<div class="panel">
  <div class="titlebar" data-tauri-drag-region>
    <div class="grow" data-tauri-drag-region></div>
    {#if update}
      <button class="chip accent update" title={update.notes.split("\n").slice(0, 5).join("\n")} onclick={() => openUrl(update!.url)}>
        새 버전 {update.latest}
      </button>
    {/if}
    <button class="win-btn" aria-label="최소화" title="최소화" onclick={() => win.minimize()}>
      <svg width="10" height="10" viewBox="0 0 10 10"><path d="M1 5h8" stroke="currentColor" stroke-width="1" /></svg>
    </button>
    <button class="win-btn close" aria-label="숨기기" title="숨기기 (트레이에서 다시 열기)" onclick={() => win.hide()}>
      <svg width="10" height="10" viewBox="0 0 10 10"><path d="M1 1l8 8M9 1l-8 8" stroke="currentColor" stroke-width="1" /></svg>
    </button>
  </div>

  {#if enabled.length > 1}
    <div class="tabbar-wrap">
      <div class="tabbar" bind:this={bar}>
        <div class="pill" style="left:{pill.left}px;width:{pill.width}px"></div>
        {#each TABS.filter((t) => enabled.includes(t.id)) as t (t.id)}
          <button class="tab" class:on={t.id === current} data-tab={t.id} onclick={() => setSetting("lastTab", t.id)}>
            {t.title}
          </button>
        {/each}
      </div>
    </div>
    <div class="divider"></div>
  {/if}

  <div class="content">
    {#if current === "notes"}
      <NotesTab />
    {:else}
      <TasksTab />
    {/if}
    {#if toast.text}
      <div class="toast">{toast.text}</div>
    {/if}
  </div>

  <div class="divider"></div>
  <div class="footer">
    <div class="grow"></div>
    <button class="icon-btn" aria-label="설정" title="설정 (Ctrl+,)" onclick={() => native.openSettings()}>
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6">
        <circle cx="12" cy="12" r="3" />
        <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
      </svg>
    </button>
  </div>
</div>

<style>
  .panel { display: flex; flex-direction: column; height: 100%; }
  .grow { flex: 1; align-self: stretch; }
  .titlebar { display: flex; align-items: center; height: 30px; padding-left: 10px; flex: none; }
  .update { margin-right: 6px; }
  .win-btn {
    width: 40px; height: 30px; border: none; background: transparent; color: var(--fg2);
    display: inline-flex; align-items: center; justify-content: center; cursor: pointer;
  }
  .win-btn:hover { background: var(--fill2); color: var(--fg); }
  .win-btn.close:hover { background: #C42B1C; color: #fff; }
  .tabbar-wrap { padding: 0 10px 6px; flex: none; }
  .tabbar { position: relative; display: flex; background: var(--fill); border-radius: 8px; padding: 3px; }
  .pill {
    position: absolute; top: 3px; bottom: 3px; border-radius: 6px; background: var(--accent-soft);
    transition: left 0.22s cubic-bezier(.3,.7,.3,1), width 0.22s cubic-bezier(.3,.7,.3,1);
  }
  .tab {
    position: relative; flex: 1; padding: 5px 0; border: none; background: transparent;
    color: var(--fg2); cursor: pointer; border-radius: 6px; font-size: 1.05em;
  }
  .tab.on { color: var(--accent); }
  .divider { height: 1px; background: var(--line); flex: none; }
  .content { position: relative; flex: 1; min-height: 0; display: flex; flex-direction: column; }
  .footer { display: flex; align-items: center; padding: 3px 10px; flex: none; }
  .toast {
    position: absolute; left: 50%; bottom: 10px; transform: translateX(-50%);
    padding: 5px 14px; border-radius: 14px; background: var(--fg); color: var(--bg); font-size: 0.92em;
    pointer-events: none;
  }
</style>
