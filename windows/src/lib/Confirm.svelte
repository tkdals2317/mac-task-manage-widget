<script lang="ts">
  // 확인 대화상자 (Mac confirmationDialog). open 이 true 일 때만 그린다.
  let {
    open = $bindable(false), title, message = "", confirm = "확인", danger = false, onconfirm,
  }: { open?: boolean; title: string; message?: string; confirm?: string; danger?: boolean; onconfirm: () => void } = $props();

  function key(e: KeyboardEvent) {
    if (!open) return;
    if (e.key === "Escape") { e.stopPropagation(); open = false; }
    if (e.key === "Enter") { e.stopPropagation(); open = false; onconfirm(); }
  }
</script>

<svelte:window onkeydown={key} />

{#if open}
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
  <div class="modal-back" onclick={() => (open = false)}>
    <div class="modal" role="dialog" tabindex="-1" aria-modal="true" aria-label={title} onclick={(e) => e.stopPropagation()}>
      <div class="title">{title}</div>
      {#if message}<div class="msg">{message}</div>{/if}
      <div class="acts">
        <button class="btn" onclick={() => (open = false)}>취소</button>
        <button class="btn primary" class:danger onclick={() => { open = false; onconfirm(); }}>{confirm}</button>
      </div>
    </div>
  </div>
{/if}

<style>
  .btn.primary.danger { background: var(--danger); }
</style>
