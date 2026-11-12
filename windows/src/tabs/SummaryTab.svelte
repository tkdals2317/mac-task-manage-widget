<script lang="ts">
  // 요약 탭 (Mac SummaryView): 일간/주간 전환, 날짜 이동, Markdown 보기·직접 수정, 복사·다시 생성·일지 열기.
  import { onDestroy, onMount } from "svelte";
  import { listen } from "@tauri-apps/api/event";
  import { settings, setSetting } from "../lib/settings.svelte";
  import { native } from "../lib/native";
  import { copyText } from "../lib/toast.svelte";
  import Sym from "../lib/Sym.svelte";
  import Markdown from "../lib/Markdown.svelte";
  import Confirm from "../lib/Confirm.svelte";
  import {
    sm, loadSummary, loadWeekly, generateDaily, generateWeekly, saveEdit, fileName, worklogFile,
  } from "../lib/summary.svelte";
  import { addDays, dayKey, dayTitle, sameDay, weekDays, weekTitle } from "../lib/summaryCore";
  import { CLAUDE_NOT_FOUND } from "../lib/summaryCore";

  let day = $state(new Date());
  let weekly = $derived(settings.summaryWeekly);
  let editing = $state<{ day: Date; weekly: boolean; original: string } | null>(null);
  let draft = $state("");
  let confirmDiscard = $state(false);
  let confirmRegen = $state(false);
  let editor: HTMLTextAreaElement | undefined = $state();

  let shown = $derived(weekly ? sm.weekly : sm.summary);
  let current = $derived(weekly ? sm.weekly?.markdown ?? null : sm.summary?.markdown ?? sm.worklogRaw);
  let editedAt = $derived(shown ? sm.edits[fileName(day, weekly)] : undefined);
  let label = $derived(weekly ? weekTitle(day) : { title: dayTitle(day), range: null as string | null });

  const reload = () => (weekly ? loadWeekly(day) : loadSummary(day));

  $effect(() => {
    void day; void weekly;
    void reload();
  });

  let timer: ReturnType<typeof setInterval>;
  let unlisten: (() => void) | undefined;
  onMount(() => {
    // 오늘을 보고 있으면 30초마다 다시 읽는다 (일지·자동 생성 반영)
    timer = setInterval(() => {
      if (sameDay(day, new Date()) && !sm.generating && !editing) void reload();
    }, 30_000);
    listen("panel-hidden", () => finish(true)).then((f) => (unlisten = f));
  });
  onDestroy(() => { clearInterval(timer); unlisten?.(); finish(true); });

  function shift(n: number) {
    finish(true);
    day = addDays(day, weekly ? n * 7 : n);
  }

  function setWeekly(w: boolean) {
    if (w === weekly) return;
    finish(true);
    sm.error = null;
    setSetting("summaryWeekly", w);
  }

  function startEdit() {
    if (!shown) return;
    draft = shown.markdown;
    editing = { day, weekly, original: shown.markdown };
    queueMicrotask(() => editor?.focus());
  }

  function cancelEdit() {
    if (editing && draft !== editing.original) confirmDiscard = true;
    else finish(false);
  }

  /** 수정 끝. 바뀌었으면 저장 (실패하면 내용을 잃지 않게 수정 모드 유지). */
  async function finish(save: boolean) {
    const e = editing;
    if (!e) return;
    if (save && draft !== e.original) {
      if (!(await saveEdit(draft, e.day, e.weekly))) return;
    }
    editing = null;
  }

  function regenerate() {
    const force = shown != null;
    if (weekly) void generateWeekly(day, force); else void generateDaily(day, force);
  }

  function editorKey(e: KeyboardEvent) {
    if (e.key === "Enter" && e.ctrlKey) { e.preventDefault(); void finish(true); }
    if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); cancelEdit(); }
  }

  const time = (d: Date) => d.toLocaleTimeString("ko-KR", { hour: "numeric", minute: "2-digit" });
  const openLog = () => native.openDataPath(`logs/summary-${weekly ? "week-" + weekDays(day).key : dayKey(day)}.log`, true).catch(() => {});
</script>

<svelte:window onkeydown={(e) => { if (e.key === "e" && e.ctrlKey && shown && !editing && !sm.generating) { e.preventDefault(); startEdit(); } }} />

