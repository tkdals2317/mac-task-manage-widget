import "./app.css";
import { mount, tick } from "svelte";
import SettingsApp from "./settings/SettingsApp.svelte";
import { loadSettings, settings } from "./lib/settings.svelte";
import { applyTheme } from "./lib/theme";
import { native } from "./lib/native";

await loadSettings();
// 설정 창은 투명도 없이 테마 색만 따른다.
$effect.root(() => {
  $effect(() => applyTheme({ ...settings, opacity: 1 }));
});
window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => applyTheme({ ...settings, opacity: 1 }));
mount(SettingsApp, { target: document.getElementById("app")! });
// 다 그린 뒤에 창을 보인다 (흰 화면이 먼저 번쩍이지 않게)
await tick();
requestAnimationFrame(() => native.settingsReady().catch(() => {}));
