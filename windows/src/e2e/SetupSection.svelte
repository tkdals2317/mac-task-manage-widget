<script lang="ts">
  // E2E 탭 위쪽의 준비 점검. 봐야 할 항목(막힘·주의·안내)이 있을 때만 보이고, 실행을 막는 항목이 있으면 접을 수 없다. (Mac E2ESetupSection)
  import Sym from "../lib/Sym.svelte";
  import SectionHeader from "../tasks/SectionHeader.svelte";
  import { checkAside, e2e, setupItems } from "../lib/e2e.svelte";
  import { blocker, needsAttention } from "../lib/asideCore";
  import { e2eURLKey, e2eUserKey, setSetting, settings } from "../lib/settings.svelte";
  import type { E2EEnv } from "../lib/e2eCore";
  import SetupList from "./SetupList.svelte";

  let { env }: { env: E2EEnv } = $props();
  // 주소·계정 설정이 바뀌면 다시 계산되도록 값을 읽어 둔다
  const items = $derived.by(() => { void settings[e2eURLKey(env)]; void settings[e2eUserKey(env)]; void e2e.report; void e2e.jobs; return setupItems(env); });
  const pending = $derived(items.filter(needsAttention));
  const blocked = $derived(blocker(items) !== undefined);
  const collapsed = $derived(blocked ? false : settings.e2eSetupCollapsed);
</script>

{#if pending.length}
  <SectionHeader title="준비" count={pending.length} bind:collapsed={() => collapsed, (v) => { if (!blocked) setSetting("e2eSetupCollapsed", v); }}>
    {#snippet trailing()}
      <button class="chip plain" disabled={e2e.checking} onclick={() => checkAside()}><Sym name="refresh" size={0.95} />{e2e.checking ? "확인 중…" : "다시 확인"}</button>
    {/snippet}
  </SectionHeader>
  {#if !collapsed}
    <div class="box" class:blocked><SetupList {items} {env} pendingOnly /></div>
  {/if}
{/if}

<style>
  .box { padding: 8px; border-radius: 6px; background: var(--fill); }
  .box.blocked { background: var(--warn-soft); }
</style>
