<script lang="ts">
  // 설정 > E2E (Mac E2ESettingsSections): Aside 준비 점검, 환경 주소·테스트 계정, 모델·제한 시간·보관.
  import { onMount } from "svelte";
  import { openUrl } from "@tauri-apps/plugin-opener";
  import { checkAside, e2e, reload, setupItems } from "../lib/e2e.svelte";
  import { e2eURLKey, e2eUserKey, setSetting, settings } from "../lib/settings.svelte";
  import { selectableEnvs, forcesReadOnly, normalizeEnvURL, webURL, type E2EEnv } from "../lib/e2eCore";
  import { ASIDE_DOWNLOAD_URL } from "../lib/asideCore";
  import { native } from "../lib/native";
  import Segmented from "./Segmented.svelte";
  import SetupList from "../e2e/SetupList.svelte";

  onMount(() => { void reload(); if (!e2e.report) void checkAside(); });
  const items = $derived.by(() => { void e2e.report; return setupItems(); });
  const envs = $derived(selectableEnvs(settings.e2eAllowPR));
  const num = (key: "e2eMinutesPerIssue" | "e2eMaxMinutes" | "e2eMaxIssues", min: number, max: number, raw: string) => {
    const n = Math.round(Number(raw));
    if (Number.isFinite(n)) setSetting(key, Math.min(max, Math.max(min, n)));
  };
  let openErr = $state("");
  async function openEnv(env: E2EEnv) {
    openErr = "";
    const site = webURL(normalizeEnvURL(String(settings[e2eURLKey(env)])));
    if (site) await native.asideOpenUrl(site).catch((e) => (openErr = String(e)));
  }
</script>

