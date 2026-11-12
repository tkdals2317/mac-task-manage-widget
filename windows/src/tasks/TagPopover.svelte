<script lang="ts">
  import { store, toggleTag } from "../lib/todos.svelte";
  import { allTags, safeHex } from "../lib/tags";
  import { native } from "../lib/native";
  import Icon from "./Icon.svelte";
  import Popover from "./Popover.svelte";
  import type { Todo } from "./model";

  let { todo, anchor, onclose }: { todo: Todo; anchor: HTMLElement; onclose: () => void } = $props();
</script>

<Popover {anchor} {onclose}>
  <div class="tags">
    {#each store.tagConfig.groups as group (group.id)}
      <div class="gname">{group.selection === "single" ? `${group.name} · 하나만` : group.name}</div>
      {#each group.tags as tag (tag.id)}
        <button class="tag" onclick={() => toggleTag(todo.id, tag.id)}>
          <span class="dot" style="background:{safeHex(tag.colorHex)}"></span>
          <span>{tag.name}</span>
          <span class="grow"></span>
          {#if todo.tagIds.includes(tag.id)}<Icon name="check" size={0.85} />{/if}
        </button>
      {/each}
    {/each}
    {#if allTags(store.tagConfig).length === 0}<div class="faint empty">태그 없음</div>{/if}
    <div class="sep"></div>
    <button class="manage" onclick={() => { native.openSettings("tags"); onclose(); }}>태그 관리…</button>
  </div>
</Popover>

<style>
  .tags { display: flex; flex-direction: column; gap: 2px; min-width: 150px; }
  .gname { font-size: 0.88em; font-weight: 600; color: var(--fg2); padding-top: 4px; }
  .tag { display: flex; align-items: center; gap: 8px; padding: 3px 0; border: none; background: transparent; cursor: pointer; text-align: left; }
  .dot { width: 8px; height: 8px; border-radius: 50%; flex: none; }
  .grow { flex: 1; min-width: 12px; }
  .empty { font-size: 0.92em; }
  .sep { height: 1px; background: var(--line); margin: 4px 0 2px; }
  .manage { border: none; background: transparent; color: var(--fg2); font-size: 0.92em; cursor: pointer; text-align: left; padding: 0; }
  .manage:hover { color: var(--fg); }
</style>
