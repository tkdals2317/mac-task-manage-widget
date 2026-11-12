<script lang="ts">
  import {
    deleteMemo, hasLock, isReadable, lockMemo, ns, openIfKeyed, previewOf, relockAll, rename, textOf,
    toggleExpanded, togglePin, unlockPermanently,
  } from "../lib/notes.svelte";
  import { isLocked, type Memo } from "./data";
  import { clickOutside } from "./clickOutside";
  import { openMenu } from "./menu.svelte";
  import Icon from "./Icon.svelte";
  import MemoEditor from "./MemoEditor.svelte";
  import LockedPanel from "./LockedPanel.svelte";
  import RelockLabel from "./RelockLabel.svelte";
  import PasswordPopover from "./PasswordPopover.svelte";

  let { memo }: { memo: Memo } = $props();
  let editing = $state(false);
  let draft = $state("");
  let popover = $state<null | "create" | "verify">(null);
  let titleEl: HTMLInputElement | undefined = $state();
  let clickTimer: ReturnType<typeof setTimeout> | undefined;

  const expanded = $derived(!!ns.expanded[memo.id]);
  const locked = $derived(isLocked(memo));
  const readable = $derived(isReadable(memo));
  const icon = $derived(memo.pinned ? "pin" : locked ? "lock" : "note");
  const iconFill = $derived(memo.pinned || locked);
  const iconName = $derived(locked && !memo.pinned && readable ? "lockopen" : icon);
  const lead = $derived(memo.pinned || locked);

  function toggleRow() {
    toggleExpanded(memo.id);
    // 열쇠가 아직 메모리에 있으면 다시 묻지 않고 연다.
    if (ns.expanded[memo.id] && locked) void openIfKeyed(memo.id);
  }
  function titleClick(e: MouseEvent) {
    if (e.detail > 1) return;
    clearTimeout(clickTimer);
    clickTimer = setTimeout(toggleRow, 220);
  }
  function beginEdit() {
    clearTimeout(clickTimer);
    draft = memo.title;
    editing = true;
    queueMicrotask(() => { titleEl?.focus(); titleEl?.select(); });
  }
  function commitEdit() {
    if (!editing) return;
    editing = false;
    rename(memo.id, draft);
  }
  function lockTapped() {
    if (locked) {
      if (readable) relockAll();
      else if (!expanded) toggleRow();
      return;
    }
    if (!hasLock()) popover = "create";
    else if (ns.hasKey) void lockMemo(memo.id);
    else popover = "verify";
  }
  const lockHelp = $derived(locked ? (readable ? "지금 잠그기" : "열기") : "잠그기");
</script>

<div class="memo" oncontextmenu={(e) => openMenu(e, [
  { label: memo.pinned ? "고정 해제" : "고정", onclick: () => togglePin(memo.id) },
  locked ? { label: "잠금 풀기", disabled: !readable, onclick: () => unlockPermanently(memo.id) } : { label: "잠그기", onclick: lockTapped },
  { sep: true },
  { label: "삭제", danger: true, onclick: () => deleteMemo(memo.id) },
])} role="presentation">
  <div class="head" class:pop={popover !== null}>
    <span class="lead" class:on={lead}><Icon name={iconName} fill={iconFill} size=".95em" /></span>

    <div class="mid">
      {#if editing}
        <input class="edit" bind:this={titleEl} bind:value={draft} onblur={commitEdit}
          onkeydown={(e) => { if (e.key === "Enter") commitEdit(); else if (e.key === "Escape") { e.stopPropagation(); editing = false; } }} />
      {:else}
        <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
        <div class="title" title="{memo.title} (더블클릭하면 수정)" onclick={titleClick} ondblclick={beginEdit}>{memo.title}</div>
      {/if}
      {#if !expanded}
        {#if locked}
          <div class="sub">{#if readable}열림 <RelockLabel />{:else}잠김{/if}</div>
        {:else if previewOf(memo)}
          <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
          <div class="sub" onclick={toggleRow}>{previewOf(memo)}</div>
        {/if}
      {/if}
    </div>

    <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
    <div class="fill" onclick={toggleRow}></div>

    <div class="acts">
      <button class="icon-btn mini" title={memo.pinned ? "고정 해제" : "고정"} onclick={() => togglePin(memo.id)}><Icon name={memo.pinned ? "pinoff" : "pin"} size="1em" /></button>
      <span class="anchor" style="position:relative" use:clickOutside={() => (popover = null)}>
        <button class="icon-btn mini" title={lockHelp} onclick={lockTapped}><Icon name={locked ? "lockopen" : "lock"} size="1em" /></button>
        {#if popover}<PasswordPopover mode={popover} memoId={memo.id} done={() => (popover = null)} />{/if}
      </span>
      <button class="icon-btn mini" title="삭제" onclick={() => deleteMemo(memo.id)}><Icon name="x" size="1em" bold /></button>
    </div>
  </div>

  {#if expanded}
    <div class="body">
      {#if readable}
        {#key `${memo.id}-${locked}`}
          <MemoEditor id={memo.id} text={textOf(memo)} autofocus={ns.focusMemo === memo.id} />
        {/key}
        {#if locked}
          <div class="relock">
            <button class="chip accent" onclick={relockAll}><Icon name="lock" fill size=".85em" /> 지금 잠그기</button>
            <RelockLabel />
          </div>
        {/if}
      {:else}
        <LockedPanel memoId={memo.id} />
      {/if}
    </div>
  {/if}
</div>

<style>
  .memo { border-bottom: 1px solid var(--line); }
  .head { display: flex; align-items: flex-start; gap: 8px; padding: 5px 0; }
  .lead { flex: none; width: 1.2em; height: 1.2em; display: inline-flex; align-items: center; justify-content: center; color: var(--fg2); }
  .lead.on { color: var(--accent); }
  .mid { min-width: 0; display: flex; flex-direction: column; gap: 2px; }
  .title { font-size: .96em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; cursor: default; }
  .sub { font-size: .85em; color: var(--fg2); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .edit { font-size: .96em; width: 100%; padding: 0; border: none; outline: none; background: transparent; user-select: text; }
  .fill { flex: 1; align-self: stretch; min-width: 4px; }
  .acts { display: flex; align-items: center; gap: 2px; opacity: 0; }
  .head:hover .acts, .head.pop .acts { opacity: 1; }
  .mini { width: 1.5em; height: 1.5em; font-size: .78em; }
  .body { display: flex; flex-direction: column; gap: 4px; padding: 0 0 6px calc(1.2em + 8px); }
  .relock { display: flex; align-items: center; gap: 6px; }
</style>
