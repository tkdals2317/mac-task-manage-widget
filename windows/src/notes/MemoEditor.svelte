<script lang="ts">
  // 여러 줄 본문 편집기. 글자를 칠 때마다 저장소에 넘기고 저장은 저장소가 모아서 한다.
  import { onMount } from "svelte";
  import { setBody, ns } from "../lib/notes.svelte";
  let { id, text, autofocus }: { id: string; text: string; autofocus: boolean } = $props();
  let draft = $state(text);
  let el: HTMLTextAreaElement | undefined = $state();

  onMount(() => {
    if (autofocus) { el?.focus(); ns.focusMemo = null; }
  });
  function onkeydown(e: KeyboardEvent) {
    // Esc / Ctrl+Enter 로 편집을 마친다
    if (e.key === "Escape" || (e.key === "Enter" && e.ctrlKey)) { e.preventDefault(); e.stopPropagation(); el?.blur(); }
  }
</script>

<textarea bind:this={el} bind:value={draft} {onkeydown} oninput={() => setBody(id, draft)} spellcheck="false"
  placeholder="내용 (여러 줄, Ctrl+Enter 로 마침)"></textarea>

<style>
  textarea {
    width: 100%; resize: none; padding: 4px 5px; border: none; outline: none; border-radius: 5px;
    background: var(--fill); font-size: .92em; line-height: 1.3; user-select: text;
    field-sizing: content; min-height: 3.9em; max-height: 15.6em; overflow-y: auto;
    scrollbar-width: none;
  }
  textarea::placeholder { color: var(--fg3); }
</style>
