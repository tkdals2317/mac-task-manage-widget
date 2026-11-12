<script lang="ts">
  import { enabledTabs, setSetting, settings, toggledTabs } from "../lib/settings.svelte";

  const TABS = [{ id: "tasks", title: "할 일" }, { id: "notes", title: "노트" }];
  const ids = TABS.map((t) => t.id);
  const enabled = $derived(enabledTabs(settings.enabledTabs, ids));
</script>

<div class="pane">
  <h2>탭</h2>
  <div class="card">
    {#each TABS as t (t.id)}
      {@const on = enabled.includes(t.id)}
      <label class="srow">
        <span>{t.title}</span>
        <input class="switch" type="checkbox" checked={on} disabled={on && enabled.length === 1}
          onchange={() => setSetting("enabledTabs", toggledTabs(t.id, settings.enabledTabs, ids))} />
      </label>
    {/each}
  </div>
  {#if enabled.length === 1}<div class="hint">최소 1개는 켜져 있어야 합니다</div>{/if}
  <div class="hint">요약·PR·Teleport 는 다음 버전에서 추가돼요</div>
</div>
