<script lang="ts">
  // 링크 수정 창: 이름 + 주소. 이름을 비우면 새 주소의 페이지 제목을 받아 온다.
  import { updateLink } from "../lib/notes.svelte";
  import type { SavedLink } from "./data";
  import Popover from "./Popover.svelte";
  import PopButtons from "./PopButtons.svelte";
  let { link, done }: { link: SavedLink; done: () => void } = $props();
  let title = $state(link.title);
  let url = $state(link.url);
  let error = $state("");

  function submit(e: Event) {
    e.preventDefault();
    if (!updateLink(link.id, title, url)) { error = "주소로 볼 수 없어요"; return; }
    done();
  }
</script>

<Popover width={280}>
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <form onsubmit={submit} onkeydown={(e) => e.key === "Escape" && (e.stopPropagation(), done())}>
    <div style="display:flex;flex-direction:column;gap:6px">
      <div class="lbl">이름</div>
      <!-- svelte-ignore a11y_autofocus -->
      <input class="field" placeholder="비우면 페이지 제목" bind:value={title} autofocus />
      <div class="lbl" style="margin-top:2px">주소</div>
      <input class="field" placeholder="https://" bind:value={url} />
      {#if error}<div class="err">{error}</div>{/if}
      <div style="margin-top:4px"><PopButtons primary="저장" cancel={done} /></div>
    </div>
  </form>
</Popover>
