<script lang="ts">
  // 잠긴 메모를 펼쳤을 때: "열기" 버튼 하나. Windows Hello 를 켰으면 먼저 Hello, 꺼져 있거나 취소·실패하면 비밀번호 팝오버.
  import { HelloFallback, helloUsable, unlockWithHello } from "../lib/notes.svelte";
  import { clickOutside } from "./clickOutside";
  import Icon from "./Icon.svelte";
  import UnlockPopover from "./UnlockPopover.svelte";
  let { memoId }: { memoId: string } = $props();
  let ask = $state(false);
  let error = $state("");
  let busy = $state(false);

  async function openTapped() {
    error = "";
    if (!(await helloUsable())) { ask = true; return; }
    busy = true;
    try { await unlockWithHello(memoId); }
    catch (e) {
      if (!(e instanceof HelloFallback)) error = (e as Error).message;
      ask = true;
    } finally { busy = false; }
  }
</script>

<div style="position:relative;display:inline-block" use:clickOutside={() => (ask = false)}>
  <button class="chip accent" disabled={busy} onclick={openTapped}><Icon name="lockopen" fill size=".85em" /> 열기</button>
  {#if ask}{#key error}<UnlockPopover {memoId} initialError={error} done={() => (ask = false)} />{/key}{/if}
</div>
