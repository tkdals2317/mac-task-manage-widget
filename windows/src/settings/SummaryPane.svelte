<script lang="ts">
  // 설정 > 요약 (Mac summaryPane): 생성 시각·완료 알림, 요약 프롬프트, Claude CLI 모델·경로.
  import { setSetting, settings } from "../lib/settings.svelte";
  import { DEFAULT_INSTRUCTIONS } from "../lib/summaryCore";
  import { locateClaude } from "../lib/claude";

  let draft = $state(settings.summaryInstructions || DEFAULT_INSTRUCTIONS);
  let saved = $state(false);
  let found = $state<{ path: string; source: string } | null | undefined>(undefined);

  const hours = Array.from({ length: 24 }, (_, i) => i);
  const minutes = [0, 10, 15, 20, 30, 40, 45, 50];

  function save() {
    const isDefault = draft.trim() === DEFAULT_INSTRUCTIONS.trim();
    setSetting("summaryInstructions", isDefault ? "" : draft);
    if (isDefault) draft = DEFAULT_INSTRUCTIONS;
    saved = true;
    setTimeout(() => (saved = false), 1500);
  }

  async function find() {
    found = await locateClaude("");
  }
</script>

<div class="pane">
  <h2>요약</h2>
  <div class="card">
    <div class="srow">
      <span>생성 시각</span>
      <div class="actions">
        <select class="field sel" value={settings.summaryHour} onchange={(e) => setSetting("summaryHour", Number(e.currentTarget.value))}>
          {#each hours as h}<option value={h}>{String(h).padStart(2, "0")}</option>{/each}
        </select>
        <span>:</span>
        <select class="field sel" value={settings.summaryMinute} onchange={(e) => setSetting("summaryMinute", Number(e.currentTarget.value))}>
          {#each minutes.includes(settings.summaryMinute) ? minutes : [...minutes, settings.summaryMinute].sort((a, b) => a - b) as m}
            <option value={m}>{String(m).padStart(2, "0")}</option>
          {/each}
        </select>
      </div>
    </div>
    <label class="srow">
      <span>완료 알림</span>
      <input class="switch" type="checkbox" checked={settings.summaryNotify} onchange={(e) => setSetting("summaryNotify", e.currentTarget.checked)} />
    </label>
    <div class="srow col"><div class="hint">패널이 켜져 있는 동안(트레이에 숨겨도 됨) 이 시각에 그날 요약을 만들어요. 꺼져 있던 날은 다음에 켤 때 최근 7일까지 채워요.</div></div>
  </div>

  <div class="card-title">요약 프롬프트</div>
  <div class="card">
    <div class="srow col">
      <textarea class="field mono prompt" bind:value={draft} spellcheck="false"></textarea>
      <div class="actions">
        <button class="btn" onclick={save}>저장</button>
        <button class="btn" onclick={() => { draft = DEFAULT_INSTRUCTIONS; setSetting("summaryInstructions", ""); }}>기본값으로 되돌리기</button>
        {#if saved}<span class="hint ok">저장했어요</span>{/if}
      </div>
      <div class="hint">`{"{날짜}"}`는 그날 날짜로 바뀝니다. 업무 일지·대화 기록·커밋 데이터는 이 지시문 뒤에 자동으로 붙습니다.</div>
    </div>
  </div>

  <div class="card-title">Claude CLI</div>
  <div class="card">
    <div class="srow">
      <span>모델</span>
      <input class="field narrow" placeholder="비우면 CLI 기본" value={settings.claudeModel} onchange={(e) => setSetting("claudeModel", e.currentTarget.value.trim())} />
    </div>
    <div class="srow">
      <span>claude 경로</span>
      <input class="field narrow mono" placeholder="비우면 자동 탐색" value={settings.claudePath} onchange={(e) => setSetting("claudePath", e.currentTarget.value.trim())} />
    </div>
    <div class="srow col">
      <div class="actions"><button class="btn" onclick={find}>자동 찾기</button></div>
      {#if found}
        <div class="hint selectable">찾음: {found.path} ({found.source})</div>
        <div class="actions"><button class="btn" onclick={() => setSetting("claudePath", found!.path)}>이 경로 사용</button></div>
      {:else if found === null}
        <div class="hint warn">찾지 못함. Claude Code 를 설치했다면 PowerShell 에서 <code>(Get-Command claude).Source</code> 결과를 위에 넣어 주세요.</div>
      {/if}
    </div>
  </div>
</div>

<style>
  .sel { width: auto; padding: 3px 6px; }
  .narrow { width: 280px; }
  .prompt { min-height: 220px; font-size: 0.86em; resize: vertical; }
  code { font-family: "Cascadia Mono", Consolas, monospace; font-size: 0.92em; }
</style>
