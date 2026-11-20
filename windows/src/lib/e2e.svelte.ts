// E2E 탭 상태 (Mac E2EModel + E2EJobStore + E2ERunner). job 기록은 디스크(데이터 폴더 e2e/jobs/<id>/)가 원본이고,
// 실행 중·대기 상태는 이 모듈의 러너가 원본이다 (패널 창에서만 startE2E 로 켠다. 설정 창은 Aside 점검·준비 목록만 쓴다).
// aside 는 한 번에 하나씩 돌린다 (브라우저를 같이 쓰므로). 프로세스는 Rust 가 들고(터널과 같은 방식) 출력은 run.log 로 바로 간다.
import { openUrl } from "@tauri-apps/plugin-opener";
import { log, native, writeJSON } from "./native";
import { ALL_TABS, e2eURLKey, e2eUserKey, enabledTabs, setSetting, settings, toggledTabs } from "./settings.svelte";
import { addAttachment, addComment, downloadAttachment, fetchIssueDetail, isImageAttachment, mediaFileId, normalizeBase, JiraError } from "./jira";
import { creds } from "../tasks/jiraState.svelte";
import {
  ASIDE_DOWNLOAD_URL, asideEnv, blocker, execArguments, latestVersionOf, modelNames, parseAccountStatus, parseConnectedModels, parseModels,
  parseOtherAccounts, parsePlainAccountStatus, parseWindowOpen, runOutcome, sessionIdInLog, setupItems as buildSetupItems, isUnknownOption,
  type AsideModel, type AsideProbe, type LoginHistory, type SetupFix, type SetupItem,
} from "./asideCore";
import {
  attachmentImagePath, buildRequest, isActive, isoString, issueFilePath, issueMarkdown, issueKeys as jobIssueKeys, jiraURL, jobIdValid, jobToJSON,
  latestVerdicts, localStamp, makeJobId, MAX_IMAGE_BYTES, MAX_IMAGES, newJob, normalizeEnvURL, parseJob, parseResult, renderPrompt, runTimeoutMs, screenshotNames, webURL,
  type E2EEnv, type IssueRef, type IssueResult, type Job, type JobStatus, type Result, type ResultLoad, type Verdict,
} from "./e2eCore";
import { attachmentName, commentDocument, mimeOf, reportFileName, reportHtml, type ReportImage } from "./e2eReport";

export interface AsideReport { browserInstalled: boolean; browserVersion: string; probe: AsideProbe | null }

export const e2e = $state({
  jobs: [] as Job[],
  results: {} as Record<string, ResultLoad>,
  /** 이슈 키 → 가장 최근 판정 (Jira 목록 뱃지) */
  verdictByKey: {} as Record<string, { verdict: Verdict; jobId: string }>,
  running: null as string | null,
  runningSince: null as number | null,
  queued: [] as string[],
  report: null as AsideReport | null,
  checking: false,
  models: [] as AsideModel[],
  plan: "",
  submitting: false,
  exporting: false,
  /** Jira 댓글을 남기는 중인 대상 (jobId/키) */
  commenting: null as string | null,
  commentNote: null as { id: string; text: string } | null,
  submitError: null as string | null,
  setupError: null as string | null,
  /** 결과 상세로 열린 job. null 이면 목록. */
  openJobId: null as string | null,
  /** 요청 화면에서 고르고 쓰던 것. 결과를 보거나 탭을 옮겨도 남게 모듈에 둔다. */
  draftSelected: [] as string[],
  draftKeys: "",
  draftNotes: "",
});

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const errText = (e: unknown) => (e instanceof JiraError ? e.userMessage : e instanceof Error ? e.message : String(e));

// ---------------------------------------------------------------- job 기록 (디스크)
const jobFile = (id: string) => `e2e/jobs/${id}/job.json`;
const resultFile = (id: string) => `e2e/jobs/${id}/result.json`;
const pidFile = (id: string) => `e2e/jobs/${id}/run.pid`;
const logPath = (id: string) => `e2e/jobs/${id}/run.log`;

/** 데이터 폴더 안 경로 (탐색기에 넘길 절대 경로). */
async function absPath(...parts: string[]): Promise<string> {
  const d = await native.dataDir();
  return [d, ...parts].join(d.includes("\\") ? "\\" : "/");
}

async function loadJob(id: string): Promise<Job | null> {
  const raw = await native.readText(jobFile(id)).catch(() => null);
  if (raw == null) return null;
  try { return parseJob(JSON.parse(raw)); } catch { return null; }
}

async function listJobs(): Promise<Job[]> {
  const ids = (await native.listSubdirs(await absPath("e2e", "jobs")).catch(() => [])).filter(jobIdValid);
  const jobs = (await Promise.all(ids.map(loadJob))).filter((j): j is Job => j !== null);
  return jobs.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
}

async function loadResult(id: string): Promise<ResultLoad> {
  const raw = await native.readText(resultFile(id)).catch(() => null);
  return raw == null ? { kind: "missing" } : parseResult(raw);
}

