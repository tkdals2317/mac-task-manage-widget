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
    isEnabled()
      .then((cur) => (cur === want ? undefined : want ? enable() : disable()))
      .catch(() => {});
  });
});
window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => applyTheme(settings));

mount(App, { target: document.getElementById("app")! });

// 처음 실행이면 설정 창을 열어 Jira 연결부터 안내한다.
if (!settings.onboardingDone) native.openSettings("jira");
