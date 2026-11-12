import "./app.css";
import { mount } from "svelte";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { register, unregisterAll } from "@tauri-apps/plugin-global-shortcut";
import { enable, disable, isEnabled } from "@tauri-apps/plugin-autostart";
import App from "./App.svelte";
import { loadSettings, settings } from "./lib/settings.svelte";
import { applyTheme } from "./lib/theme";
import { log, native } from "./lib/native";
import { setHotkeyError } from "./lib/hotkeyStatus.svelte";
import { displayAccelerator } from "./lib/hotkey";
import { listen } from "@tauri-apps/api/event";
import { enabledTabs } from "./lib/settings.svelte";
import { startSummaryScheduler } from "./lib/summary.svelte";
import { refreshPR, resetBitbucketCache, startPRLoop } from "./lib/pr.svelte";
import { locateTsh, reloadConfig, refreshStatus as refreshTeleportStatus, startTeleport, tp } from "./lib/teleport.svelte";
import { startTasks, store } from "./lib/todos.svelte";
import { dayKey } from "./lib/summaryCore";

await loadSettings();
const win = getCurrentWindow();
let hovering = $state(false);
document.documentElement.addEventListener("mouseenter", () => (hovering = true));
document.documentElement.addEventListener("mouseleave", () => (hovering = false));

// 설정이 바뀔 때마다 테마·항상 위·단축키·자동 실행을 다시 맞춘다.
$effect.root(() => {
  // 마우스를 올리면 불투명 (hoverOpaque, Mac 과 같음)
  $effect(() => applyTheme(hovering && settings.hoverOpaque ? { ...settings, opacity: 1 } : settings));
  $effect(() => {
    win.setAlwaysOnTop(settings.alwaysOnTop).catch(() => {});
  });
  $effect(() => {
    const on = settings.globalHotKeyEnabled;
    const key = settings.globalHotKey;
    unregisterAll()
      .then(async () => {
        if (!on || !key) return setHotkeyError("");
        await register(key, (e) => e.state === "Pressed" && native.togglePanel());
        setHotkeyError("");
      })
      .catch((e) => {
        // 대부분 다른 앱이 이미 쓰는 조합 (예: Claude 데스크톱의 Ctrl+Alt+Space)
        log(`단축키 등록 실패 ${key}: ${e}`);
        setHotkeyError(`${displayAccelerator(key)} 를 다른 앱이 쓰고 있어요`);
      });
  });
  $effect(() => {
    const want = settings.launchAtLogin;
    // 개발 빌드(`tauri dev`)는 임시 빌드 폴더의 exe 라서 등록하면 안 된다.
    // 같은 "ATM" 이름이라 설치한 앱의 자동 실행 항목까지 덮어쓴다.
    if (import.meta.env.DEV) return;
    isEnabled()
      .then((cur) => (cur === want ? undefined : want ? enable() : disable()))
      .catch(() => {});
  });
});
window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => applyTheme(settings));

mount(App, { target: document.getElementById("app")! });

// ---- 백그라운드 일: 요약 자동 생성, PR 새로고침·알림, Teleport 자동 유지 ----
// 패널 창은 숨겨도 살아 있으므로 여기서 돌린다 (Mac AppDelegate 의 Scheduler·PRModel.startLoop·TeleportManager.start).
const ALL_TABS = ["tasks", "summary", "notes", "pr", "teleport"];
let panelVisible = true;
const checkVisible = () => win.isVisible().then((v) => (panelVisible = v)).catch(() => {});
setInterval(checkVisible, 10_000);
listen("panel-hidden", () => (panelVisible = false)).catch(() => {});
win.onFocusChanged(({ payload }) => { if (payload) panelVisible = true; }).catch(() => {});

startTasks();
startSummaryScheduler();
startPRLoop(() => panelVisible);
startTeleport(() => enabledTabs(settings.enabledTabs, ALL_TABS).includes("teleport"));

// 설정 창에서 바꾼 것 반영
listen("pr-config-changed", () => { resetBitbucketCache(); void refreshPR(); }).catch(() => {});
listen("teleport-config-changed", () => { void locateTsh().then(reloadConfig).then(refreshTeleportStatus); }).catch(() => {});
listen("teleport-setup-requested", () => { tp.setupRequested = true; void win.show(); void win.setFocus(); }).catch(() => {});

// 트레이 툴팁에 오늘·지난 마감 할 일 수 (Mac 메뉴바 숫자)
$effect.root(() => {
  $effect(() => {
    if (!store.loaded) return;
    const today = dayKey(new Date());
    const n = store.todos.filter((t) => !t.done).reduce((c, t) =>
      c + (t.dueDate && t.dueDate <= today ? 1 : 0) + t.subtasks.filter((s) => !s.done && s.dueDate && s.dueDate <= today).length, 0);
    native.setTrayTooltip(n ? `ATM · 오늘까지 할 일 ${n}개` : "ATM").catch(() => {});
  });
});

// 처음 실행이면 설정 도우미를 연다.
if (!settings.onboardingDone) native.openSettings("onboarding");