/** job.json 의 키만 바꾼다. 모르는 키는 그대로 둔다. */
async function patchJob(id: string, set: Record<string, unknown> = {}, remove: string[] = []): Promise<void> {
  const raw = await native.readText(jobFile(id));
  const obj = raw ? JSON.parse(raw) : null;
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) throw new Error("job.json 이 깨졌어요");
  Object.assign(obj, set);
  for (const k of remove) delete obj[k];
  await writeJSON(jobFile(id), obj);
}

/** 실행이 끝난 job 을 마무리한다: 상태·오류·종료 시각을 쓴다. job.json 이 깨졌거나 없어졌으면 메모리의 job 으로 다시 쓴다. */
async function finishJob(job: Job, status: JobStatus, error: string | null, sessionId: string | null): Promise<Job> {
  const now = new Date();
  const cur = (await loadJob(job.id)) ?? job;
  const out: Job = { ...cur, status, finishedAt: now, error, sessionId: sessionId ?? cur.sessionId };
  try {
    await patchJob(job.id, { status, finishedAt: isoString(now), ...(error ? { error } : {}), ...(out.sessionId ? { sessionId: out.sessionId } : {}) }, error ? [] : ["error"]);
  } catch {
    await writeJSON(jobFile(job.id), jobToJSON(out));
  }
  await native.deleteFile(pidFile(job.id)).catch(() => {});
  return out;
}

const logNote = (id: string, line: string) => native.e2eLogAppend(id, `[ATM ${new Date().toISOString()}] ${line}`).catch(() => {});

// ---------------------------------------------------------------- 화면용 읽기
let reloadSeq = 0;
export async function reload(): Promise<void> {
  const seq = ++reloadSeq;
  const list = await listJobs();
  const results: Record<string, ResultLoad> = {};
  const entries: { job: Job; result: Result }[] = [];
  for (const j of list) {
    if (isActive(j.status)) continue;
    const res = await loadResult(j.id);
    results[j.id] = res;
    if (j.status === "done" && res.kind === "ok") entries.push({ job: j, result: res.result });
  }
  if (seq !== reloadSeq) return; // 더 나중 요청이 있으면 버린다
  e2e.jobs = list;
  e2e.results = results;
  e2e.verdictByKey = latestVerdicts(entries);
  syncRunner();
  if (e2e.openJobId && !list.some((j) => j.id === e2e.openJobId)) e2e.openJobId = null;
}

function syncRunner() {
  const r = current?.job.id ?? null;
  if (r !== e2e.running) e2e.runningSince = r === null ? null : Date.now();
  e2e.running = r;
  e2e.queued = pending.map((p) => p.job.id);
}

export const job = (id: string) => e2e.jobs.find((j) => j.id === id);
export const isRunning = (id: string) => e2e.running === id || e2e.queued.includes(id);
/** 모델 id → 메뉴에 보일 이름 (모르는 id 는 그대로). */
export const modelName = (id: string | null | undefined) => (!id ? "Aside 기본 모델" : e2e.models.find((m) => m.id === id)?.name ?? id);

/** 이 job 의 Jira 이슈 주소. ATM 이 만든 https 주소 중 지금 설정한 Jira 와 호스트가 같은 것만. */
export function issueLink(ref: IssueRef): string | null {
  const base = normalizeBase(settings.jiraBaseURL);
  return base ? jiraURL(ref.url, base) : null;
}

export const openResult = (jobId: string) => { e2e.openJobId = jobId; setSetting("lastTab", "e2e"); };

// ---------------------------------------------------------------- 시작·정리
/** 앱 시작 때: 지난 실행이 남긴 상태를 닫고 오래된 job 을 지운다. 패널 창에서 한 번 부른다. */
export async function startE2E(): Promise<void> {
  introduceTab();
  const launched = new Date();
  try {
    await recoverOnLaunch(launched);
    await pruneOld(settings.e2eRetentionDays);
    for (const id of await native.e2eWorkPrune(localStamp(launched))) log(`e2e: 남은 실행용 폴더 정리 (${id})`);
  } catch (e) { log(`e2e start error: ${errText(e)}`); }
  await reload();
}

/** E2E 탭이 생긴 버전으로 처음 올라온 사용자에게 탭을 한 번 켜 준다. 이후 끄면 다시 켜지 않는다. 처음 설치하는 사람은 설정 도우미에서 고른다. */
function introduceTab() {
  if (settings.e2eTabIntroduced) return;
  setSetting("e2eTabIntroduced", true);
  if (settings.onboardingDone && !enabledTabs(settings.enabledTabs, ALL_TABS).includes("e2e")) {
    setSetting("enabledTabs", toggledTabs("e2e", settings.enabledTabs, ALL_TABS));
  }
}

