<script lang="ts">
  import { badge } from "../lib/due";
  import { deleteSubtask, renameSubtask, setSubtaskDue, toggleSubtask } from "../lib/todos.svelte";
  import DuePopover from "./DuePopover.svelte";
  import Icon from "./Icon.svelte";
  import { focusOnMount, truncTitle } from "./truncTitle";
  import type { Subtask, Todo } from "./model";

  let { todo, sub }: { todo: Todo; sub: Subtask } = $props();
  let editing = $state(false);
  let draft = $state("");
  let showDue = $state(false);
  let dueBtn: HTMLElement | undefined = $state();
  const b = $derived(badge(sub.dueDate, new Date()));

  function commit() {
    if (!editing) return;
    editing = false;
    renameSubtask(todo.id, sub.id, draft);
  }
</script>

<div class="sub">
  <button class="icon check" class:on={sub.done} aria-label={sub.done ? "미완료로" : "완료"} onclick={() => toggleSubtask(todo.id, sub.id)}>
    <Icon name={sub.done ? "circle-check" : "circle"} size={1} />
  </button>

  {#if editing}
    <input class="edit" bind:value={draft} use:focusOnMount={true} onblur={commit}
      onkeydown={(e) => { if (e.key === "Enter") commit(); else if (e.key === "Escape") { e.stopPropagation(); editing = false; } }} />
  {:else}
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <span class="title" class:done={sub.done} use:truncTitle={{ full: sub.title, hint: "더블클릭하면 수정" }}
      ondblclick={() => { draft = sub.title; editing = true; }}>{sub.title}</span>
  {/if}

  <button bind:this={dueBtn} class="due-btn" class:empty={b.style === "none"} class:open={showDue} aria-label="마감일" onclick={() => (showDue = !showDue)}>
    {#if b.style === "none"}
      <Icon name="calendar" size={0.9} />
    {:else}
      <span class="badge {b.style}">{b.text}</span>
    {/if}
  </button>
  {#if showDue && dueBtn}
    <DuePopover due={sub.dueDate} anchor={dueBtn} onpick={(k) => setSubtaskDue(todo.id, sub.id, k)} onclose={() => (showDue = false)} />
  {/if}

  <button class="icon del" aria-label="삭제" onclick={() => deleteSubtask(todo.id, sub.id)}><Icon name="x" size={0.75} /></button>
</div>

<style>
  .sub { display: flex; align-items: center; gap: 6px; padding: 2px 0; }
  .icon { border: none; background: transparent; padding: 0; cursor: pointer; display: inline-flex; color: var(--fg2); }
  .check.on { color: var(--accent); }
  .title { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .title.done { text-decoration: line-through; color: var(--fg2); }
  .edit { flex: 1; min-width: 0; border: none; outline: none; background: transparent; user-select: text; }
  .due-btn { border: none; background: transparent; padding: 0; cursor: pointer; color: var(--fg3); display: inline-flex; }
  .due-btn.empty { opacity: 0; }
  .sub:hover .due-btn.empty, .due-btn.open { opacity: 1; }
  .badge { font-size: 0.85em; font-weight: 500; padding: 1px 5px; border-radius: 5px; font-variant-numeric: tabular-nums; }
  .badge.overdue { color: var(--danger); background: var(--danger-soft); }
  .badge.today { color: var(--warn); background: var(--warn-soft); }
  .badge.normal { color: var(--fg2); background: var(--fill2); }
  .del { opacity: 0; }
  .sub:hover .del { opacity: 1; }
</style>
