<script lang="ts">
  // 준비 점검 목록: 항목마다 상태, 막힌 항목에는 할 일과 그 단계를 푸는 버튼. E2E 탭·설정·설정 도우미가 같이 쓴다. (Mac E2ESetupList)
  import Sym, { type SymName } from "../lib/Sym.svelte";
  import { checkAside, e2e, perform } from "../lib/e2e.svelte";
  import { fixLabel, needsAttention, type SetupFix, type SetupItem } from "../lib/asideCore";
  import type { E2EEnv } from "../lib/e2eCore";

  let { items, env = null, pendingOnly = false, recheck = false }: { items: SetupItem[]; env?: E2EEnv | null; pendingOnly?: boolean; recheck?: boolean } = $props();

  const icon = (s: SetupItem["state"]): SymName => (s === "ok" ? "check-circle" : s === "todo" ? "warning" : s === "warn" ? "warning" : s === "info" ? "info" : "minus-circle");
  const tint = (s: SetupItem["state"]) => (s === "ok" ? "var(--ok)" : s === "todo" || s === "warn" ? "var(--warn)" : "var(--fg2)");
  const fixIcon = (f: SetupFix): SymName =>
    f.kind === "downloadBrowser" || f.kind === "installCLI" ? "arrow-down-circle" : f.kind === "updateCLI" || f.kind === "loginCLI" ? "terminal"
      : f.kind === "openAside" ? "window" : f.kind === "switchAccount" ? "person" : f.kind === "openSettings" ? "gear" : "external";
  const rows = $derived(pendingOnly ? items.filter(needsAttention) : items);
  const switches = (it: SetupItem) => it.fixes.filter((f) => f.kind === "switchAccount");
  const others = (it: SetupItem) => it.fixes.filter((f) => f.kind !== "switchAccount");
</script>

<div class="sl">
  {#if e2e.report}
    {#each rows as it (it.kind)}
      <div class="r">
        <span class="ic" style="color:{tint(it.state)}"><Sym name={icon(it.state)} size={1.05} /></span>
        <div class="b">
          {#if needsAttention(it)}
            <div class="t">{it.title}</div>
            <div class="d" class:info={it.state === "info"}>{it.detail}</div>
          {:else}
            <div class="one"><span class="t" class:w={it.state === "waiting"}>{it.title}</span><span class="d2 selectable">{it.detail}</span></div>
          {/if}
          {#each it.steps as s, i (i)}<div class="step">{i + 1}. {s}</div>{/each}
          {#if it.note}<div class="note" class:strong={it.state === "todo"}>{it.note}</div>{/if}
          {#if others(it).length}
            <div class="fx">
              {#each others(it) as f, i (i)}
                <button class="chip {i === 0 && it.state === 'todo' ? 'solid' : 'soft'}" onclick={() => perform(f, env)}><Sym name={fixIcon(f)} size={0.95} />{fixLabel(f)}</button>
              {/each}
            </div>
          {/if}
          {#each switches(it) as f, i (i)}<div class="fx"><button class="chip soft" onclick={() => perform(f, env)}><Sym name={fixIcon(f)} size={0.95} />{fixLabel(f)}</button></div>{/each}
        </div>
      </div>
    {/each}
  {:else}
    <div class="load"><span class="spin dot"></span>Aside 준비 상태 확인 중…</div>
  {/if}
  {#if e2e.setupError}<div class="err">{e2e.setupError}</div>{/if}
  {#if recheck}
    <div class="re"><button class="chip plain" disabled={e2e.checking} onclick={() => checkAside()}><Sym name="refresh" size={0.95} />{e2e.checking ? "확인 중…" : "다시 확인"}</button></div>
  {/if}
</div>

<style>
  .sl { display: flex; flex-direction: column; gap: 7px; width: 100%; }
  .r { display: flex; align-items: baseline; gap: 6px; }
  .ic { flex: none; }
  .b { display: flex; flex-direction: column; gap: 3px; min-width: 0; flex: 1; }
  .t { font-weight: 600; }
  .t.w { color: var(--fg2); }
  .d { color: var(--warn); }
  .d.info { color: var(--fg2); }
  .one { display: flex; align-items: baseline; gap: 6px; min-width: 0; }
  .d2 { font-size: 0.95em; color: var(--fg2); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .step { font-size: 0.95em; color: var(--fg2); }
  .note { font-size: 0.9em; color: color-mix(in srgb, var(--fg2) 80%, transparent); }
  .note.strong { color: color-mix(in srgb, var(--fg) 75%, transparent); }
  .fx { display: flex; flex-wrap: wrap; gap: 6px; padding-top: 1px; }
  .load { display: flex; align-items: center; gap: 6px; color: var(--fg2); }
  .dot { width: 0.9em; height: 0.9em; border-radius: 50%; border: 2px solid var(--line); border-top-color: var(--accent); }
  .err { color: var(--danger); font-size: 0.95em; }
  .re { display: flex; justify-content: flex-end; }
</style>