/** 끝나지 못한 job 을 닫는다. 실행 중이던 것은 failed, 대기 중이던 것은 cancelled. 남은 aside 프로세스·세션도 멈춘다. */
async function recoverOnLaunch(launched: Date): Promise<void> {
  const stampCutoff = launched.getTime();
  for (const j of await listJobs()) {
    if (j.createdAt.getTime() >= stampCutoff) continue; // 이번 실행에서 벌써 요청한 것
    const pid = Number((await native.readText(pidFile(j.id)).catch(() => null))?.trim());
    await native.deleteFile(pidFile(j.id)).catch(() => {});
    if (!isActive(j.status)) continue;
    const interrupted = j.status === "running";
    await patchJob(j.id, {
      status: interrupted ? "failed" : "cancelled",
      error: interrupted ? "ATM 이 종료되어 실행이 중단됐어요" : "ATM 이 종료되어 대기 중인 요청을 취소했어요",
      finishedAt: isoString(new Date()),
    }).catch(() => {});
    if (Number.isInteger(pid) && pid > 0 && (await native.killPidIfAside(pid).catch(() => false))) log(`e2e: 남은 aside 프로세스 종료 (${j.id})`);
    const sid = interrupted ? sessionIdInLog(await native.e2eLogText(j.id).catch(() => "")) : null;
    if (sid) {
      const exe = (await native.which("aside", settings.e2eAsidePath).catch(() => null))?.[0];
      if (exe) { await stopSession(exe, sid); log(`e2e: 남은 Aside 세션 정지 (${j.id} ${sid})`); }
    }
  }
}

/** 만든 지 days 일이 지난 job 폴더를 지운다 (실행 중인 것은 둔다). days 가 0 이하면 아무것도 안 한다. */
async function pruneOld(days: number): Promise<void> {
  if (days <= 0) return;
  const cutoff = Date.now() - days * 86_400_000;
  for (const j of await listJobs()) {
    if (!isActive(j.status) && j.createdAt.getTime() < cutoff) await native.e2eJobDelete(j.id).catch(() => {});
  }
}

// ---------------------------------------------------------------- Aside 준비 점검
async function asideRun(exe: string, args: string[], timeoutMs = 15_000): Promise<{ text: string; status: number } | null> {
  const r = await native.run(exe, args, { timeoutMs, env: asideEnv() }).catch(() => null);
  if (!r || r.timedOut) return null;
  const out = r.stdout.trim();
  return { text: out || r.stderr.trim(), status: r.code };
}

async function accountStatus(exe: string): Promise<AsideProbe["account"]> {
  const timeout = { kind: "unknown", message: "aside 응답 없음 (15초)" } as const;
  const r = await asideRun(exe, ["account", "status", "--json"]);
  if (!r) return timeout;
  // 구버전 CLI 는 --json 이 없어 일반 출력으로 다시 본다.
  if (!isUnknownOption(r.text)) return parseAccountStatus(r.text, r.status);
  const plain = await asideRun(exe, ["account", "status"]);
  return plain ? parsePlainAccountStatus(plain.text) : timeout;
}

/** Aside 브라우저 창이 열려 있는가 (`aside host profiles`). 확인하지 못하면 null. */
async function windowOpen(exe: string): Promise<boolean | null> {
  const r = await asideRun(exe, ["host", "profiles", "--json"]);
  if (!r) return null;
  if (!isUnknownOption(r.text)) return parseWindowOpen(r.text);
  const plain = await asideRun(exe, ["host", "profiles"]);
  return plain && !isUnknownOption(plain.text) ? parseWindowOpen(plain.text) : null;
}

/** 찾은 aside 로 준비 상태를 한 번에 살펴본다 (버전·실행 가능 여부·계정·다른 계정·창). */
async function probeAside(path: string, source: string): Promise<AsideProbe> {
  const v = await asideRun(path, ["--version"]);
  const version = v && v.status === 0 ? v.text.split(/\r?\n/)[0] : "";
  // 도움말을 못 읽었으면 막지 않는다 (실행해서 실패하면 그때 알려 준다).
  const help = await asideRun(path, ["exec", "--help"]);
  const runnable = help ? help.status !== 0 || help.text.includes("--permission") : true;
  const account = await accountStatus(path);
  const probe: AsideProbe = {
    path, source, version, latestVersion: latestVersionOf(await native.asideRead("cli/update-check.json").catch(() => null)),
    runnable, account, otherAccounts: [], windowOpen: null,
  };
  if (account.kind === "unknown") return probe;
  const list = await asideRun(path, ["account", "list", "--json"]);
  probe.otherAccounts = list ? parseOtherAccounts(list.text) : [];
  if (account.kind === "signedIn") probe.windowOpen = await windowOpen(path);
  return probe;
}

const diagLine = (r: AsideReport): string => {
  const p = r.probe;
  if (!p) return `browser=${r.browserInstalled ? "있음" : "없음"} cli=없음`;
  const a = p.account;
  const account = a.kind === "signedIn" ? `signedIn(u${a.accountId})` : a.kind === "signedOut" ? `signedOut(${a.reason.kind})` : `unknown(${a.message.replace(/[^\s@]+@[^\s@]+/g, "<이메일>")})`;
  return `browser=${r.browserInstalled ? "있음" : "없음"} cli=${p.version}(${p.source}, 최신 ${p.latestVersion}) runnable=${p.runnable} account=${account} others=${p.otherAccounts.length} window=${p.windowOpen ?? "?"}`;
};

