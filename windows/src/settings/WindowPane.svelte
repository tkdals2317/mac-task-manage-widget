<script lang="ts">
  import { setSetting, settings } from "../lib/settings.svelte";
  import Segmented from "./Segmented.svelte";
  import HotKeyRecorder from "./HotKeyRecorder.svelte";
</script>

<div class="pane">
  <h2>창</h2>
  <div class="card">
    <label class="srow">
      <span>항상 위</span>
      <input class="switch" type="checkbox" checked={settings.alwaysOnTop} onchange={(e) => setSetting("alwaysOnTop", e.currentTarget.checked)} />
    </label>
    <div class="srow">
      <span>투명도</span>
      <div class="range">
        <input type="range" min="0.6" max="1" step="0.05" value={settings.opacity} aria-label="투명도"
          oninput={(e) => setSetting("opacity", Number(e.currentTarget.value))} />
        <span class="val">{Math.round(settings.opacity * 100)}%</span>
      </div>
    </div>
    <label class="srow">
      <span class="grow">마우스 올리면 불투명</span>
      <input class="switch" type="checkbox" checked={settings.hoverOpaque} onchange={(e) => setSetting("hoverOpaque", e.currentTarget.checked)} />
    </label>
    <div class="srow">
      <span>글자 크기</span>
      <Segmented value={settings.fontScale} onpick={(v) => setSetting("fontScale", v)}
        options={[{ value: 0.9, label: "작게" }, { value: 1, label: "보통" }, { value: 1.15, label: "크게" }]} />
    </div>
    <label class="srow">
      <span>Windows 시작 시 자동 실행</span>
      <input class="switch" type="checkbox" checked={settings.launchAtLogin} onchange={(e) => setSetting("launchAtLogin", e.currentTarget.checked)} />
    </label>
  </div>
  <div class="card">
    <label class="srow">
      <span>전역 단축키로 패널 열기/닫기</span>
      <input class="switch" type="checkbox" checked={settings.globalHotKeyEnabled} onchange={(e) => setSetting("globalHotKeyEnabled", e.currentTarget.checked)} />
    </label>
    {#if settings.globalHotKeyEnabled}
      <div class="srow col">
        <HotKeyRecorder />
        <div class="hint">Ctrl·Alt·Win 중 하나를 함께 눌러야 해요.</div>
      </div>
    {/if}
  </div>
</div>
