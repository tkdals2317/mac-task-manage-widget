<script lang="ts">
  // 잠긴 메모 열기용 비밀번호 팝오버.
  import { unlockMemo } from "../lib/notes.svelte";
  import Popover from "./Popover.svelte";
  import PopButtons from "./PopButtons.svelte";
  let { memoId, initialError = "", done }: { memoId: string; initialError?: string; done: () => void } = $props();
  let pw = $state("");
  let error = $state(initialError);
  let busy = $state(false);

  async function submit(e: Event) {
    e.preventDefault();
    if (busy || !pw) return;
    busy = true; error = "";
    try { await unlockMemo(memoId, pw); pw = ""; done(); }
    catch (err) { error = (err as Error).message; }
    finally { busy = false; }
  }
</script>

<Popover width={230}>
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <form onsubmit={submit} onkeydown={(e) => e.key === "Escape" && (e.stopPropagation(), done())}>
    <h4>비밀번호 입력</h4>
    <!-- svelte-ignore a11y_autofocus -->
    <input class="field" type="password" placeholder="비밀번호" bind:value={pw} autofocus style="margin-top:8px" />
    {#if error}<div class="err" style="margin-top:8px">{error}</div>{/if}
    <div style="margin-top:8px"><PopButtons primary="열기" busy={busy || !pw} cancel={done} /></div>
  </form>
</Popover>
