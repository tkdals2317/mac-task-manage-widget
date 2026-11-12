<script lang="ts">
  // 노트 탭 (Mac NotesView): 메모 + 링크(직접 저장 / Confluence 별표).
  import { onMount } from "svelte";
  import { settings, setSetting } from "../lib/settings.svelte";
  import { native } from "../lib/native";
  import { addLink, addMemo, ns, orderedMemos, refreshConfluence, startNotes } from "../lib/notes.svelte";
  import { orderLinks } from "../notes/data";
  import ContextMenu from "../notes/ContextMenu.svelte";
  import ConfluenceRow from "../notes/ConfluenceRow.svelte";
  import Icon from "../notes/Icon.svelte";
  import LinkRow from "../notes/LinkRow.svelte";
  import MemoRow from "../notes/MemoRow.svelte";
  import SectionHead from "../notes/SectionHead.svelte";

  const FILTERS = [["all", "전체"], ["direct", "직접"], ["confl", "★ 컨플"]] as const;
  type Filter = (typeof FILTERS)[number][0];

  let newTitle = $state("");
  let newLink = $state("");
  let shake = $state(false);

  const confluenceOn = $derived(settings.confluenceBaseURL.trim() !== "");
  const filter = $derived((FILTERS.some((f) => f[0] === settings.notesLinkFilter) ? settings.notesLinkFilter : "all") as Filter);
  const memos = $derived(orderedMemos());
  const pages = $derived(filter !== "direct" && confluenceOn ? ns.starred : []);
  const links = $derived(filter === "confl" ? [] : orderLinks(ns.data.links));

  onMount(() => {
    void startNotes();
    // 나타날 때 한 번, 이후 갱신 주기마다 (패널이 보일 때만)
    const visible = () => document.visibilityState === "visible";
    if (visible()) void refreshConfluence();
    const t = setInterval(() => { if (visible()) void refreshConfluence(); }, Math.max(1, settings.jiraRefreshMinutes) * 60_000);
    return () => clearInterval(t);
  });

  function submitMemo(e: Event) {
    e.preventDefault();
    addMemo(newTitle);
    newTitle = "";
  }
  function submitLink(e: Event) {
    e.preventDefault();
    const t = newLink.trim();
    if (!t) return;
    if (addLink(t)) newLink = "";
    else { shake = true; setTimeout(() => (shake = false), 350); } // 주소로 볼 수 없으면 입력은 두고 흔들어 알린다
  }
  const time = $derived(ns.starredUpdatedAt === null ? "" : new Date(ns.starredUpdatedAt).toLocaleTimeString("ko-KR", { hour: "numeric", minute: "2-digit" }));
</script>

<div class="notes scroll">
  <SectionHead title="메모" count={memos.length} collapsed={settings.notesMemoCollapsed} ontoggle={() => setSetting("notesMemoCollapsed", !settings.notesMemoCollapsed)} />
  {#if !settings.notesMemoCollapsed}
    <form onsubmit={submitMemo}><input class="field add" placeholder="메모 추가…" bind:value={newTitle} /></form>
    {#each memos as m (m.id)}<MemoRow memo={m} />{/each}
    {#if memos.length === 0}<div class="empty faint">메모 없음</div>{/if}
  {/if}

  <SectionHead title="링크" count={pages.length + links.length} collapsed={settings.notesLinkCollapsed} ontoggle={() => setSetting("notesLinkCollapsed", !settings.notesLinkCollapsed)}>
    <div class="chips">
      {#each FILTERS as [id, label] (id)}
        {#if id !== "confl" || confluenceOn}
          <button class="fchip" class:on={filter === id} onclick={() => setSetting("notesLinkFilter", id)}>{label}</button>
        {/if}
      {/each}
    </div>
    {#if confluenceOn}
      <button class="icon-btn refresh" title="새로고침" onclick={() => refreshConfluence()}><Icon name="refresh" size="1em" /></button>
    {/if}
  </SectionHead>
  {#if !settings.notesLinkCollapsed}
    <form onsubmit={submitLink}><input class="field add" class:shake placeholder="링크 붙여넣기…" bind:value={newLink} /></form>
    {#each pages as p (p.id)}<ConfluenceRow page={p} />{/each}
    {#each links as l (l.id)}<LinkRow link={l} />{/each}
    {#if pages.length === 0 && links.length === 0}<div class="empty faint">링크 없음</div>{/if}
    {#if confluenceOn}
      <div class="footer">
        {#if ns.starredError}
          <span class="err">{ns.starredError}</span>
          <button class="chip" onclick={() => native.openSettings("notes")}>설정</button>
        {:else if time}
          <span>↻ {time} 갱신 · 별표는 Confluence에서</span>
        {/if}
        <span class="grow"></span>
        {#if ns.starredLoading}<span class="spin" aria-label="불러오는 중"></span>{/if}
      </div>
    {/if}
  {/if}
</div>
<ContextMenu />

<style>
  .notes { height: 100%; padding: 0 10px 8px; user-select: none; }
  .add { margin: 4px 0; padding: 4px 7px; font-size: .92em; user-select: text; }
  .empty { padding: 8px 0; font-size: .88em; }
  .chips { display: flex; gap: 3px; }
  .fchip { padding: 1.5px 6px; border: none; border-radius: 999px; font-size: .77em; background: var(--fill2); color: var(--fg2); cursor: pointer; }
  .fchip.on { background: var(--accent); color: #fff; font-weight: 600; }
  .refresh { width: 1.5em; height: 1.5em; font-size: .8em; }
  .footer { display: flex; align-items: center; gap: 6px; padding-top: 6px; font-size: .81em; color: var(--fg2); }
  .footer .err { color: var(--danger); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .grow { flex: 1; }
  .spin { width: .9em; height: .9em; border-radius: 50%; border: 2px solid var(--line); border-top-color: var(--accent); animation: sp .8s linear infinite; }
  @keyframes sp { to { transform: rotate(360deg); } }
  .shake { animation: sh .35s; }
  @keyframes sh { 0%,100% { transform: translateX(0); } 20%,60% { transform: translateX(6px); } 40%,80% { transform: translateX(-6px); } }
</style>
