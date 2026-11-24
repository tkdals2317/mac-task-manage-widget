<script lang="ts">
  // 스크린샷 썸네일. 누르면 기본 이미지 뷰어로 크게 연다. 결과 폴더 안의 이미지 일반 파일만 (Rust 가 검사한다).
  import { onMount } from "svelte";
  import { native } from "../lib/native";

  let { jobId, name }: { jobId: string; name: string } = $props();
  let src = $state<string | null | undefined>(undefined);
  onMount(() => { void native.e2eScreenshotData(jobId, name).then((d) => (src = d ? `data:${d[0]};base64,${d[1]}` : null)).catch(() => (src = null)); });
  const label = $derived(name.split(/[\\/]/).pop() ?? name);
</script>

{#if src !== null}
  <button class="th" title={label} onclick={() => native.e2eScreenshotOpen(jobId, name).catch(() => {})}>
    {#if src}<img {src} alt={label} />{/if}
  </button>
{/if}

<style>
  .th { flex: none; height: 72px; max-width: 128px; min-width: 40px; padding: 0; border: 0.5px solid var(--line2); border-radius: 4px; overflow: hidden; background: var(--fill); }
  .th img { display: block; height: 100%; width: auto; max-width: 128px; object-fit: contain; }
</style>
