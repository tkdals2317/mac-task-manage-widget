<script lang="ts">
  // 설정 도우미 (Mac OnboardingView): 쓸 기능 고르기 → 고른 기능에 필요한 설정을 차례로 → 마무리(테마·단축키·로그인 시 실행).
  import { onMount } from "svelte";
  import { emit } from "@tauri-apps/api/event";
  import { setSetting, settings } from "../lib/settings.svelte";
  import { native } from "../lib/native";
  import { JIRA_KEYCHAIN_SERVICE } from "../lib/jira";
  import { hookStatus, installHook, installTodoSkill, installWorklogSkill, todoSkillInstalled, worklogSkillInstalled, locateClaude } from "../lib/claude";
  import Sym, { type SymName } from "../lib/Sym.svelte";
  import Segmented from "./Segmented.svelte";
  import JiraPane from "./JiraPane.svelte";
  import NotesPane from "./NotesPane.svelte";
  import PRPane from "./PRPane.svelte";
  import { PRESETS } from "../lib/theme";

  let { ondone }: { ondone: () => void } = $props();

  const FEATURES: { id: string; title: string; desc: string; icon: SymName; tab?: string }[] = [
    { id: "jira", title: "Jira", desc: "내게 할당된 이슈를 할 일 탭에", icon: "jira" },
    { id: "notes", title: "노트", desc: "잠글 수 있는 메모, 링크, Confluence 별표", icon: "notes", tab: "notes" },
    { id: "summary", title: "요약", desc: "Claude Code 세션으로 하루·주간 업무 요약", icon: "sparkles", tab: "summary" },
    { id: "pr", title: "PR", desc: "GitHub·Bitbucket 리뷰 요청과 내 PR", icon: "branch", tab: "pr" },
    { id: "teleport", title: "Teleport", desc: "DB 터널 자동 로그인·유지", icon: "globe", tab: "teleport" },
  ];

  const cur = settings.enabledTabs.split(",");
  let picked = $state(new Set<string>([...FEATURES.filter((f) => f.tab && cur.includes(f.tab)).map((f) => f.id), ...(settings.jiraEmail ? ["jira"] : [])]));
  let step = $state(0); // 0 = 고르기, 1..n = 기능별, n+1 = 마무리
  let steps = $derived(FEATURES.filter((f) => picked.has(f.id)));
  let current = $derived(step >= 1 && step <= steps.length ? steps[step - 1] : null);

  let jiraOk = $state(false);
  let claude = $state<{ path: string } | null | undefined>(undefined);
  let hook = $state(""); let skill = $state(false); let todoSkill = $state(false);
  let busy = $state(false);

  async function refresh() {
    jiraOk = settings.jiraEmail ? (await native.secretGet(JIRA_KEYCHAIN_SERVICE, settings.jiraEmail.trim()).catch(() => null)) != null : false;
    claude = await locateClaude(settings.claudePath);
    hook = await hookStatus();
    skill = await worklogSkillInstalled().catch(() => false);
    todoSkill = await todoSkillInstalled().catch(() => false);
  }
  onMount(() => { void refresh(); });

  function toggle(id: string) { const s = new Set(picked); if (!s.delete(id)) s.add(id); picked = s; }

  function applyTabs() {
    const tabs = ["tasks", ...FEATURES.filter((f) => f.tab && picked.has(f.id)).map((f) => f.tab!)];
    const order = ["tasks", "summary", "notes", "pr", "teleport"];
    setSetting("enabledTabs", order.filter((t) => tabs.includes(t)).join(","));
  }

  async function setupClaudeAll() {
    busy = true;
    try { await installHook(); await installWorklogSkill(); await installTodoSkill(); } catch { /* 화면에 상태로 보인다 */ }
    await refresh();
    busy = false;
  }

  function finish() {
    applyTabs();
    setSetting("onboardingDone", true);
    void emit("pr-config-changed");
    ondone();
  }
</script>

