<script lang="ts">
  import { untrack } from "svelte";
  import { badge } from "../lib/due";
  import { orderedTags } from "../lib/tags";
  import {
    addSubtask, expanded, remove, rename, setDue, setMemo, store, toggle, toggleExpanded, toggleTag,
  } from "../lib/todos.svelte";
  import DuePopover from "./DuePopover.svelte";
  import Icon from "./Icon.svelte";
  import Menu, { type MenuItem } from "./Menu.svelte";
  import SubtaskRow from "./SubtaskRow.svelte";
  import TagCapsule from "./TagCapsule.svelte";
  import TagPopover from "./TagPopover.svelte";
  import { focusOnMount, truncTitle } from "./truncTitle";
  import { memoPreview, subtaskProgress, type Todo } from "./model";

  let { todo }: { todo: Todo } = $props();

  let editing = $state(false);
  let draft = $state("");
  let showDue = $state(false);
  let showTags = $state(false);
  let menu = $state<{ x: number; y: number } | null>(null);
  let dueBtn: HTMLElement | undefined = $state();
  let tagBtn: HTMLElement | undefined = $state();
  let memoOpen = $state(false);
  let memoDraft = $state("");
  let memoTimer: ReturnType<typeof setTimeout> | undefined;
  let addingSub = $state(false);
  let subDraft = $state("");

  const isOpen = $derived(expanded.has(todo.id));
  const b = $derived(badge(todo.dueDate, new Date()));
  const shown = $derived(orderedTags(store.tagConfig, todo.tagIds));
  const progress = $derived(subtaskProgress(todo));
  const meta = $derived(memoPreview(todo));

  // ---- 펼치기 ----
  function toggleOpen() {
    if (isOpen) { if (memoOpen) closeMemo(); addingSub = false; subDraft = ""; }
    toggleExpanded(todo.id);
  }
  function ensureOpen() { if (!isOpen) toggleExpanded(todo.id); }

  // ---- 제목 수정 ----
  function beginEdit() { draft = todo.title; editing = true; }
  function commitEdit() { if (!editing) return; editing = false; rename(todo.id, draft); }

  // ---- 메모 (0.5초 뒤 저장, 닫거나 사라질 때 즉시 저장) ----
  function openMemo() { ensureOpen(); if (!memoOpen) { memoDraft = todo.memo; memoOpen = true; } }
  function flushMemo() {
    clearTimeout(memoTimer);
    memoTimer = undefined;
    if (memoOpen) setMemo(todo.id, memoDraft);
  }
  function closeMemo() { flushMemo(); memoOpen = false; }
  function onMemoInput() {
    clearTimeout(memoTimer);
    memoTimer = setTimeout(() => setMemo(todo.id, memoDraft), 500);
  }
  $effect(() => () => untrack(flushMemo));

  // ---- 하위 할 일 ----
  function openSubAdd() { ensureOpen(); addingSub = true; }
  /** Enter: 추가하고 다음 입력을 위해 열어 둔다. 빈 입력이면 닫는다. */
  function submitSub() {
    if (!subDraft.trim()) { addingSub = false; subDraft = ""; return; }
    addSubtask(todo.id, subDraft);
    subDraft = "";
  }

  const menuItems = $derived<MenuItem[]>([
    { label: isOpen ? "접기" : "펼치기", onselect: toggleOpen },
    { label: "메모 편집", onselect: openMemo },
    { label: "하위 할 일 추가", onselect: openSubAdd },
    ...store.tagConfig.groups.flatMap((g): MenuItem[] => [
      { separator: true },
      { header: true, label: g.name },
      ...g.tags.map((t): MenuItem => ({ label: t.name, checked: todo.tagIds.includes(t.id), onselect: () => toggleTag(todo.id, t.id) })),
    ]),
  ]);
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="todo" class:done={todo.done} oncontextmenu={(e) => { e.preventDefault(); menu = { x: e.clientX, y: e.clientY }; }}>
  <div class="head">
    <button class="icon chev" aria-label={isOpen ? "접기" : "펼치기"} title={isOpen ? "접기" : "펼쳐서 메모·하위 할 일 보기"} onclick={toggleOpen}>
      <Icon name={isOpen ? "chevron-down" : "chevron-right"} size={0.8} />
    </button>
    <button class="icon box" class:on={todo.done} aria-label={todo.done ? "미완료로" : "완료"} onclick={() => toggle(todo.id)}>
      <Icon name={todo.done ? "square-check" : "square"} size={1.1} />
    </button>

    <div class="main">
      {#if editing}
        <input class="edit" bind:value={draft} use:focusOnMount={true} onblur={commitEdit}
          onkeydown={(e) => { if (e.key === "Enter") commitEdit(); else if (e.key === "Escape") { e.stopPropagation(); editing = false; } }} />
      {:else}
        <span class="title" use:truncTitle={{ full: todo.title, hint: "더블클릭하면 수정" }} ondblclick={beginEdit}>{todo.title}</span>
      {/if}
      {#if !isOpen && meta}
        <span class="meta" role="presentation" onclick={toggleOpen}>{meta}</span>
      {/if}
    </div>

    {#if progress.total > 0}
      <button class="pill" class:complete={progress.done === progress.total} title="하위 할 일 {progress.done}/{progress.total}" onclick={toggleOpen}>
        <Icon name={progress.done === progress.total ? "check" : "list"} size={0.85} />{progress.done}/{progress.total}
      </button>
    {/if}

    <button bind:this={tagBtn} class="tags" class:has={shown.length > 0} class:open={showTags} aria-label="태그" onclick={() => (showTags = !showTags)}>
      {#if shown.length === 0}
        <span class="faint addtag">＋태그</span>
      {:else}
        {#each shown.slice(0, 2) as t (t.id)}<TagCapsule tag={t} />{/each}
        {#if shown.length > 2}<span class="muted more">+{shown.length - 2}</span>{/if}
      {/if}
    </button>

    <button bind:this={dueBtn} class="due-btn" aria-label="마감일" onclick={() => (showDue = !showDue)}>
      {#if b.style === "none"}
        <span class="faint"><Icon name="calendar" size={0.95} /></span>
      {:else}
        <span class="badge {b.style}">{b.text}</span>
      {/if}
    </button>

    <button class="icon del" aria-label="삭제" onclick={() => remove(todo.id)}><Icon name="x" size={0.8} /></button>
  </div>

  {#if isOpen}
    <div class="body">
      <div class="label">메모</div>
      {#if memoOpen}
        <textarea class="memo" bind:value={memoDraft} oninput={onMemoInput} use:focusOnMount placeholder="메모 (여러 줄, - 목록·링크 가능)"
          onblur={closeMemo} onkeydown={(e) => { if (e.key === "Escape") { e.stopPropagation(); closeMemo(); } }}></textarea>
      {:else if todo.memo === ""}
        <button class="add" onclick={openMemo}>＋ 메모 추가</button>
      {:else}
        <div class="memo-text" role="presentation" onclick={openMemo}>{todo.memo}</div>
      {/if}

      <div class="label sub-label">{progress.total > 0 ? `하위 할 일 ${progress.done}/${progress.total}` : "하위 할 일"}</div>
      {#each todo.subtasks as s (s.id)}<SubtaskRow {todo} sub={s} />{/each}
      {#if addingSub}
        <input class="field subadd" placeholder="하위 할 일" bind:value={subDraft} use:focusOnMount
          onkeydown={(e) => { if (e.key === "Enter") submitSub(); else if (e.key === "Escape") { e.stopPropagation(); addingSub = false; subDraft = ""; } }} />
      {:else}
        <button class="add" onclick={openSubAdd}>＋ 하위 할 일 추가</button>
      {/if}
    </div>
  {/if}
</div>

{#if showDue && dueBtn}
  <DuePopover due={todo.dueDate} anchor={dueBtn} onpick={(k) => setDue(todo.id, k)} onclose={() => (showDue = false)} />
{/if}
{#if showTags && tagBtn}
  <TagPopover {todo} anchor={tagBtn} onclose={() => (showTags = false)} />
{/if}
{#if menu}
  <Menu items={menuItems} anchor={menu} onclose={() => (menu = null)} />
{/if}

<style>
  .todo { border-bottom: 1px solid var(--line); padding: 0; }
  .head { display: flex; align-items: flex-start; gap: 8px; padding: 5px 0; }
  .icon { border: none; background: transparent; padding: 0; cursor: pointer; display: inline-flex; align-items: center; justify-content: center; color: var(--fg2); height: 1.4em; }
  .chev { width: 1em; }
  .box { width: 1.2em; }
  .box.on { color: var(--accent); }
  .main { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
  .title { font-size: 1.04em; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; line-height: 1.4; }
  .done .title { text-decoration: line-through; color: var(--fg2); }
  .edit { font-size: 1.04em; border: none; outline: none; background: transparent; width: 100%; padding: 0; user-select: text; line-height: 1.4; }
  .meta { font-size: 0.9em; color: var(--fg2); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; cursor: pointer; }
  .done .meta, .done .tags, .done .pill { opacity: 0.5; }
  .pill {
    display: inline-flex; align-items: center; gap: 2px; border: none; cursor: pointer; font-size: 0.88em; font-weight: 500;
    padding: 1.5px 6px; border-radius: 999px; color: var(--accent); background: var(--accent-soft); font-variant-numeric: tabular-nums; flex: none;
  }
  .pill.complete { background: var(--accent); color: #fff; }
  .tags { display: inline-flex; align-items: center; gap: 3px; border: none; background: transparent; padding: 0; cursor: pointer; flex: none; }
  .tags:not(.has):not(.open) { display: none; }
  .head:hover .tags { display: inline-flex; }
  .addtag { font-size: 0.92em; }
  .more { font-size: 0.92em; }
  .due-btn { border: none; background: transparent; padding: 0; cursor: pointer; display: inline-flex; align-items: center; height: 1.4em; flex: none; }
  .badge { font-size: 0.88em; font-weight: 500; padding: 2px 6px; border-radius: 5px; font-variant-numeric: tabular-nums; }
  .badge.overdue { color: var(--danger); background: var(--danger-soft); }
  .badge.today { color: var(--warn); background: var(--warn-soft); }
  .badge.normal { color: var(--fg2); background: var(--fill2); }
  .done .badge { opacity: 0.6; }
  .del { opacity: 0; flex: none; }
  .head:hover .del { opacity: 1; }
  .body { padding: 0 0 6px calc(2.3em + 16px); display: flex; flex-direction: column; gap: 3px; }
  .done .body { opacity: 0.6; }
  .label { font-size: 0.88em; font-weight: 600; color: var(--fg2); }
  .sub-label { margin-top: 5px; }
  .add { border: none; background: transparent; padding: 0; text-align: left; cursor: pointer; color: var(--fg3); }
  .add:hover { color: var(--fg2); }
  .memo-text { white-space: pre-wrap; color: var(--fg2); cursor: text; overflow-wrap: anywhere; }
  .memo {
    field-sizing: content; min-height: 3.9em; max-height: 10.4em; resize: none; width: 100%; padding: 4px 6px;
    border-radius: 5px; border: 1px solid transparent; outline: none; background: var(--fill); user-select: text; line-height: 1.3;
  }
  .memo:focus { border-color: var(--accent); }
  .subadd { padding: 3px 6px; }
</style>
