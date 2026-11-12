<script lang="ts">
  import Icon from "./Icon.svelte";
  let { primary, busy = false, cancel }: { primary: string; busy?: boolean; cancel: () => void } = $props();
</script>

<div class="btns">
  <button type="button" class="chip" onclick={cancel}><Icon name="x" size=".8em" /> 취소</button>
  <button type="submit" class="chip accent" disabled={busy}><Icon name="check" size=".8em" /> {primary}</button>
</div>
