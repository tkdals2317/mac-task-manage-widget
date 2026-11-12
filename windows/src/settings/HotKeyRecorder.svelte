<script lang="ts">
  // 전역 단축키 녹화 버튼 + 기본값 복원 (Mac HotKeyRecorder).
  import { DEFAULTS, setSetting, settings } from "../lib/settings.svelte";
  import { displayAccelerator, recordKey } from "../lib/hotkey";

  let recording = $state(false);
  let message = $state("");

  function onKey(e: KeyboardEvent) {
    e.preventDefault();
    e.stopPropagation();
    const r = recordKey(e);
    if (!r) return;
    if ("cancel" in r) return stop();
    if ("error" in r) { message = r.error; return; }
    message = "";
    setSetting("globalHotKey", r.accel);
    stop();
  }
  function start() {
    message = "";
    recording = true;
    window.addEventListener("keydown", onKey, true);
  }
  function stop() {
    window.removeEventListener("keydown", onKey, true);
    recording = false;
  }
  $effect(() => () => window.removeEventListener("keydown", onKey, true));
</script>

<div class="actions">
  <button class="btn keybtn" class:rec={recording} onclick={() => (recording ? stop() : start())} onblur={stop} onkeyup={(e) => e.preventDefault()}>
    {recording ? "키를 누르세요… (Esc 취소)" : displayAccelerator(settings.globalHotKey)}
  </button>
  {#if settings.globalHotKey !== DEFAULTS.globalHotKey && !recording}
    <button class="btn" onclick={() => setSetting("globalHotKey", DEFAULTS.globalHotKey)}>기본값</button>
  {/if}
</div>
{#if message}<div class="hint err">{message}</div>{/if}
