<script lang="ts">
  // 메모 잠그기 흐름의 비밀번호 팝오버: 처음이면 만들기, 열쇠가 없으면 확인. 끝나면 그 메모를 잠근다.
  import { createPassword, lockMemo, verify } from "../lib/notes.svelte";
  import Popover from "./Popover.svelte";
  import PopButtons from "./PopButtons.svelte";
  let { mode, memoId, done }: { mode: "create" | "verify"; memoId: string; done: () => void } = $props();
  let pw = $state("");
  let confirm = $state("");
  let error = $state("");
  let busy = $state(false);

  async function submit(e: Event) {
    e.preventDefault();
    if (busy) return;
    busy = true; error = "";
    try {
      if (mode === "create") await createPassword(pw, confirm);
      else await verify(pw);
      await lockMemo(memoId);
      done();
    } catch (err) { error = (err as Error).message; }
    finally { busy = false; }
  }
</script>

<Popover width={250}>
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <form onsubmit={submit} onkeydown={(e) => e.key === "Escape" && (e.stopPropagation(), done())}>
    <h4>{mode === "create" ? "잠금 비밀번호 만들기" : "비밀번호 확인"}</h4>
    <div style="display:flex;flex-direction:column;gap:8px;margin-top:8px">
      <!-- svelte-ignore a11y_autofocus -->
      <input class="field" type="password" placeholder="비밀번호" bind:value={pw} autofocus />
      {#if mode === "create"}
        <input class="field" type="password" placeholder="비밀번호 확인" bind:value={confirm} />
        <div class="warn">비밀번호를 잊으면 잠긴 메모는 되살릴 수 없습니다.</div>
      {/if}
      {#if error}<div class="err">{error}</div>{/if}
      <PopButtons primary={mode === "create" ? "만들고 잠그기" : "잠그기"} {busy} cancel={done} />
    </div>
  </form>
</Popover>