<div class="pane">
  <div class="steps">
    {#each ["기능 고르기", ...steps.map((s) => s.title), "마무리"] as s, i (i)}
      <span class:on={i === step} class:done={i < step}>{i + 1}. {s}</span>
    {/each}
  </div>

  {#if step === 0}
    <div class="hint">쓸 기능을 고르면, 고른 기능에 필요한 설정만 차례로 안내해요. 할 일 탭은 늘 켜져 있어요. 나중에 설정 &gt; 정보 &gt; 설정 도우미 열기로 다시 할 수 있어요.</div>
    <div class="feats">
      {#each FEATURES as f (f.id)}
        <button class="feat" class:on={picked.has(f.id)} onclick={() => toggle(f.id)}>
          <span class="fi"><Sym name={f.icon} size={1.3} /></span>
          <span class="ft"><b>{f.title}</b><span>{f.desc}</span></span>
          <span class="chk">{#if picked.has(f.id)}<Sym name="check-circle" size={1.2} />{/if}</span>
        </button>
      {/each}
    </div>
    <div class="card-title">비밀 정보 저장</div>
    <div class="card">
      <div class="srow">
        <span>저장 위치</span>
        <Segmented value={settings.secretStorage} onpick={(v) => setSetting("secretStorage", v)}
          options={[{ value: "credman", label: "자격 증명 관리자 (권장)" }, { value: "file", label: "파일" }]} />
      </div>
    </div>
  {:else if current?.id === "jira"}
    <JiraPane bind:hasToken={jiraOk} />
  {:else if current?.id === "notes"}
    <NotesPane />
  {:else if current?.id === "summary"}
    <div class="card">
      <div class="srow">
        <div class="grow"><div>Claude Code CLI</div><div class="hint selectable">{claude ? claude.path : claude === null ? "찾지 못함 · Claude Code 를 설치하고 로그인해 주세요 (claude → /login)" : "찾는 중…"}</div></div>
        <button class="btn" onclick={refresh}>다시 찾기</button>
      </div>
      <div class="srow">
        <div class="grow"><div>활동 훅 · /worklog · atm-todo 스킬</div><div class="hint">훅 {hook === "installed" ? "설치됨" : "미설치"} · /worklog {skill ? "설치됨" : "미설치"} · atm-todo {todoSkill ? "설치됨" : "미설치"}</div></div>
        <button class="btn primary" disabled={busy || (hook === "installed" && skill && todoSkill)} onclick={setupClaudeAll}>한 번에 설치</button>
      </div>
      <div class="srow">
        <span>요약 생성 시각</span>
        <span class="actions">
          <select class="field" value={settings.summaryHour} onchange={(e) => setSetting("summaryHour", Number(e.currentTarget.value))}>
            {#each Array.from({ length: 24 }, (_, i) => i) as h}<option value={h}>{String(h).padStart(2, "0")}</option>{/each}
          </select>:
          <select class="field" value={settings.summaryMinute} onchange={(e) => setSetting("summaryMinute", Number(e.currentTarget.value))}>
            {#each [0, 15, 30, 45] as m}<option value={m}>{String(m).padStart(2, "0")}</option>{/each}
          </select>
        </span>
      </div>
    </div>
    <div class="hint">~/.claude/settings.json 은 바꾸기 전에 백업해요. 훅은 새 Claude Code 세션부터 기록해요.</div>
  {:else if current?.id === "pr"}
    <PRPane />
  {:else if current?.id === "teleport"}
    <div class="card">
      <div class="srow col">
        <div>Teleport 로그인과 DB 고르기는 패널의 Teleport 탭에서 이어서 해요.</div>
        <div class="actions"><button class="btn primary" onclick={() => { applyTabs(); setSetting("lastTab", "teleport"); void emit("teleport-setup-requested"); }}>Teleport 탭 열기</button></div>
        <div class="hint">tsh(Teleport 클라이언트)가 PATH 에 있어야 해요. 없으면 설정 &gt; Teleport 에서 경로를 지정할 수 있어요.</div>
      </div>
    </div>
  {:else}
    <div class="card">
      <div class="srow">
        <span>테마 색</span>
        <select class="field" value={settings.themePreset} onchange={(e) => setSetting("themePreset", e.currentTarget.value)}>
          {#each PRESETS as p (p.id)}<option value={p.id}>{p.name}</option>{/each}
        </select>
      </div>
      <label class="srow">
        <span>전역 단축키 ({settings.globalHotKey})로 패널 열기/닫기</span>
        <input class="switch" type="checkbox" checked={settings.globalHotKeyEnabled} onchange={(e) => setSetting("globalHotKeyEnabled", e.currentTarget.checked)} />
      </label>
      <label class="srow">
        <span>Windows 로그인 시 실행</span>
        <input class="switch" type="checkbox" checked={settings.launchAtLogin} onchange={(e) => setSetting("launchAtLogin", e.currentTarget.checked)} />
      </label>
    </div>
    <div class="hint">패널은 작업 표시줄 오른쪽 트레이의 ATM 아이콘(왼쪽 클릭) 또는 단축키로 열고 닫아요. ✕·Esc 는 끄지 않고 트레이로 숨겨요.</div>
  {/if}

  <div class="nav-row">
    {#if step > 0}<button class="btn" onclick={() => (step -= 1)}>이전</button>{/if}
    <span class="grow"></span>
    {#if step === 0}<button class="btn" onclick={finish}>건너뛰기</button>{/if}
    {#if step <= steps.length}
      <button class="btn primary" onclick={() => { if (step === 0) applyTabs(); step += 1; void refresh(); }}>다음</button>
    {:else}
      <button class="btn primary" onclick={finish}>시작하기</button>
    {/if}
  </div>
</div>

<style>
  .steps { display: flex; flex-wrap: wrap; gap: 4px 12px; font-size: 0.85em; color: var(--fg3); padding: 8px 0 4px; }
  .steps .on { color: var(--accent-text); font-weight: 700; }
  .steps .done { color: var(--fg2); }
  .feats { display: flex; flex-direction: column; gap: 8px; }
  .feat { display: flex; align-items: center; gap: 12px; padding: 12px 14px; border-radius: 10px; border: 0.5px solid var(--line2); background: var(--fill); text-align: left; }
  .feat.on { border-color: var(--accent); background: var(--accent-soft); }
  .fi { color: var(--accent); }
  .ft { flex: 1; display: flex; flex-direction: column; gap: 2px; }
  .ft span { font-size: 0.88em; color: var(--fg2); }
  .chk { width: 22px; color: var(--accent); }
  .nav-row { display: flex; gap: 8px; margin-top: 10px; }
  .grow { flex: 1; }
  select.field { width: auto; }
</style>
