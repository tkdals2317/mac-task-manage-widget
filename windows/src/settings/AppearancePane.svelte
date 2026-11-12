<script lang="ts">
  import { setSetting, settings } from "../lib/settings.svelte";
  import { ACCENTS, CUSTOM_ID, DARK_BACKGROUNDS, LIGHT_BACKGROUNDS, lowContrast, PRESETS, resolveTheme } from "../lib/theme";
  import Segmented from "./Segmented.svelte";

  let showCustom = $state(settings.themePreset === CUSTOM_ID);
  const isCustom = $derived(settings.themePreset === CUSTOM_ID);
  const warn = $derived(isCustom && lowContrast({ background: settings.customBackground, accent: settings.customAccent }));

  /** 스와치를 고르면 "직접 조합"으로 전환. 처음 전환할 때는 지금 보이던 색에서 시작한다. */
  function pickCustom(p: { background?: string; accent?: string }) {
    if (!isCustom) {
      const cur = resolveTheme(settings.themePreset, settings.customBackground, settings.customAccent);
      if (cur) { setSetting("customBackground", cur.background); setSetting("customAccent", cur.accent); }
    }
    if (p.background) setSetting("customBackground", p.background);
    if (p.accent) setSetting("customAccent", p.accent);
    setSetting("themePreset", CUSTOM_ID);
  }
</script>

<div class="pane">
  <h2>외관</h2>
  <div class="card">
    <div class="srow">
      <span>투명도</span>
      <div class="range">
        <input type="range" min="0.6" max="1" step="0.05" value={settings.opacity} aria-label="투명도"
          oninput={(e) => setSetting("opacity", Number(e.currentTarget.value))} />
        <span class="val">{Math.round(settings.opacity * 100)}%</span>
      </div>
    </div>
    <label class="srow">
      <span>마우스 올리면 불투명</span>
      <input class="switch" type="checkbox" checked={settings.hoverOpaque} onchange={(e) => setSetting("hoverOpaque", e.currentTarget.checked)} />
    </label>
  </div>

  <div class="card">
    <div class="srow">
      <span>테마</span>
      <Segmented value={settings.theme} disabled={settings.themePreset !== "default"} onpick={(v) => setSetting("theme", v)}
        options={[{ value: "system", label: "시스템" }, { value: "light", label: "라이트" }, { value: "dark", label: "다크" }]} />
    </div>
    {#if settings.themePreset !== "default"}
      <div class="hint" style="padding-bottom:10px">테마 색을 쓰면 밝기는 배경에 맞춰 자동</div>
    {/if}
    <div class="srow">
      <span>글자 크기</span>
      <Segmented value={settings.fontScale} onpick={(v) => setSetting("fontScale", v)}
        options={[{ value: 0.9, label: "작게" }, { value: 1, label: "보통" }, { value: 1.15, label: "크게" }]} />
    </div>
  </div>

  <div class="card-title">테마 색</div>
  <div class="card">
    <div class="presets">
      {#each PRESETS as p (p.id)}
        <button class="thumb" class:on={settings.themePreset === p.id} onclick={() => setSetting("themePreset", p.id)}>
          <span class="box" style:background={p.colors?.background ?? "linear-gradient(90deg,#F5F5F5 50%,#2E2E2E 50%)"}>
            {#if p.colors}
              <span class="bar" style:background={p.colors.accent} style="top:12px;width:18px"></span>
              <span class="bar" style="top:21px;width:30px;background:rgba(128,128,128,.6);height:3px"></span>
            {/if}
          </span>
          <span class="hint">{p.name}</span>
        </button>
      {/each}
    </div>
    <button class="srow" style="width:100%;background:none;border:none;border-top:1px solid var(--line);cursor:pointer;text-align:left" onclick={() => (showCustom = !showCustom)}>
      <span>{showCustom ? "▾" : "▸"} 직접 조합</span>
    </button>
    {#if showCustom}
      <div class="srow col">
        <span class="hint">배경</span>
        {#each [LIGHT_BACKGROUNDS, DARK_BACKGROUNDS] as list}
          <div class="swatches">
            {#each list as hex (hex)}
              <button class="sw" class:on={isCustom && settings.customBackground === hex} style:background={hex} aria-label={`배경 ${hex}`} onclick={() => pickCustom({ background: hex })}></button>
            {/each}
          </div>
        {/each}
        <span class="hint" style="margin-top:4px">강조색</span>
        <div class="swatches">
          {#each ACCENTS as hex (hex)}
            <button class="sw round" class:on={isCustom && settings.customAccent === hex} style:background={hex} aria-label={`강조색 ${hex}`} onclick={() => pickCustom({ accent: hex })}></button>
          {/each}
        </div>
        {#if warn}<div class="hint warn">강조색이 배경과 비슷해 잘 안 보일 수 있어요</div>{/if}
      </div>
    {/if}
  </div>
</div>
