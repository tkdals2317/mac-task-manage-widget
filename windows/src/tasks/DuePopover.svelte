<script lang="ts">
  // 빠른 선택 + 날짜 입력(<input type="date"> 의 달력). 날짜를 고르면 바로 저장하고 팝오버는 유지, 빠른 선택은 저장 후 닫는다.
  import { dayKey, nextMonday } from "../lib/due";
  import Popover from "./Popover.svelte";

  let { due, anchor, onpick, onclose }: {
    due?: string; anchor: HTMLElement; onpick: (key: string | null) => void; onclose: () => void;
  } = $props();

  let value = $state(due ?? dayKey(new Date()));

  function pick(d: Date) { onpick(dayKey(d)); onclose(); }
  function tomorrow() { const d = new Date(); d.setDate(d.getDate() + 1); return d; }
  function onchange(e: Event & { currentTarget: HTMLInputElement }) {
    const v = e.currentTarget.value; // 지우면 "" — 그땐 아무것도 안 함
    if (v) { value = v; onpick(v); }
  }
</script>

<Popover {anchor} {onclose}>
  <div class="due">
    <div class="quick">
      <button class="btn" onclick={() => pick(new Date())}>오늘</button>
      <button class="btn" onclick={() => pick(tomorrow())}>내일</button>
      <button class="btn" onclick={() => pick(nextMonday(new Date()))}>다음 주 월</button>
      <button class="btn" onclick={() => { onpick(null); onclose(); }}>마감 없음</button>
    </div>
    <input class="field date" type="date" {value} {onchange} />
  </div>
</Popover>

<style>
  .due { display: flex; flex-direction: column; gap: 8px; }
  .quick { display: flex; gap: 6px; flex-wrap: wrap; }
  .quick .btn { padding: 2px 8px; font-size: 0.92em; }
  .date { user-select: auto; color-scheme: light dark; }
</style>
