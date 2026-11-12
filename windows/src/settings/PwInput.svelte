<script lang="ts">
  // 비밀번호 입력칸. 자동완성 말풍선을 막는다.
  let { label, value = $bindable(""), onenter }: { label: string; value?: string; onenter?: () => void } = $props();
</script>

<input class="field selectable" type="password" autocomplete="off" placeholder={label} aria-label={label} bind:value
  onkeydown={(e) => { if (e.key === "Enter") onenter?.(); }} />
