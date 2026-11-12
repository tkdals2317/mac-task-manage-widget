<script lang="ts">
  import { ns } from "../lib/notes.svelte";
  // "N분 뒤 잠김". 저장소가 15초마다 now 를 갱신한다.
  const min = $derived(ns.relockAt === null ? null : Math.max(1, Math.ceil((ns.relockAt - ns.now) / 60000)));
</script>

{#if min !== null}<span class="faint" style="font-size:.81em">{min}분 뒤 잠김</span>{/if}