let checkTask: Promise<void> | null = null;
/** quiet: 확인 중 표시 없이 결과만 바꾼다 (사용자를 기다리며 반복 확인할 때, 실행 직전). 이미 점검 중이면 그 점검이 끝나기를 기다린다. */
export async function checkAside(quiet = false): Promise<void> {
  if (checkTask) return checkTask;
  checkTask = runCheck(quiet).finally(() => { checkTask = null; });
  return checkTask;
}

async function runCheck(quiet: boolean): Promise<void> {
  if (!quiet) e2e.checking = true;
  try {
    const found = await native.which("aside", settings.e2eAsidePath).catch(() => null);
    const probe = found ? await probeAside(found[0], found[1]) : null;
    const next: AsideReport = { browserInstalled: (await native.asideBrowser().catch(() => null)) != null, browserVersion: "", probe };
    if (JSON.stringify(next) !== JSON.stringify(e2e.report)) log(`e2e aside: ${diagLine(next)}`);
    e2e.report = next;
    if (probe?.account.kind === "signedIn") {
      e2e.plan = probe.account.plan;
      const id = probe.account.accountId;
      const [cache, connected] = await Promise.all([native.asideRead(`u/${id}/cache/models.json`).catch(() => null), native.asideRead(`u/${id}/models.json`).catch(() => null)]);
      e2e.models = [...(cache ? parseModels(cache) : []), ...(connected ? parseConnectedModels(connected, cache ? modelNames(cache) : {}) : [])];
    }
  } finally {
    e2e.checking = false;
  }
}

/** 실행에 쓸 aside 경로와 Aside 계정 번호. 준비가 안 됐으면 null. */
export function runTarget(): { path: string; accountId: number } | null {
  const p = e2e.report?.probe;
  return p && p.runnable && p.account.kind === "signedIn" ? { path: p.path, accountId: p.account.accountId } : null;
}
export const asideReady = () => runTarget() !== null;

/** 고른 환경의 지난 검증에서 로그인이 어땠는지 (같은 환경·주소로 끝난 가장 최근 검증). */
export function loginHistory(env: E2EEnv, baseUrl: string): LoginHistory {
  const last = e2e.jobs.find((j) => j.status === "done" && j.env === env && j.baseUrl === baseUrl && e2e.results[j.id]?.kind === "ok");
  const res = last ? e2e.results[last.id] : null;
  if (!last || res?.kind !== "ok") return { kind: "none" };
  if (res.result.loginBlocked) return { kind: "blocked", block: res.result.loginBlocked };
  // 전부 BLOCKED 면 로그인까지 갔는지 알 수 없다
  return res.result.issues.some((i) => i.verdict !== null && i.verdict !== "BLOCKED") ? { kind: "ok" } : { kind: "none" };
}

/** 준비 항목. env 를 주면 그 환경의 주소·로그인 항목까지 본다 (설정에 넣은 값 그대로). */
export function setupItems(env: E2EEnv | null = null): SetupItem[] {
  const r = e2e.report;
  if (!r) return [];
  const base = env ? normalizeEnvURL(String(settings[e2eURLKey(env)])) : "";
  return buildSetupItems({
    browserInstalled: r.browserInstalled, browserVersion: r.browserVersion, probe: r.probe, env, envURL: base,
    envUser: env ? String(settings[e2eUserKey(env)]).trim() : "", lastLogin: env ? loginHistory(env, base) : { kind: "none" },
  });
}

let watching = 0;
/** 사용자가 Aside·터미널에서 할 일을 마칠 때까지 3초마다 조용히 다시 확인한다. done 이 true 가 되면 멈춘다. */
function watchAside(minutes: number, done: (r: AsideReport) => boolean) {
  const me = ++watching;
  void (async () => {
    for (let i = 0; i < minutes * 20; i++) {
      await sleep(3000);
      if (me !== watching) return;
      await checkAside(true);
      if (e2e.report && done(e2e.report)) return;
    }
  })();
}

