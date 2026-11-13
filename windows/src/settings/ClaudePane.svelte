<script lang="ts">
  // 설정 > Claude 연동 (Mac claudePane): 활동 훅, /worklog 스킬, atm-todo 스킬.
  import { onMount } from "svelte";
  import { native } from "../lib/native";
  import {
    hookStatus, installHook, removeHook, worklogSkillInstalled, todoSkillInstalled,
    installWorklogSkill, removeWorklogSkill, installTodoSkill, removeTodoSkill, type HookStatus,
  } from "../lib/claude";
  import { parseActivity } from "../lib/summaryCore";

  let hook = $state<HookStatus>("notInstalled");
  let skill = $state(false);
  let todoSkill = $state(false);
  let today = $state(0);
  let error = $state("");
  let note = $state("");

  async function refresh() {
    hook = await hookStatus();
    skill = await worklogSkillInstalled().catch(() => false);
    todoSkill = await todoSkillInstalled().catch(() => false);
    today = parseActivity((await native.readText("activity.jsonl").catch(() => null)) ?? "", new Date()).length;
  }
  onMount(() => { void refresh(); });

  async function act(f: () => Promise<unknown>, done: string) {
    error = ""; note = "";
    try {
      const r = await f();
      note = done + (typeof r === "string" && r ? ` (이전 설정 백업: ${r})` : "");
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    }
    await refresh();
  }

  const hookLabel = $derived(hook === "installed" ? "설치됨" : hook === "pathMismatch" ? "경로 다름 (다시 설치 필요)" : "미설치");
</script>

<div class="pane">
  <h2>Claude 연동</h2>
  <div class="card">
    <div class="srow">
      <div class="grow">
        <div>활동 훅</div>
        <div class="hint">{hookLabel} · 오늘 {today}건</div>
      </div>
      {#if hook === "installed"}
        <button class="btn" onclick={() => act(removeHook, "훅을 뺐어요")}>제거</button>
      {:else}
        <button class="btn primary" onclick={() => act(installHook, "훅을 넣었어요. 새 Claude Code 세션부터 기록해요")}>{hook === "pathMismatch" ? "다시 설치" : "설치"}</button>
      {/if}
    </div>
    <div class="srow">
      <div class="grow">
        <div>/worklog 스킬</div>
        <div class="hint">{skill ? "설치됨" : "미설치"} · Claude Code 에서 /worklog 로 업무 일지를 남겨요</div>
      </div>
      <button class="btn" onclick={() => act(skill ? removeWorklogSkill : installWorklogSkill, skill ? "스킬을 지웠어요" : "스킬을 설치했어요")}>{skill ? "제거" : "설치"}</button>
    </div>
    <div class="srow">
      <div class="grow">
        <div>할 일 추가 스킬 (atm-todo)</div>
        <div class="hint">{todoSkill ? "설치됨" : "미설치"} · "이거 할 일에 추가해줘, 금요일까지" 처럼 말하면 ATM 할 일에 들어가요</div>
      </div>
      <button class="btn" onclick={() => act(todoSkill ? removeTodoSkill : installTodoSkill, todoSkill ? "스킬을 지웠어요" : "스킬을 설치했어요")}>{todoSkill ? "제거" : "설치"}</button>
    </div>
    {#if error}<div class="srow col"><div class="hint err">{error}</div></div>{/if}
    {#if note}<div class="srow col"><div class="hint ok selectable">{note}</div></div>{/if}
  </div>
  <div class="hint">훅·스킬은 이 ATM 실행 파일 경로를 기억해요. 설치 위치를 옮기면 다시 설치해 주세요. ~/.claude/settings.json 은 바꾸기 전에 같은 폴더에 백업해요.</div>
  <div class="actions">
    <button class="btn" onclick={() => native.openDataPath("")}>데이터 폴더 열기</button>
    <button class="btn" onclick={() => native.openDataPath("summaries")}>요약 폴더 열기</button>
    <button class="btn" onclick={() => native.openDataPath("worklog")}>일지 폴더 열기</button>
  </div>
</div>
