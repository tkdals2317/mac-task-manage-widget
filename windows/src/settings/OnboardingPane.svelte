<script lang="ts">
  // 설정 도우미 (Mac OnboardingView): 직무 고르기(탭·Jira 목록 기본값) → 고른 기능에 필요한 설정을 차례로 → 마무리(테마·단축키·로그인 시 실행).
  import { onMount } from "svelte";
  import { emit } from "@tauri-apps/api/event";
  import { setSetting, settings, enabledTabs } from "../lib/settings.svelte";
  import { ROLES, TAB_ORDER, isValid, jqlFor, preset, previewLine, scopeForJQL, steps, STEP_TITLE, tabsString, type E2EScope, type JiraScope, type SetupStep, type UserRole } from "../lib/rolePreset";
  import { native } from "../lib/native";
  import { JIRA_KEYCHAIN_SERVICE } from "../lib/jira";
  import { hookStatus, installHook, installTodoSkill, installWorklogSkill, todoSkillInstalled, worklogSkillInstalled, locateClaude } from "../lib/claude";
  import Sym, { type SymName } from "../lib/Sym.svelte";
  import Segmented from "./Segmented.svelte";
  import JiraPane from "./JiraPane.svelte";
  import NotesPane from "./NotesPane.svelte";
  import PRPane from "./PRPane.svelte";
  import SetupList from "../e2e/SetupList.svelte";
  import { checkAside, e2e, reload as reloadE2E, setupItems } from "../lib/e2e.svelte";
  import { PRESETS } from "../lib/theme";

  let { ondone }: { ondone: () => void } = $props();

  const ROLE_ICON: Record<UserRole, SymName> = { developer: "terminal", planner: "doc", custom: "wand" };
  const TAB_TITLE: Record<string, string> = { tasks: "할 일", summary: "요약", notes: "노트", pr: "PR", e2e: "E2E", teleport: "Teleport" };

  // 다시 열면 저장된 직무를 고르고, 편집 영역은 직무 기본값이 아니라 지금 값으로 채운다.
  let role = $state<UserRole | null>(
    ROLES.some((r) => r.id === settings.userRole) ? (settings.userRole as UserRole) : settings.onboardingDone ? "custom" : null,
  );
  let tabs = $state(new Set<string>(enabledTabs(settings.enabledTabs, TAB_ORDER)));
  const curScope = scopeForJQL(settings.jiraJQL);
  /** 지금 저장된 JQL 이 담당·보고·둘 다 어디에도 안 맞는 직접 쓴 값이면 "지금 값 유지" 를 고를 수 있게 한다. */
  const customJQL = curScope === "keep";
  let jiraScope = $state<JiraScope>(curScope);
  let e2eScope = $state<E2EScope>(settings.e2eIssueScope === "reporter" ? "reporter" : "assignee");
  const jiraOptions = [
    { value: "assignee" as JiraScope, label: "담당" }, { value: "reporter" as JiraScope, label: "보고" }, { value: "both" as JiraScope, label: "둘 다" },
    ...(customJQL ? [{ value: "keep" as JiraScope, label: "지금 값 유지" }] : []),
  ];

  let step = $state(0); // steps 목록의 위치 (0 = 직무)
  let list = $derived(steps(tabs));
  let current = $derived<SetupStep>(list[Math.min(step, list.length - 1)]);
  let valid = $derived(isValid(tabs));
  let applied = false;

  function pick(r: UserRole) {
    role = r;
    const p = preset(r);
    tabs = new Set(p.tabs); jiraScope = p.jira; e2eScope = p.e2eScope;
  }
  function toggleTab(id: string) { const s = new Set(tabs); if (!s.delete(id)) s.add(id); tabs = s; }

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
  onMount(() => { void refresh(); void reloadE2E(); });

  /** 고른 탭·Jira 목록 기준·E2E 기준·직무를 설정에 적용한다. 직무를 안 골랐으면 아무것도 안 바꾼다. */
  function applyPlan(force = false) {
    if (!role || (applied && !force)) return;
    if (valid) setSetting("enabledTabs", tabsString(tabs));
    const q = jqlFor(jiraScope);
    if (q !== null) setSetting("jiraJQL", q);
    setSetting("e2eIssueScope", e2eScope);
    setSetting("userRole", role);
    applied = true;
  }

  async function setupClaudeAll() {
    busy = true;
    try { await installHook(); await installWorklogSkill(); await installTodoSkill(); } catch { /* 화면에 상태로 보인다 */ }
    await refresh();
    busy = false;
  }

  function finish() {
    applyPlan();
    setSetting("onboardingDone", true);
    void emit("pr-config-changed");
    ondone();
  }