/** 준비 항목의 버튼. env 는 환경을 여는 동작에만 쓴다. */
export async function perform(fix: SetupFix, env: E2EEnv | null = null): Promise<void> {
  e2e.setupError = null;
  const probe = e2e.report?.probe ?? null;
  const fail = (e: unknown) => { e2e.setupError = errText(e); };
  switch (fix.kind) {
    case "downloadBrowser":
    case "installCLI":
      await openUrl(ASIDE_DOWNLOAD_URL).catch(fail);
      watchAside(10, (r) => r.browserInstalled || r.probe !== null);
      break;
    case "updateCLI":
      if (!probe) { await openUrl(ASIDE_DOWNLOAD_URL).catch(fail); watchAside(10, (r) => r.probe !== null); break; }
      await native.asideTerminal(probe.path, "update").catch(fail);
      if (!e2e.setupError) { const before = probe.version; watchAside(5, (r) => r.probe?.version !== before); }
      break;
    case "loginCLI":
      if (!probe) return;
      await native.asideTerminal(probe.path, "login").catch(fail);
      if (!e2e.setupError) watchAside(5, (r) => r.probe?.account.kind === "signedIn");
      break;
    case "openAside":
      await native.asideLaunch().catch(() => { e2e.setupError = "Aside 브라우저를 직접 열어 주세요 (설치 위치를 찾지 못했어요)"; });
      watchAside(5, (r) => r.probe?.account.kind === "signedIn" && r.probe.windowOpen !== false);
      break;
    case "switchAccount": {
      if (!probe) return;
      const r = await asideRun(probe.path, ["account", "use", `u${fix.id}`]);
      e2e.setupError = !r ? "aside 응답 없음 (15초)" : r.status === 0 ? null : `계정을 바꾸지 못했어요 · ${r.text.split(/\r?\n/).pop() || `exit ${r.status}`}`;
      await checkAside();
      break;
    }
    case "openSettings":
      await native.openSettings("e2e").catch(() => {});
      break;
    case "openEnvironment": {
      const site = env ? webURL(normalizeEnvURL(String(settings[e2eURLKey(env)]))) : null;
      if (site) await native.asideOpenUrl(site).catch(fail);
      break;
    }
  }
}

/** 환경 주소를 Aside 브라우저로 연다 (직접 로그인해 Aside Vault 에 저장하는 용도). */
export const openInAside = (url: string) => native.asideOpenUrl(url);

/** Aside 창이 닫혀 있으면 실행이 바로 실패한다. Aside 를 열고 창이 연결될 때까지 잠깐 기다린다. */
async function openAsideWindow(exe: string): Promise<boolean> {
  await native.asideLaunch().catch(() => {});
  for (let i = 0; i < 15; i++) {
    await sleep(1000);
    // 확인하지 못한 경우(null)는 막지 않고 실행에 맡긴다
    if ((await windowOpen(exe)) !== false) { if (e2e.report?.probe) e2e.report.probe.windowOpen = true; return true; }
  }
  return false;
}

async function stopSession(exe: string, id: string): Promise<void> {
  await asideRun(exe, ["session", "stop", id]);
}

// ---------------------------------------------------------------- 요청
/** 요청 화면의 초안으로 실행한다. 성공하면 초안을 비운다. */
export async function submit(env: E2EEnv, keys: string[], notes: string, titles: Record<string, string>): Promise<boolean> {
  if (!(await enqueueJob(env, keys, notes, titles))) return false;
  e2e.draftSelected = []; e2e.draftKeys = ""; e2e.draftNotes = "";
  return true;
}

/** 끝난 job 을 같은 환경·이슈·추가 요청사항으로 다시 실행한다. 모델과 환경 주소는 지금 설정을 쓴다. */
export async function retry(id: string): Promise<boolean> {
  const j = job(id);
  if (!j || isRunning(id)) return false;
  return enqueueJob(j.env, jobIssueKeys(j), j.notes, Object.fromEntries(j.issues.map((i) => [i.key, i.title])));
}

/** 검증 요청을 만들고 대기열에 넣는다. titles 는 아는 제목 (모르면 빈 값으로 넘긴다). */
async function enqueueJob(env: E2EEnv, keys: string[], notes: string, titles: Record<string, string>): Promise<boolean> {
  e2e.submitError = null;
  const s = settings;
  const maxIssues = Math.min(20, Math.max(1, s.e2eMaxIssues));
  if (!keys.length) { e2e.submitError = "검증할 이슈를 고르거나 키를 입력하세요"; return false; }
  if (keys.length > maxIssues) { e2e.submitError = `한 번에 ${maxIssues}건까지 실행할 수 있어요 (설정 > E2E 에서 바꿀 수 있어요)`; return false; }
  if (env === "PR" && !s.e2eAllowPR) { e2e.submitError = "PR(운영) 환경은 설정 > E2E 에서 켜야 실행할 수 있어요"; return false; }
  const base = normalizeEnvURL(String(s[e2eURLKey(env)]));
  if (!base) { e2e.submitError = `${env} 환경 주소를 설정 > E2E 에 입력하세요`; return false; }
  if (e2e.submitting) return false;
  e2e.submitting = true;
  try {
    // 실행 직전 상태로 다시 본다 (그사이 로그아웃했거나 Aside 창을 닫았을 수 있다)
    await checkAside(true);
    const target = runTarget();
    if (!target) { e2e.submitError = blocker(setupItems())?.detail ?? "Aside 준비 상태를 확인하지 못했어요 · '다시 확인'을 눌러 주세요"; return false; }
    if (e2e.report?.probe?.windowOpen === false && !(await openAsideWindow(target.path))) {
      e2e.submitError = "Aside 브라우저 창을 열지 못했어요 · Aside 를 직접 연 뒤 다시 실행해 주세요";
      return false;
    }

    // 비밀번호는 넘기지 않는다. 로그인은 Aside Vault 나 이미 로그인된 세션으로 한다.
    const user = String(s[e2eUserKey(env)]).trim();
    const jiraBase = normalizeBase(s.jiraBaseURL) ?? "";
    const id = makeJobId();
    const { files, notes: logNotes } = await prepareIssueFiles(keys, id, jiraBase);
    const issues: IssueRef[] = keys.map((key) => ({
      key, url: jiraBase ? `${jiraBase}/browse/${key}` : "", title: files[key]?.title ?? titles[key] ?? "", ...(files[key] ? { detailFile: files[key].path } : {}),
    }));
    const model = s.e2eModel.trim();
    const j = newJob({ id, env, baseUrl: base, username: user, issues, notes: notes.trim(), requestedBy: s.jiraEmail, model });
    try {
      await writeJSON(jobFile(id), jobToJSON(j));
    } catch (e) { e2e.submitError = `요청 파일을 만들지 못했어요: ${errText(e)}`; return false; }
    const workDir = await native.asideWorkDir(target.accountId, id);
    enqueueRun(j, {
      exe: target.path, args: execArguments(renderPrompt(workDir), model), env: asideEnv(), accountId: target.accountId,
      timeoutMs: runTimeoutMs(keys.length, s.e2eMinutesPerIssue, s.e2eMaxMinutes), logNotes,
    });
    log(`e2e submit ${id} env=${env} issues=${keys.length} model=${model || "기본"}`);
    await reload();
    return true;
  } finally {
    e2e.submitting = false;
  }
}

