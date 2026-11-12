import "./app.css";
import { mount } from "svelte";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { register, unregisterAll } from "@tauri-apps/plugin-global-shortcut";
import { enable, disable, isEnabled } from "@tauri-apps/plugin-autostart";
import App from "./App.svelte";
import { loadSettings, settings } from "./lib/settings.svelte";
import { applyTheme } from "./lib/theme";
import { log, native } from "./lib/native";

await loadSettings();
const win = getCurrentWindow();

// 설정이 바뀔 때마다 테마·항상 위·단축키·자동 실행을 다시 맞춘다.
$effect.root(() => {
  $effect(() => applyTheme(settings));
  $effect(() => {
    win.setAlwaysOnTop(settings.alwaysOnTop).catch(() => {});
  });
  $effect(() => {
    const on = settings.globalHotKeyEnabled;
    const key = settings.globalHotKey;
    unregisterAll()
      .then(() => (on && key ? register(key, (e) => e.state === "Pressed" && native.togglePanel()) : undefined))
      .catch((e) => log(`단축키 등록 실패 ${key}: ${e}`));
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
