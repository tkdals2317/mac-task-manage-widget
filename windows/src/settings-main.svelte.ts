import "./app.css";
import { mount, tick } from "svelte";
import { getCurrentWindow } from "@tauri-apps/api/window";
import SettingsApp from "./settings/SettingsApp.svelte";
import { loadSettings, settings } from "./lib/settings.svelte";
import { applyTheme } from "./lib/theme";
import { native } from "./lib/native";

await loadSettings();
// 설정 창은 투명도 없이 테마 색만 따른다.
$effect.root(() => {
  $effect(() => {
    applyTheme({ ...settings, opacity: 1 });
    // Windows 제목 표시줄도 테마 밝기에 맞춘다 (어두운 테마인데 흰 제목줄이 남지 않게)
    const dark = document.documentElement.style.getPropertyValue("--dark") === "1";
    getCurrentWindow().setTheme(dark ? "dark" : "light").catch(() => {});
  });
});
window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => applyTheme({ ...settings, opacity: 1 }));
mount(SettingsApp, { target: document.getElementById("app")! });
// 다 그린 뒤에 창을 보인다 (흰 화면이 먼저 번쩍이지 않게)
await tick();
requestAnimationFrame(() => native.settingsReady().catch(() => {}));