/** Aside 브라우저가 Jira 2단계 인증에 막히지 않게, ATM 의 Jira 토큰으로 이슈 내용을 받아 job 폴더에 써 둔다.
 * 토큰이 없거나 실패한 이슈는 파일 없이 두고(브라우저로 연다) 이유를 run.log 에 남긴다. */
async function prepareIssueFiles(keys: string[], jobId: string, jiraBase: string): Promise<{ files: Record<string, { path: string; title: string }>; notes: string[] }> {
  const c = jiraBase ? await creds().catch(() => null) : null;
  if (!c) return { files: {}, notes: ["Jira 연결 정보나 토큰이 없어 이슈는 Aside 브라우저로 열어요"] };
  const files: Record<string, { path: string; title: string }> = {};
  const notes: string[] = [];
  const enc = new TextEncoder();
  for (const key of keys) {
    try {
      const d = await fetchIssueDetail(c, key);
      const saved: Record<string, string> = {};
      let count = 0;
      for (const a of d.attachments) {
        if (!isImageAttachment(a) || a.size > MAX_IMAGE_BYTES || count >= MAX_IMAGES) continue;
        const data = await downloadAttachment(c, a).catch(() => null);
        if (!data || data.length > MAX_IMAGE_BYTES) continue;
        const rel = attachmentImagePath(key, a);
        await native.e2eJobWrite(jobId, rel, data);
        saved[a.id] = rel; count++;
      }
      const path = issueFilePath(key);
      await native.e2eJobWrite(jobId, path, enc.encode(issueMarkdown(d, saved, `${jiraBase}/browse/${key}`)));
      files[key] = { path, title: d.summary };
      notes.push(`Jira ${key}: API 로 받음 (댓글 ${d.comments.length}, 이미지 ${count})`);
    } catch (e) {
      notes.push(`Jira ${key}: 받지 못해 브라우저로 열어요 (${errText(e)})`);
      log(`e2e jira ${key} 받기 실패: ${errText(e)}`);
    }
  }
  return { files, notes };
}

// ---------------------------------------------------------------- 러너 (한 번에 하나)
interface RunOptions { exe: string; args: string[]; env: Record<string, string>; accountId: number; timeoutMs: number; logNotes: string[] }
interface Run { job: Job; opts: RunOptions; cancelled: boolean; cancelReason: string | null; timedOut: boolean; stopped: boolean }
let current: Run | null = null;
const pending: { job: Job; opts: RunOptions }[] = [];

function enqueueRun(j: Job, opts: RunOptions) {
  pending.push({ job: j, opts });
  syncRunner();
  pump();
}

function pump() {
  if (current || !pending.length) return;
  const next = pending.shift()!;
  current = { job: next.job, opts: next.opts, cancelled: false, cancelReason: null, timedOut: false, stopped: false };
  syncRunner();
  void runCurrent(current).catch((e) => log(`e2e runner error: ${errText(e)}`));
}

/** 대기 중이면 빼고 cancelled 로, 실행 중이면 프로세스를 멈춘다. */
export async function cancelJob(id: string): Promise<void> {
  if (current?.job.id === id) {
    current.cancelled = true;
    await logNote(id, "사용자가 취소");
    await stopProcess(current);
    return;
  }
  const i = pending.findIndex((p) => p.job.id === id);
  if (i >= 0) {
    const [p] = pending.splice(i, 1);
    await finishJob(p.job, "cancelled", null, null);
    await reload();
  }
}

