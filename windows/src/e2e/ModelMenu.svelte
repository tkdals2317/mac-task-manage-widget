<script lang="ts">
  // 실행에 쓸 Aside 모델 메뉴 (Jira 버전 메뉴와 같은 알약). 목록은 Aside 가 받아 둔 카탈로그, 없는 id 는 설정에서 직접 입력. (Mac E2EModelMenu)
  import Sym from "../lib/Sym.svelte";
  import Menu, { type MenuItem } from "../tasks/Menu.svelte";
  import { e2e, modelName } from "../lib/e2e.svelte";
  import { needsPaidPlan } from "../lib/asideCore";
  import { setSetting, settings } from "../lib/settings.svelte";
  import { native } from "../lib/native";

  let open = $state(false);
  let btn: HTMLElement | undefined = $state();
  const model = $derived(settings.e2eModel);
  const pick = (id: string) => () => setSetting("e2eModel", id);

  const items = $derived.by<MenuItem[]>(() => {
    const out: MenuItem[] = [{ label: "Aside 기본 모델", checked: model === "", onselect: pick("") }];
    // Aside 제공 모델을 먼저, 내가 연동한 provider 모델은 이름순으로 나눈다.
    const providers = [...new Set(e2e.models.map((m) => m.provider))].sort((a, b) => (a === "aside" ? -1 : b === "aside" ? 1 : a < b ? -1 : 1));
    for (const p of providers) {
      out.push({ separator: true }, { header: true, label: p === "aside" ? "Aside 제공" : `연동: ${p}` });
      for (const m of e2e.models.filter((x) => x.provider === p)) {
        const locked = needsPaidPlan(m) && e2e.plan.toLowerCase() === "free";
        out.push({ label: needsPaidPlan(m) ? `${m.name} · ${m.minPlan[0].toUpperCase()}${m.minPlan.slice(1)}` : m.name, checked: model === m.id, disabled: locked, onselect: pick(m.id) });
      }
    }
    if (model && !e2e.models.some((m) => m.id === model)) out.push({ separator: true }, { label: model, checked: true, onselect: pick(model) });
    out.push({ separator: true }, { label: "직접 입력…", onselect: () => void native.openSettings("e2e") });
    return out;
  });
</script>

<button bind:this={btn} class="mm" class:sel={model !== ""} title="검증에 쓸 Aside 모델" onclick={() => (open = !open)}>
  <Sym name="cpu" size={0.95} /><span class="nm">{model ? modelName(model) : "기본 모델"}</span><Sym name="chevron-down" size={0.7} />
</button>
{#if open && btn}<Menu {items} anchor={btn} align="end" onclose={() => (open = false)} />{/if}

<style>
  .mm {
    display: inline-flex; align-items: center; gap: 3px; padding: 1px 7px; border-radius: 999px; font-size: 0.92em; max-width: 160px;
    color: var(--fg2); background: transparent; border: 1px solid var(--line); cursor: pointer;
  }
  .mm.sel { color: var(--fg); background: var(--fill2); border-color: transparent; }
  .nm { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
</style>
