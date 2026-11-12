import "./app.css";
import { mount } from "svelte";
import SettingsApp from "./settings/SettingsApp.svelte";
import { loadSettings, settings } from "./lib/settings.svelte";
import { applyTheme } from "./lib/theme";

await loadSettings();
// 설정 창은 투명도 없이 테마 색만 따른다.
$effect.root(() => {
  $effect(() => applyTheme({ ...settings, opacity: 1 }));
});
mount(SettingsApp, { target: document.getElementById("app")! });