/** 프로세스 트리를 끝낸다 (Windows 에는 SIGTERM 이 없어 바로 강제 종료). 세션은 finalize 에서 따로 멈춘다. */
async function stopProcess(r: Run) {
  if (r.stopped) return;
  r.stopped = true;
  await native.tunnelStop(`e2e-${r.job.id}`).catch(() => {});
}

async function runCurrent(r: Run): Promise<void> {
  const { job: j, opts: o } = r;
  const key = `e2e-${j.id}`;
  await logNote(j.id, `시작 env=${j.env} issues=${jobIssueKeys(j).join(",")} timeout=${Math.floor(o.timeoutMs / 1000)}s`);
  await logNote(j.id, `실행 ${o.exe} ${o.args.slice(0, -1).join(" ")} <지시문>`);
  for (const n of o.logNotes) await logNote(j.id, n);
  const fail = async (message: string) => {
    await logNote(j.id, message);
    await native.e2eWorkImport(o.accountId, j.id).catch(() => []); // 실행용 폴더 정리
    await closeRun(r, "failed", message, null);
  };
  try {
    await native.e2eWorkPrepare(o.accountId, j.id, JSON.stringify(buildRequest(j), null, 2));
    await patchJob(j.id, { status: "running" });
  } catch (e) { return fail(`요청 파일을 쓰지 못했어요: ${errText(e)}`); }

  let pid: number;
  try {
    pid = await native.tunnelSpawn(key, o.exe, o.args, logPath(j.id), o.env);
  } catch (e) { return fail(`aside 를 실행하지 못했어요: ${errText(e)}`); }
  await native.writeText(pidFile(j.id), String(pid)).catch(() => {});
  await logNote(j.id, `pid ${pid}`);
  void reload();

  const deadline = Date.now() + o.timeoutMs;
  let exitCode = -1;
  for (;;) {
    await sleep(1000);
    if (r.stopped) break; // 취소·시간 초과로 우리가 끝냈다
    const code = await native.tunnelExit(key).catch(() => -1);
    if (code !== null) { exitCode = code; break; }
    if (Date.now() >= deadline) {
      r.timedOut = true;
      await logNote(j.id, `제한 시간 ${Math.floor(o.timeoutMs / 1000)}s 초과 → 중지`);
      await stopProcess(r);
      break;
    }
  }

  const output = await native.e2eLogText(j.id).catch(() => "");
  const sessionId = sessionIdInLog(output);
  await logNote(j.id, `종료 exit=${exitCode}${sessionId ? ` session=${sessionId}` : ""}`);
  // 강제 종료로 끝난 CLI 는 Aside 세션을 멈추지 못하니 세션을 따로 멈춘다.
  if (r.stopped && sessionId) void stopSession(o.exe, sessionId);
  const skipped = await native.e2eWorkImport(o.accountId, j.id).catch(() => [] as string[]);
  if (skipped.length) await logNote(j.id, `가져오지 않은 파일 (이미지·result.json 이 아니거나 링크·너무 큼): ${skipped.join(", ")}`);
  const { status, error } = runOutcome({
    cancelled: r.cancelled, cancelReason: r.cancelReason, timedOut: r.timedOut, timeoutMs: o.timeoutMs, result: await loadResult(j.id), exitCode, output: tail(output),
  });
  await logNote(j.id, `결과 ${status}${error ? ` · ${error}` : ""}`);
  await closeRun(r, status, error, sessionId);
}

/** 실패 원인을 찾는 데 쓸 마지막 부분. */
const tail = (s: string) => s.slice(-4000);

async function closeRun(r: Run, status: JobStatus, error: string | null, sessionId: string | null) {
  await finishJob(r.job, status, error, sessionId);
  if (status !== "done") log(`e2e ${r.job.id} ${status}${error ? ` · ${error}` : ""}`);
  if (current === r) current = null;
  await reload();
  pump();
}

// ---------------------------------------------------------------- 결과 화면 동작
export async function deleteJob(id: string): Promise<void> {
  if (isRunning(id)) return;
  await native.e2eJobDelete(id).catch(() => {});
  await reload();
}

export const openLog = (id: string) => native.openDataPath(logPath(id), false).catch(() => {});
export const logTail = (id: string, lines = 15) => native.e2eLogText(id).then((t) => t.split(/\r?\n/).slice(-lines).join("\n").trim()).catch(() => "");
export async function revealJob(id: string): Promise<void> {
  await native.revealPath(await absPath("e2e", "jobs", id, "job.json")).catch(() => {});
}

/** 이 이슈 결과의 스크린샷 중 결과 폴더에 실제로 있는 것 (이름만 보고 이미지 확장자의 일반 파일만). */
export const existingScreenshots = (jobId: string, issue: IssueResult) => native.e2eScreenshots(jobId, screenshotNames(issue)).catch(() => [] as string[]);