<div class="summary">
  <div class="head">
    <div class="mode">
      <div class="pill" style="transform: translateX({weekly ? 100 : 0}%)"></div>
      <button class:on={!weekly} onclick={() => setWeekly(false)}>일간</button>
      <button class:on={weekly} onclick={() => setWeekly(true)}>주간</button>
    </div>
    <div class="nav">
      <button class="icon-btn" aria-label="이전" onclick={() => shift(-1)}><Sym name="chevron-left" /></button>
      <span class="title">{label.title}</span>
      {#if label.range}<span class="range">{label.range}</span>{/if}
      <button class="icon-btn" aria-label="다음" onclick={() => shift(1)}><Sym name="chevron-right" /></button>
    </div>
  </div>
  <div class="divider"></div>

  {#if editing}
    <div class="edit-wrap">
      <textarea class="field mono editor" bind:this={editor} bind:value={draft} onkeydown={editorKey} spellcheck="false"></textarea>
    </div>
  {:else}
    <div class="body scroll">
      {#if weekly}
        {#if sm.weekly}<Markdown markdown={sm.weekly.markdown} />
        {:else}<div class="empty">주간 요약 없음</div>{/if}
      {:else if sm.summary}
        <Markdown markdown={sm.summary.markdown} />
      {:else if sm.worklogRaw?.trim()}
        <div class="caption">업무 일지 (요약 전)</div>
        <Markdown markdown={sm.worklogRaw} />
      {:else}
        <div class="empty">기록 없음</div>
      {/if}
    </div>
  {/if}

  <div class="divider"></div>
  {#if editing}
    <div class="foot">
      <span class="status">Ctrl+Enter 저장 · Esc 취소</span>
      <div class="grow"></div>
      <button class="chip lg plain" onclick={cancelEdit}><Sym name="x" />취소</button>
      <button class="chip lg solid" onclick={() => finish(true)}><Sym name="check" />저장</button>
    </div>
  {:else}
    <div class="foot">
      {#if shown && !sm.generating}
        <button class="chip lg soft" title="수정 (Ctrl+E)" onclick={startEdit}><Sym name="pencil" />수정</button>
      {/if}
      <button class="chip lg soft" disabled={current == null} onclick={() => current && copyText(current, "요약을 복사했어요")}><Sym name="copy" />복사</button>
      <button class="chip lg soft" disabled={sm.generating} onclick={() => (editedAt ? (confirmRegen = true) : regenerate())}>
        <Sym name="refresh" />{shown ? "다시 생성" : "생성"}
      </button>
      {#if !weekly}
        <button class="chip lg soft" disabled={sm.worklogRaw == null} onclick={() => native.openDataPath(worklogFile(day), true)}><Sym name="book" />일지</button>
      {/if}
      <div class="grow"></div>
      <div class="status">
        {#if sm.generating}
          <span class="gen"><span class="spin"><Sym name="refresh" /></span> 생성 중…</span>
        {:else if sm.error}
          <span class="err" title={sm.error}>{sm.error}</span>
          {#if sm.error === CLAUDE_NOT_FOUND}<button class="chip" onclick={() => native.openSettings("summary")}>설정</button>{/if}
          <button class="chip" onclick={openLog}>로그</button>
        {:else if shown}
          <span>{time(shown.generatedAt)} 생성</span>
          {#if editedAt}<span>{time(new Date(editedAt))} 수정</span>{/if}
        {/if}
      </div>
    </div>
  {/if}
</div>

<Confirm bind:open={confirmDiscard} title="수정한 내용을 버릴까요?" confirm="버리기" danger onconfirm={() => finish(false)} />
<Confirm bind:open={confirmRegen} title="직접 수정한 내용이 사라져요. 다시 생성할까요?" confirm="다시 생성" onconfirm={regenerate} />

<style>
  .summary { display: flex; flex-direction: column; height: 100%; min-height: 0; }
  .head { display: flex; flex-direction: column; gap: 6px; padding: 8px 12px; }
  .mode { position: relative; display: flex; padding: 2px; border-radius: 999px; background: var(--fill2); }
  .mode .pill { position: absolute; top: 2px; bottom: 2px; left: 2px; width: calc(50% - 2px); border-radius: 999px; background: var(--accent); transition: transform 0.25s cubic-bezier(.3,.7,.3,1); }
  .mode button { position: relative; flex: 1; padding: 3px 0; border: none; background: transparent; color: var(--fg2); border-radius: 999px; font-size: 0.93em; }
  .mode button.on { color: var(--on-accent); font-weight: 600; }
  .nav { display: flex; align-items: baseline; justify-content: center; gap: 8px; }
  .nav .icon-btn { align-self: center; }
  .title { font-weight: 600; }
  .range { font-size: 0.85em; color: var(--fg2); }
  .divider { height: 0.5px; background: var(--line2); flex: none; }
  .body { flex: 1; min-height: 0; padding: 12px; }
  .caption { font-size: 0.8em; color: var(--fg2); margin-bottom: 4px; }
  .empty { padding-top: 20px; color: var(--fg2); font-size: 0.93em; }
  .edit-wrap { flex: 1; min-height: 0; padding: 10px; display: flex; }
  .editor { flex: 1; font-size: 0.9em; padding: 8px; }
  .foot { display: flex; align-items: center; gap: 6px; padding: 6px 10px; flex: none; }
  .grow { flex: 1; }
  .status { display: flex; flex-direction: column; align-items: flex-end; font-size: 0.8em; color: var(--fg2); min-width: 0; text-align: right; }
  .status:has(.err) { flex-direction: row; align-items: center; gap: 4px; }
  .err { color: var(--danger); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 170px; }
  .gen { display: inline-flex; align-items: center; gap: 4px; }
</style>