<div class="pane">
  <h2>E2E</h2>
  <div class="card-title">Aside 준비</div>
  <div class="card">
    <div class="srow col"><SetupList {items} recheck /></div>
    <div class="srow">
      <span>aside 경로</span>
      <input class="field narrow mono" placeholder="비우면 자동 탐색 (PATH)" value={settings.e2eAsidePath}
        onchange={(e) => { setSetting("e2eAsidePath", e.currentTarget.value.trim()); setTimeout(() => void checkAside(), 400); }} />
    </div>
    {#if e2e.report?.probe}<div class="srow col"><div class="hint selectable">찾은 aside: {e2e.report.probe.path} ({e2e.report.probe.source})</div></div>{/if}
    <div class="srow col">
      <div class="hint">위 목록을 위에서부터 채우면 돼요. Aside 계정은 Aside 브라우저와 CLI 가 같이 써서, 로그인은 Aside 브라우저의 설정 &gt; 계정에서 한 번만 하면 돼요. 검증할 때는 Aside 창이 열려 있어야 하고, 닫혀 있으면 실행할 때 ATM 이 열어요.</div>
      <div class="hint">Windows 에서 Aside 브라우저·CLI 의 설치 위치는 아직 확인하지 못했어요. 자동으로 못 찾으면 위에 aside 경로를 직접 넣어 주세요.</div>
      <div class="hint warn">ATM 은 aside 를 guard 권한으로 실행해요. Aside 에이전트는 Aside 계정 폴더 안의 실행용 폴더(%USERPROFILE%\.aside\u\&lt;계정&gt;\atm-e2e)에서만 파일을 읽고 쓰고, 끝나면 ATM 이 스크린샷 이미지와 result.json 만 골라 가져와요. 다만 Aside 브라우저에 로그인된 사이트는 그대로 쓸 수 있으니 믿을 수 있는 이슈만 검증하세요.</div>
      <div class="actions"><button class="btn" onclick={() => openUrl(ASIDE_DOWNLOAD_URL)}>Aside 다운로드 ↗</button></div>
    </div>
  </div>

  <div class="card-title">환경</div>
  <div class="card">
    {#each envs as env (env)}
      {@const key = e2eURLKey(env)}
      {@const site = webURL(normalizeEnvURL(String(settings[key])))}
      <div class="srow">
        <span class="lbl">{env} 주소</span>
        <span class="actions grow">
          <input class="field mono" placeholder="https://{env.toLowerCase()}.example.com" value={String(settings[key])}
            onchange={(e) => setSetting(key, normalizeEnvURL(e.currentTarget.value))} />
          <button class="btn" disabled={!site} title="Aside 브라우저에서 이 환경을 열어 직접 로그인하고 Aside Vault 에 저장해 두세요" onclick={() => openEnv(env)}>Aside 에서 열기</button>
        </span>
      </div>
      <div class="srow">
        <span class="lbl">{env} 계정 ID</span>
        <input class="field grow" placeholder="비우면 Aside 에 저장된 로그인" value={String(settings[e2eUserKey(env)])}
          onchange={(e) => setSetting(e2eUserKey(env), e.currentTarget.value.trim())} />
      </div>
      {#if forcesReadOnly(env)}<div class="srow col"><div class="hint">PR 환경은 조회만 하라고 지시해요 (쓰기 동작은 SKIPPED)</div></div>{/if}
    {/each}
    {#if openErr}<div class="srow col"><div class="hint err">{openErr}</div></div>{/if}
    <label class="srow">
      <span>PR(운영) 환경 쓰기</span>
      <input class="switch" type="checkbox" checked={settings.e2eAllowPR} onchange={(e) => setSetting("e2eAllowPR", e.currentTarget.checked)} />
    </label>
    <div class="srow col">
      <div class="hint" class:warn={settings.e2eAllowPR}>기본은 꺼져 있어요. 켜면 E2E 탭에 PR 이 보이고 실행 전에 한 번 더 물어요. '조회만' 은 Aside 에 주는 지시로만 지켜지니 운영 데이터가 바뀌어도 괜찮은 경우에만 켜세요.</div>
      <div class="hint">테스트 계정 비밀번호는 ATM 이 Aside 에 넘기지 않아요. 환경마다 한 번, 주소 옆 'Aside 에서 열기'로 환경을 열어 직접 로그인하고 저장할지 물으면 Aside Vault 에 저장해 두세요 (Vault 가 없으면 이때 만들어요). 그러면 Aside 가 자동 채우기로 로그인해요. Vault 가 잠기면 로그인이 막히니 실행 전에 풀어 두세요. 계정 ID 를 넣으면 그 계정으로 로그인하라고 알려주고, Vault 에 저장된 계정과 다르면 결과 화면에서 알려줘요.</div>
    </div>
  </div>

  <div class="card-title">실행</div>
  <div class="card">
    <div class="srow">
      <span>모델</span>
      <input class="field narrow" placeholder="비우면 Aside 기본 · 예: claude-sonnet-5" value={settings.e2eModel} onchange={(e) => setSetting("e2eModel", e.currentTarget.value.trim())} />
    </div>
    <div class="srow col"><div class="hint">E2E 탭 실행 버튼 옆 메뉴에서도 고를 수 있어요. 메뉴에 없는 모델(provider/model)은 여기에 직접 넣어요.</div></div>
    <div class="srow"><span>이슈당 제한 시간 (분)</span><input class="field num" type="number" min="1" max="30" value={settings.e2eMinutesPerIssue} onchange={(e) => num("e2eMinutesPerIssue", 1, 30, e.currentTarget.value)} /></div>
    <div class="srow"><span>최대 제한 시간 (분)</span><input class="field num" type="number" min="5" max="120" step="5" value={settings.e2eMaxMinutes} onchange={(e) => num("e2eMaxMinutes", 5, 120, e.currentTarget.value)} /></div>
    <div class="srow"><span>한 번에 최대 (건)</span><input class="field num" type="number" min="1" max="20" value={settings.e2eMaxIssues} onchange={(e) => num("e2eMaxIssues", 1, 20, e.currentTarget.value)} /></div>
    <div class="srow">
      <span>결과 보관</span>
      <Segmented value={settings.e2eRetentionDays} onpick={(v) => setSetting("e2eRetentionDays", v)}
        options={[{ value: 7, label: "7일" }, { value: 30, label: "30일" }, { value: 90, label: "90일" }, { value: 0, label: "지우지 않음" }]} />
    </div>
    <div class="srow col">
      <div class="hint">검증은 한 번에 하나씩 돌고, 실행 중에 요청하면 대기열에 쌓여요.</div>
      <div class="actions"><button class="btn" onclick={() => native.openDataPath("e2e/jobs", false)}>결과 폴더 열기</button></div>
    </div>
  </div>
</div>

<style>
  .narrow { width: 300px; }
  .num { width: 80px; text-align: right; }
  .lbl { flex: none; min-width: 90px; }
  .grow { flex: 1; min-width: 0; }
  .actions.grow { flex-wrap: nowrap; }
</style>