/** 결과를 HTML 파일 하나(스크린샷 포함)로 바탕 화면에 내보내고 탐색기에서 보여준다. */
export async function exportReport(id: string): Promise<void> {
  const j = job(id);
  if (!j || isRunning(id) || e2e.exporting) return;
  e2e.exporting = true;
  e2e.submitError = null;
  try {
    const result = await loadResult(id);
    const images = new Map<string, ReportImage>();
    if (result.kind === "ok") {
      for (const issue of result.result.issues) {
        for (const name of screenshotNames(issue)) {
          const d = await native.e2eScreenshotData(id, name).catch(() => null);
          if (d) images.set(name, { mime: d[0], base64: d[1] });
        }
      }
    }
    const html = reportHtml({
      job: j, result, modelName: modelName(j.model), logTail: await logTail(id, 40), jiraBase: normalizeBase(settings.jiraBaseURL) ?? "",
      image: (name) => images.get(name.split(/[\\/]/).pop() ?? "") ?? null,
    });
    const path = await native.e2eExportHtml(reportFileName(j), html);
    await native.revealPath(path).catch(() => {});
  } catch (e) {
    e2e.submitError = `내보내기 실패: ${errText(e)}`;
  } finally {
    e2e.exporting = false;
  }
}

// ---------------------------------------------------------------- Jira 댓글
export const commentId = (jobId: string, key: string) => `${jobId}/${key}`;

/** 댓글로 남길 수 있는 이슈: 끝난 job 의 결과 중 ATM 이 만든 Jira 주소가 있는 것. */
export function commentableIssues(j: Job): IssueResult[] {
  const r = e2e.results[j.id];
  if (isRunning(j.id) || r?.kind !== "ok") return [];
  return r.result.issues.filter((i) => { const ref = j.issues.find((x) => x.key === i.key); return ref ? issueLink(ref) !== null : false; });
}

const b64ToBytes = (b: string) => Uint8Array.from(atob(b), (c) => c.charCodeAt(0));

/** 검증 결과를 그 Jira 이슈의 댓글로 남긴다. withScreenshots 면 스크린샷을 이슈에 첨부하고 댓글 안에 이미지로 넣는다.
 * 이미지로 넣지 못한 스크린샷은 댓글에 첨부 이름만 적는다. */
export async function postComment(jobId: string, key: string, withScreenshots: boolean): Promise<void> {
  const j = job(jobId);
  const ref = j?.issues.find((i) => i.key === key);
  const res = e2e.results[jobId];
  const issue = res?.kind === "ok" ? res.result.issues.find((i) => i.key === key) : undefined;
  if (e2e.commenting || isRunning(jobId) || !j || !ref || !issue) return;
  const id = commentId(jobId, key);
  e2e.commenting = id;
  e2e.commentNote = null;
  try {
    const c = await creds().catch(() => null);
    if (!c) { e2e.commentNote = { id, text: "Jira 주소·이메일·토큰이 필요해요 · 설정 > Jira 에서 연결해 주세요" }; return; }
    // 검증을 돌린 뒤 Jira 주소를 바꿨으면 다른 사이트의 같은 키에 남기게 된다.
    if (!jiraURL(ref.url, c.baseURL)) { e2e.commentNote = { id, text: "이 검증을 돌릴 때와 지금 설정의 Jira 주소가 달라 남기지 않았어요" }; return; }

    const attached: Record<string, string> = {}, media: Record<string, string> = {}, failures: string[] = [];
    if (withScreenshots) {
      for (const name of await existingScreenshots(jobId, issue)) {
        const d = await native.e2eScreenshotData(jobId, name).catch(() => null);
        if (!d) continue;
        const upload = attachmentName(j, name);
        try {
          const attachmentId = await addAttachment(c, key, upload, d[0] || mimeOf(""), b64ToBytes(d[1]));
          attached[name] = upload;
          const m = await mediaFileId(c, attachmentId);
          if (m) media[name] = m;
        } catch (e) { failures.push(errText(e)); }
      }
    }
    try {
      await addComment(c, key, commentDocument({ job: j, issue, modelName: modelName(j.model), attached, media }));
    } catch (e) {
      const m = errText(e);
      e2e.commentNote = { id, text: Object.keys(attached).length ? `스크린샷 ${Object.keys(attached).length}장은 첨부됐지만 댓글을 남기지 못했어요 · ${m}` : `댓글을 남기지 못했어요 · ${m}` };
      log(`e2e jira comment error ${key}: ${m}`);
      return;
    }
    await patchJob(j.id, { jiraComments: { ...j.jiraComments, [key]: isoString(new Date()) } }).catch(() => {});
    await reload();
    log(`e2e jira comment ${key} job=${jobId} 첨부=${Object.keys(attached).length} 본문이미지=${Object.keys(media).length} 실패=${failures.length}`);
    if (failures[0]) e2e.commentNote = { id, text: `댓글은 남겼지만 스크린샷 ${failures.length}장은 첨부하지 못했어요 · ${failures[0]}` };
  } finally {
    e2e.commenting = null;
  }
}