</script>

<div class="pane">
  <div class="steps">
    {#each list as s, i (s)}
      <span class:on={i === step} class:done={i < step}>{i + 1}. {STEP_TITLE[s]}</span>
    {/each}
  </div>

  {#if current === "role"}
    <div class="hint">직무에 맞게 미리 맞춰 둘게요. 아래에서 바로 바꿀 수 있어요. 나중에 설정 &gt; 정보 &gt; 설정 도우미 열기로 다시 할 수 있어요.</div>
    <div class="feats">
      {#each ROLES as r (r.id)}
        <button class="feat" class:on={role === r.id} onclick={() => pick(r.id)}>
          <span class="fi"><Sym name={ROLE_ICON[r.id]} size={1.3} /></span>
          <span class="ft"><b>{r.title}</b><span>{r.desc}</span></span>
          <span class="chk">{#if role === r.id}<Sym name="check-circle" size={1.2} />{/if}</span>
        </button>
      {/each}
    </div>
    {#if role}
      <div class="card-title">이렇게 맞춰 둬요</div>
      <div class="card">
        <div class="srow col">
          <span>쓸 탭</span>
          <div class="tabchips">
            {#each TAB_ORDER as id (id)}
              <button class="chip" class:soft={tabs.has(id)} class:plain={!tabs.has(id)} aria-pressed={tabs.has(id)} onclick={() => toggleTab(id)}>
                <Sym name={tabs.has(id) ? "check" : "plus"} size={0.8} />{TAB_TITLE[id]}
              </button>
            {/each}
          </div>
          {#if !valid}<div class="hint err">탭을 하나 이상 골라 주세요.</div>{/if}
        </div>
        <div class="srow" class:dim={!tabs.has("tasks")}>
          <span>할 일 · Jira 목록</span>
          <Segmented value={jiraScope} onpick={(v) => (jiraScope = v)} options={jiraOptions} />
        </div>
        <div class="srow" class:dim={!tabs.has("e2e")}>
          <span>E2E 이슈 기본</span>
          <Segmented value={e2eScope} onpick={(v) => (e2eScope = v)} options={[{ value: "assignee", label: "담당" }, { value: "reporter", label: "보고" }]} />
        </div>
        <div class="srow col">
          <span>설정 도우미 {list.length}단계</span>
          <div class="hint">{previewLine(list)}</div>
        </div>
      </div>
    {/if}
    <div class="card-title">비밀 정보 저장</div>
    <div class="card">
      <div class="srow">
        <span>저장 위치</span>
        <Segmented value={settings.secretStorage} onpick={(v) => setSetting("secretStorage", v)}
          options={[{ value: "credman", label: "자격 증명 관리자 (권장)" }, { value: "file", label: "파일" }]} />
      </div>
    </div>
  {:else if current === "jira"}
    <JiraPane bind:hasToken={jiraOk} />
  {:else if current === "notes"}
    <NotesPane />
  {:else if current === "summary"}
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
  {:else if current === "pr"}
    <PRPane />
  {:else if current === "e2e"}
    <div class="hint">검증은 내 Aside 브라우저가 해요. 아래 항목을 위에서부터 채우면 돼요. 지금 다 못 해도 탭은 켜 둘 수 있고, E2E 탭에서 이어서 할 수 있어요.</div>
    <div class="card"><div class="srow col"><SetupList items={setupItems()} recheck /></div></div>
    <div class="hint">환경 주소(DV/ST/ST2)와 테스트 계정 ID 는 설정 &gt; E2E 에서 넣어요. 테스트 계정은 주소 옆 'Aside 에서 열기'로 직접 로그인해 Aside Vault 에 저장해요. 비밀번호는 ATM 이 넘기지 않아요.</div>
  {:else if current === "teleport"}
    <div class="card">
      <div class="srow col">
        <div>Teleport 로그인과 DB 고르기는 패널의 Teleport 탭에서 이어서 해요.</div>
        <div class="actions"><button class="btn primary" onclick={() => { applyPlan(); setSetting("lastTab", "teleport"); void emit("teleport-setup-requested"); }}>Teleport 탭 열기</button></div>
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
    {#if current !== "finish"}
      <button class="btn primary" disabled={step === 0 && (!role || !valid)}
        onclick={() => { if (step === 0) applyPlan(true); step += 1; void refresh(); if (!e2e.report) void checkAside(); }}>다음</button>
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
  .tabchips { display: flex; flex-wrap: wrap; gap: 6px; }
  .tabchips .chip { padding: 3px 10px; cursor: pointer; }
  .srow.dim { opacity: 0.45; }
  .hint.err { color: var(--danger); }
</style>
