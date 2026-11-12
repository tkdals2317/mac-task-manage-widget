<script lang="ts">
  // 설정 > 태그. 편집할 때마다 tags.json 에 저장한다 (할 일 창이 5초마다 다시 읽고 사라진 태그를 정리).
  import { onMount, tick } from "svelte";
  import { defaultTagConfig, loadTagConfig, saveTagConfig, TAG_COLORS, type TagConfig, type TagGroup, type Tag } from "../lib/tags";
  import { newId, normalizedTitle } from "../tasks/model";
  import { log } from "../lib/native";
  import { setSetting, settings } from "../lib/settings.svelte";

  let cfg = $state<TagConfig>(defaultTagConfig());
  let loaded = $state(false);
  let colorFor = $state<string | null>(null); // 색 고르는 중인 태그 id
  let confirmGroup = $state<string | null>(null);
  let confirmReset = $state(false);
  let focusId = $state<string | null>(null);

  onMount(async () => { cfg = await loadTagConfig(); loaded = true; });

  function save() { saveTagConfig($state.snapshot(cfg)).catch((e) => log(`tags 저장 실패: ${e}`)); }
  const edit = (change: () => void) => { change(); save(); };

  const swap = <T,>(a: T[], i: number, d: number) => {
    const j = i + d;
    if (j >= 0 && j < a.length) [a[i], a[j]] = [a[j], a[i]];
  };

  async function addTag(g: TagGroup) {
    const t: Tag = { id: newId(), name: "새 태그", colorHex: TAG_COLORS.gray };
    edit(() => g.tags.push(t));
    focusId = t.id;
    await tick();
    document.getElementById(`tag-${t.id}`)?.focus();
    (document.getElementById(`tag-${t.id}`) as HTMLInputElement | null)?.select();
  }
  const commitTag = (t: Tag, v: string) => { const n = normalizedTitle(v); if (n && n !== t.name) edit(() => (t.name = n)); };
  const commitGroup = (g: TagGroup, v: string) => { const n = normalizedTitle(v); if (n && n !== g.name) edit(() => (g.name = n)); };
  function deleteGroup(g: TagGroup) {
    edit(() => {
      cfg.groups = cfg.groups.filter((x) => x.id !== g.id);
      if (cfg.sortGroupId === g.id) cfg.sortGroupId = cfg.groups[0]?.id;
    });
    confirmGroup = null;
  }
  function addGroup() {
    edit(() => cfg.groups.push({ id: newId(), name: "새 그룹", selection: "multiple", tags: [] }));
  }
  function reset() { cfg = defaultTagConfig(); save(); confirmReset = false; }
</script>

<div class="pane">
  <h2>태그</h2>
  {#if loaded}
    {#each cfg.groups as g, gi (g.id)}
      <div class="card">
        <div class="group-head">
          <input class="field selectable" style="width:140px" aria-label="그룹 이름" value={g.name}
            onchange={(e) => { commitGroup(g, e.currentTarget.value); e.currentTarget.value = g.name; }} />
          <div class="seg">
            <button class:on={g.selection === "single"} onclick={() => edit(() => (g.selection = "single"))}>하나만</button>
            <button class:on={g.selection === "multiple"} onclick={() => edit(() => (g.selection = "multiple"))}>여러 개</button>
          </div>
          <button class="radio-btn" class:on={cfg.sortGroupId === g.id} onclick={() => edit(() => (cfg.sortGroupId = g.id))}>
            {cfg.sortGroupId === g.id ? "◉" : "○"} 정렬 기준
          </button>
          <span style="flex:1"></span>
          <button class="icon-btn" title="위로 이동" disabled={gi === 0} onclick={() => edit(() => swap(cfg.groups, gi, -1))}>↑</button>
          <button class="icon-btn" title="아래로 이동" disabled={gi === cfg.groups.length - 1} onclick={() => edit(() => swap(cfg.groups, gi, 1))}>↓</button>
          {#if confirmGroup === g.id}
            <button class="btn danger" onclick={() => deleteGroup(g)}>삭제</button>
            <button class="btn" onclick={() => (confirmGroup = null)}>취소</button>
          {:else}
            <button class="icon-btn" title="그룹 삭제" onclick={() => (confirmGroup = g.id)}>🗑</button>
          {/if}
        </div>
        {#if confirmGroup === g.id}
          <div class="hint warn">"{g.name}" 그룹을 삭제할까요? 그룹과 태그 {g.tags.length}개가 삭제되고 할 일에서 빠집니다.</div>
        {/if}
        {#each g.tags as t, ti (t.id)}
          <div class="tag-row">
            <div class="pop-wrap">
              <button class="dot-btn" style:background={t.colorHex} aria-label="색 바꾸기" onclick={() => (colorFor = colorFor === t.id ? null : t.id)}></button>
              {#if colorFor === t.id}
                <div class="popover">
                  {#each Object.values(TAG_COLORS) as hex (hex)}
                    <button class="sw round" class:on={t.colorHex.toUpperCase() === hex} style:background={hex} aria-label={hex}
                      onclick={() => { edit(() => (t.colorHex = hex)); colorFor = null; }}></button>
                  {/each}
                  <input type="color" aria-label="직접 고르기" value={t.colorHex}
                    onchange={(e) => { edit(() => (t.colorHex = e.currentTarget.value.toUpperCase())); colorFor = null; }} />
                </div>
              {/if}
            </div>
            <input id={`tag-${t.id}`} class="field selectable" style="flex:1;width:auto" aria-label="태그 이름" value={t.name}
              onchange={(e) => { commitTag(t, e.currentTarget.value); e.currentTarget.value = t.name; }} />
            <button class="icon-btn" title="위로" disabled={ti === 0} onclick={() => edit(() => swap(g.tags, ti, -1))}>↑</button>
            <button class="icon-btn" title="아래로" disabled={ti === g.tags.length - 1} onclick={() => edit(() => swap(g.tags, ti, 1))}>↓</button>
            <button class="icon-btn" title="삭제" onclick={() => edit(() => (g.tags = g.tags.filter((x) => x.id !== t.id)))}>🗑</button>
          </div>
        {/each}
        <div class="srow"><button class="btn" onclick={() => addTag(g)}>＋ 태그</button></div>
      </div>
    {/each}

    <div class="card">
      <div class="srow"><button class="btn" onclick={addGroup}>＋ 그룹 추가</button></div>
      <label class="srow">
        <span>태그 순서로 정렬</span>
        <input class="switch" type="checkbox" checked={settings.sortTodosByTag} onchange={(e) => setSetting("sortTodosByTag", e.currentTarget.checked)} />
      </label>
      <div class="srow col">
        {#if confirmReset}
          <div class="hint warn">태그를 기본값으로 되돌릴까요? 그룹과 태그가 초기화되고, 사라진 태그는 할 일에서 제거됩니다.</div>
          <div class="actions">
            <button class="btn danger" onclick={reset}>되돌리기</button>
            <button class="btn" onclick={() => (confirmReset = false)}>취소</button>
          </div>
        {:else}
          <div class="actions"><button class="btn" onclick={() => (confirmReset = true)}>기본값으로 되돌리기</button></div>
        {/if}
      </div>
    </div>
    <div class="hint">↑↓ 로 그룹 안에서 순서를 바꿉니다. '정렬 기준' 그룹의 위쪽 태그가 먼저 정렬됩니다.</div>
  {/if}
</div>
