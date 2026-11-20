// Aside CLI 쪽 순수 로직 (Mac AsideCLI·E2ESetup 포팅): 상태 해석, 모델 목록, 실패 원인, 준비 점검.
// 프로세스·파일은 e2e.svelte.ts 가 다룬다.
import { loginBlockReason, loginBlockSteps, type JobStatus, type LoginBlock, type ResultLoad } from "./e2eCore";

export const ASIDE_DOWNLOAD_URL = "https://aside.com/download";
/** 오래된 CLI 가 보여 줄 안내. */
export const UPDATE_HINT = "Aside CLI 가 오래됐어요 · '터미널에서 업데이트'로 올린 뒤 다시 실행";

export type SignOutReason = { kind: "never" } | { kind: "noSession" } | { kind: "paused"; why: string };
export type AccountStatus =
  | { kind: "signedIn"; email: string; accountId: number; plan: string }
  | { kind: "signedOut"; who: string; reason: SignOutReason }
  | { kind: "unknown"; message: string };
export interface AsideAccount { id: number; title: string; signedIn: boolean }
export interface AsideModel { id: string; name: string; minPlan: string; provider: string }
export interface AsideProbe {
  path: string; source: string; version: string; latestVersion: string;
  /** `aside exec` 가 guard 권한 옵션을 아는가 (모르는 구버전은 검증을 돌릴 수 없다) */
  runnable: boolean;
  account: AccountStatus; otherAccounts: AsideAccount[];
  /** Aside 브라우저 창이 열려 있는가. 확인 못 했으면 null. */
  windowOpen: boolean | null;
}

export const needsPaidPlan = (m: AsideModel) => m.minPlan !== "" && m.minPlan.toLowerCase() !== "free";

/** 점으로 나눈 숫자 버전 비교 (1.26.1107.24). 숫자가 아니면 false. */
export function isNewer(candidate: string, current: string): boolean {
  const parts = (v: string) => {
    const p = v.trim().split(".").map((x) => (/^\d+$/.test(x) ? Number(x) : NaN));
    return p.length === 0 || p.some(Number.isNaN) ? null : p;
  };
  const a = parts(candidate), b = parts(current);
  if (!a || !b) return false;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const x = a[i] ?? 0, y = b[i] ?? 0;
    if (x !== y) return x > y;
  }
  return false;
}
export const updateAvailable = (p: AsideProbe) => isNewer(p.latestVersion, p.version);

/** `aside exec` 인자. 셸을 거치지 않고 배열로 넘긴다. 권한은 늘 guard (사용자의 Aside 기본이 full-access 여도). */
export function execArguments(prompt: string, model = ""): string[] {
  const m = model.trim();
  return ["exec", "--permission", "guard", ...(m ? ["--model", m] : []), prompt];
}

/** 묻는 창·색·업데이트 알림을 끈다. */
export const asideEnv = (): Record<string, string> => ({ CI: "1", NO_COLOR: "1", NO_UPDATE_NOTIFIER: "1" });

/** stderr 의 `created new session: <id>` 에서 세션 id. */
export function sessionIdIn(line: string): string | null {
  const i = line.indexOf("created new session:");
  if (i < 0) return null;
  const id = line.slice(i + "created new session:".length).trim();
  return !id || /\s/.test(id) ? null : id;
}

export const sessionIdInLog = (text: string): string | null => {
  for (const l of text.split("\n")) { const s = sessionIdIn(l); if (s) return s; }
  return null;
};

/** 구버전 CLI 가 모르는 옵션·명령을 받았을 때의 출력인가. */
export const isUnknownOption = (out: string) => /unknown option|unknown command/i.test(out);

// ---- 계정 ----
interface AccountJSON {
  id?: number; email?: string; name?: string; provider?: string; mode?: string;
  authStatus?: string; authPausedReason?: string; hasSession?: boolean; subscriptionPlan?: string;
}
const titleOf = (a: AccountJSON) => a.email ?? a.name ?? "";

/** 로그인 판단은 Aside CLI 의 기준을 따른다 (cloud 계정이고 세션이 있으며 멈추지 않았을 때만 로그인). */
function statusOf(a: AccountJSON): AccountStatus {
  const auth = a.authStatus?.toLowerCase();
  if (auth === "active" && a.hasSession !== false && a.mode?.toLowerCase() !== "local") {
    return { kind: "signedIn", email: titleOf(a), accountId: a.id ?? 0, plan: a.subscriptionPlan ?? "" };
  }
  if (auth === "paused") return { kind: "signedOut", who: titleOf(a), reason: { kind: "paused", why: a.authPausedReason ?? "" } };
  const known = !!a.email || !["", "anonymous"].includes(a.provider?.toLowerCase() ?? "");
  return { kind: "signedOut", who: titleOf(a), reason: { kind: known ? "noSession" : "never" } };
}

const json = (s: string): unknown => { try { return JSON.parse(s); } catch { return undefined; } };
const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === "object" && !Array.isArray(v);

/** `aside account status --json` 결과 해석. */
export function parseAccountStatus(stdout: string, exitCode: number): AccountStatus {
  const j = json(stdout);
  if (!isObj(j)) {
    const lower = stdout.toLowerCase();
    if (lower.includes("not signed in") || lower.includes("aside login")) return { kind: "signedOut", who: "", reason: { kind: "never" } };
    const last = stdout.split("\n").filter(Boolean).pop() ?? "";
    return { kind: "unknown", message: exitCode === 0 ? `알 수 없는 응답: ${last.slice(0, 120)}` : `aside 오류 (exit ${exitCode}) ${last.slice(0, 120)}` };
  }
  return isObj(j.account) ? statusOf(j.account as AccountJSON) : { kind: "signedOut", who: "", reason: { kind: "never" } };
}

/** `aside account list --json` 에서 지금 계정 말고 다른 계정. 모르는 모양이면 빈 목록. */
export function parseOtherAccounts(stdout: string): AsideAccount[] {
  const j = json(stdout);
  if (!isObj(j) || !Array.isArray(j.accounts)) return [];
  const cur = typeof j.currentAccountId === "number" ? j.currentAccountId : undefined;
  return (j.accounts as AccountJSON[]).flatMap((a) => {
    if (!isObj(a) || typeof a.id !== "number" || a.id === cur) return [];
    return [{ id: a.id, title: titleOf(a) || `u${a.id}`, signedIn: statusOf(a).kind === "signedIn" }];
  });
}

/** `aside host profiles` 에서 Aside 브라우저 창이 하나라도 연결돼 있는가. 모르는 출력이면 null. */
export function parseWindowOpen(output: string): boolean | null {
  const j = json(output);
  if (isObj(j) && Array.isArray(j.profiles)) return (j.profiles as { connected?: boolean }[]).some((p) => p?.connected === true);
  const states = output.split(/\r?\n/).flatMap((line) => {
    const last = line.trim().split(/\s+/).pop()?.toLowerCase();
    return last === "connected" ? [true] : last === "disconnected" ? [false] : [];
  });
  if (states.length) return states.includes(true);
  return output.toLowerCase().includes("no browser profiles") ? false : null;
}

/** `aside account status` 일반 출력 (`--json` 이 없는 구버전). 예: `* u0  me@example.com  signed in  profiles: Profile 0`. */
export function parsePlainAccountStatus(output: string): AccountStatus {
  const rows = output.split(/\r?\n/).map((line) => {
    const t = line.trim().split(/\s+/).filter(Boolean);
    const current = t[0] === "*";
    if (current) t.shift();
    return { current, t };
  }).filter((r) => r.t.length >= 3 && /^u\d+$/.test(r.t[0]));
  const lower = output.toLowerCase();
  const row = rows.find((r) => r.current) ?? rows[0];
  if (!row) {
    if (lower.includes("not signed in") || lower.includes("aside login")) return { kind: "signedOut", who: "", reason: { kind: "never" } };
    return { kind: "unknown", message: UPDATE_HINT };
  }
  const who = row.t[1];
  const state = row.t.slice(2).join(" ").toLowerCase();
  if (state.includes("paused")) return { kind: "signedOut", who, reason: { kind: "paused", why: "" } };
  if (state.includes("not signed in") || state.includes("signed out")) return { kind: "signedOut", who, reason: { kind: "noSession" } };
  if (!state.startsWith("signed in")) return { kind: "unknown", message: UPDATE_HINT };
  return { kind: "signedIn", email: who, accountId: Number(row.t[0].slice(1)), plan: "" };
}

// ---- 모델 ----
interface CacheEntry { value?: { models?: { id?: string; name?: string; minPlan?: string }[] } }

/** Aside 앱이 받아 둔 모델 목록 캐시 (공식 CLI 명령이 없어 내부 파일을 읽는다. 모양이 바뀌면 빈 목록). */
export function parseModels(text: string): AsideModel[] {
  const all = json(text);
  if (!isObj(all)) return [];
  const e = all['["models","aside-catalog"]'] as CacheEntry | undefined;
  return (e?.value?.models ?? []).filter((m) => m?.id).map((m) => ({ id: m.id!, name: m.name ?? m.id!, minPlan: m.minPlan ?? "", provider: "aside" }));
}

/** 캐시의 모든 카탈로그에서 id → 이름. */
export function modelNames(text: string): Record<string, string> {
  const all = json(text), out: Record<string, string> = {};
  if (!isObj(all)) return out;
  for (const e of Object.values(all) as CacheEntry[]) for (const m of e?.value?.models ?? []) if (m?.id && !(m.id in out)) out[m.id] = m.name ?? m.id;
  return out;
}

/** 사용자가 Aside 에 연동한 provider(claude-code 등)의 모델. --model 에 넣을 id 는 "provider/모델". */
export function parseConnectedModels(text: string, names: Record<string, string> = {}): AsideModel[] {
  const f = json(text);
  if (!isObj(f) || !isObj(f.providers)) return [];
  const out: AsideModel[] = [];
  for (const provider of Object.keys(f.providers).sort()) {
    const c = (f.providers[provider] as { accountModelCatalog?: { modelIds?: string[]; scopes?: Record<string, { modelIds?: string[] }> } })?.accountModelCatalog;
    const ids = [...(c?.modelIds ?? []), ...Object.values(c?.scopes ?? {}).flatMap((s) => s?.modelIds ?? [])];
    for (const id of new Set(ids)) if (id) out.push({ id: `${provider}/${id}`, name: `${names[id] ?? id} · ${provider}`, minPlan: "", provider });
  }
  return out;
}

export function latestVersionOf(text: string | null): string {
  const j = text ? json(text) : undefined;
  return isObj(j) && typeof j.latestVersion === "string" ? j.latestVersion : "";
}

// ---- 실패 원인 ----
export type FailureKind = "cliOutdated" | "versionMismatch" | "modelUnavailable" | "signedOut" | "folderBlocked" | "windowClosed" | "asideDown";
export const FAILURE_KINDS: FailureKind[] = ["cliOutdated", "versionMismatch", "modelUnavailable", "signedOut", "folderBlocked", "windowClosed", "asideDown"];

export function detectFailure(output: string): FailureKind | null {
  const t = output.toLowerCase();
  const has = (...w: string[]) => w.some((x) => t.includes(x));
  if (isUnknownOption(t)) return "cliOutdated";
  if (has("no procedure found on path", "-procedure on path")) return "versionMismatch";
  if (has("is not available for this account", "choose an available model")) return "modelUnavailable";
  if (has("not signed in", "aside login", "sign in to", "sign in again", "needs sign-in", "requires sign-in", "unauthorized", "session expired", "login required")) return "signedOut";
  if (has("operation not permitted", "path escapes", "blocked by policy", "permission denied")) return "folderBlocked";
  if (has("is not connected to the daemon", "no browser profiles are connected", "start aside browser")) return "windowClosed";
  if (has("econnrefused", "daemon", "is aside running", "could not connect", "failed to connect")) return "asideDown";
  return null;
}

export const failureMessage = (k: FailureKind): string => ({
  cliOutdated: UPDATE_HINT,
  versionMismatch: "Aside 브라우저와 CLI 버전이 서로 맞지 않아요 · 둘 다 최신으로 올린 뒤 다시 실행",
  modelUnavailable: "고른 모델을 이 Aside 계정에서 쓸 수 없어요 · E2E 탭 실행 버튼 옆에서 다른 모델을 고르세요",
  signedOut: "Aside 계정 로그인이 풀렸어요 · Aside 설정 > 계정에서 다시 로그인한 뒤 다시 실행",
  folderBlocked: "Aside 가 실행용 폴더에 접근하지 못했어요 · run.log 를 확인해 주세요",
  windowClosed: "Aside 브라우저 창이 닫혀 있었어요 · Aside 를 연 뒤 다시 실행",
  asideDown: "Aside 앱에 연결하지 못했어요 · Aside 를 켠 뒤 다시 실행",
})[k];

/** 사용자가 할 일 (마지막은 늘 다시 실행). */
export const failureSteps = (k: FailureKind): string[] => ({
  cliOutdated: ["'터미널에서 업데이트'로 Aside CLI 를 최신으로 올려요", "다시 실행해요"],
  versionMismatch: ["'터미널에서 업데이트'로 Aside CLI 를 최신으로 올려요", "Aside 브라우저도 최신 버전으로 올린 뒤 다시 켜요", "다시 실행해요"],
  modelUnavailable: ["E2E 탭 실행 버튼 옆 메뉴에서 쓸 수 있는 모델(또는 Aside 기본 모델)을 골라요", "다시 실행해요"],
  signedOut: ["'Aside 열기'를 눌러요", "Aside 설정 > 계정에서 Aside 계정으로 다시 로그인해요", "다시 실행해요"],
  folderBlocked: ["위의 '로그'로 run.log 에서 막힌 경로를 확인해요", "다시 실행해요"],
  windowClosed: ["'Aside 열기'로 Aside 브라우저 창을 띄워요 (앱이 켜져 있어도 창이 없으면 실행하지 못해요)", "다시 실행해요"],
  asideDown: ["'Aside 열기'로 Aside 를 켜요", "계속 안 되면 Aside 를 완전히 종료했다가 다시 켜요", "다시 실행해요"],
})[k];

export const failureFix = (k: FailureKind): SetupFix | null =>
  k === "cliOutdated" || k === "versionMismatch" ? { kind: "updateCLI" }
    : k === "signedOut" || k === "windowClosed" || k === "asideDown" ? { kind: "openAside" } : null;

/** 저장된 job.error 문장에서 알아본 실패 원인을 다시 찾는다. */
export const failureOfMessage = (error: string): FailureKind | null => FAILURE_KINDS.find((k) => failureMessage(k) === error) ?? null;

/** result.json 이 없을 때 보여줄 한 줄. */
export function missingResultMessage(exitCode: number, output: string): string {
  const k = detectFailure(output);
  if (k) return failureMessage(k);
  const last = output.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).pop() ?? "";
  return `결과 파일(result.json)이 없어요 (exit ${exitCode})${last ? ` · ${last.slice(0, 160)}` : ""}`;
}

// ---- 준비 점검 ----
export type SetupFix =
  | { kind: "downloadBrowser" } | { kind: "installCLI" } | { kind: "updateCLI" } | { kind: "loginCLI" } | { kind: "openAside" }
  | { kind: "switchAccount"; id: number; title: string } | { kind: "openSettings" } | { kind: "openEnvironment" };

export function fixLabel(f: SetupFix): string {
  switch (f.kind) {
    case "downloadBrowser": return "Aside 다운로드";
    case "installCLI": return "Aside 다운로드";
    case "updateCLI": return "터미널에서 업데이트";
    case "loginCLI": return "터미널에서 로그인";
    case "openAside": return "Aside 열기";
    case "switchAccount": return `${f.title} 계정으로 바꾸기`;
    case "openSettings": return "설정 열기";
    case "openEnvironment": return "Aside 에서 열기";
  }
}

/** 고른 환경의 지난 검증에서 로그인이 어땠는지. Vault 상태는 실행 전에 알 수 없어 지난 결과로 안내한다. */
export type LoginHistory = { kind: "none" } | { kind: "ok" } | { kind: "blocked"; block: LoginBlock };

export interface SetupItem {
  kind: "browser" | "cli" | "account" | "window" | "envURL" | "envLogin";
  /** todo: 실행을 막는다. warn·info: 실행은 되지만 봐야 한다. waiting: 앞 단계가 끝나야 알 수 있다. */
  state: "ok" | "todo" | "warn" | "info" | "waiting";
  title: string; detail: string; steps: string[]; note: string; fixes: SetupFix[];
}
export interface SetupInput {
  browserInstalled: boolean; browserVersion: string; probe: AsideProbe | null;
  /** 환경 항목을 볼 환경. null 이면 Aside 항목만. */
  env: string | null; envURL: string; envUser: string; lastLogin: LoginHistory;
}

const item = (kind: SetupItem["kind"], state: SetupItem["state"], title: string, detail: string, extra: Partial<SetupItem> = {}): SetupItem =>
  ({ kind, state, title, detail, steps: [], note: "", fixes: [], ...extra });
const waiting = (kind: SetupItem["kind"], title: string) => item(kind, "waiting", title, "앞 단계를 마치면 확인해요");
export const needsAttention = (i: SetupItem) => i.state === "todo" || i.state === "warn" || i.state === "info";

/** 검증을 돌리기까지 필요한 준비를 순서대로 본다: Aside 브라우저 → CLI → Aside 계정 → 창 → 환경 주소 → 환경 로그인. */
export function setupItems(i: SetupInput): SetupItem[] {
  const out = [browser(i), cli(i), account(i)];
  const w = windowItem(i);
  if (w) out.push(w);
  if (i.env) out.push(...environment(i.env, i));
  return out;
}
export const blocker = (items: SetupItem[]) => items.find((i) => i.state === "todo");

function browser(i: SetupInput): SetupItem {
  const title = "Aside 브라우저";
  if (i.browserInstalled) return item("browser", "ok", title, i.browserVersion ? `설치됨 · ${i.browserVersion}` : "설치됨");
  // CLI 가 있으면 브라우저는 다른 위치에 설치된 것으로 보고 막지 않는다
  if (i.probe) return item("browser", "ok", title, "앱 위치는 찾지 못했어요");
  return item("browser", "todo", title, "Aside 브라우저가 없어요", {
    steps: ["'Aside 다운로드'로 내려받아 설치해요", "Aside 를 열고 Aside 계정으로 로그인해요", "'다시 확인'을 눌러요"],
    fixes: [{ kind: "downloadBrowser" }],
  });
}

function cli(i: SetupInput): SetupItem {
  const title = "Aside CLI";
  const p = i.probe;
  if (!p) {
    if (!i.browserInstalled) return waiting("cli", title);
    return item("cli", "todo", title, "Aside CLI 가 없어요", {
      steps: ["'Aside 다운로드'에서 Windows 용 Aside 와 CLI 를 설치해요", "설치가 끝나면 ATM 이 알아서 다시 확인해요"],
      fixes: [{ kind: "installCLI" }],
    });
  }
  const version = p.version || "설치됨";
  if (!p.runnable) {
    return item("cli", "todo", title, `Aside CLI(${version})가 오래돼 검증을 돌릴 수 없어요`, {
      steps: ["'터미널에서 업데이트'로 최신으로 올려요", "Aside 브라우저도 최신 버전으로 올려요", "끝나면 ATM 이 알아서 다시 확인해요"],
      fixes: [{ kind: "updateCLI" }],
    });
  }
  if (updateAvailable(p)) {
    return item("cli", "ok", title, `${version} · 새 버전 ${p.latestVersion} 있음`, {
      note: "검증이 이유 없이 실패하면 CLI 와 Aside 브라우저를 둘 다 최신으로 올려 보세요.", fixes: [{ kind: "updateCLI" }],
    });
  }
  return item("cli", "ok", title, version);
}

const pausedNote = (why: string) => (why === "device_mismatch" ? " (기기 정보가 달라졌어요)" : why === "token_revoked" ? " (로그인이 해제됐어요)" : "");

function account(i: SetupInput): SetupItem {
  const title = "Aside 계정";
  const p = i.probe;
  if (!p) return waiting("account", title);
  const others = p.otherAccounts.filter((a) => a.signedIn);
  const switches: SetupFix[] = others.map((a) => ({ kind: "switchAccount", id: a.id, title: a.title }));
  const a = p.account;
  if (a.kind === "signedIn") {
    const it = item("account", "ok", title, `${a.email || "로그인됨"} (u${a.accountId})`);
    if (p.otherAccounts.length) {
      it.note = `Aside 에 계정이 ${p.otherAccounts.length + 1}개 있어요. 검증은 위 계정으로 돌고, 테스트 환경 로그인도 이 계정의 Vault 에 있어야 해요.`;
      it.fixes = switches;
    }
    return it;
  }
  if (a.kind === "signedOut") {
    const name = a.who ? `Aside 계정(${a.who})` : "Aside 계정";
    const detail = a.reason.kind === "never" ? "Aside 브라우저에 Aside 계정으로 로그인해야 해요"
      : a.reason.kind === "noSession" ? `${name} 로그인이 풀렸어요` : `${name} 로그인이 멈췄어요${pausedNote(a.reason.why)}`;
    const it = item("account", "todo", title, detail, {
      steps: ["'Aside 열기'를 눌러요", "Aside 설정 > 계정에서 Aside 계정으로 로그인해요(안 되면 '터미널에서 로그인')", "로그인하면 ATM 이 알아서 다시 확인해요"],
      fixes: [{ kind: "openAside" }, { kind: "loginCLI" }, ...switches],
    });
    if (others.length) it.note = `다른 계정(${others.map((o) => o.title).join(", ")})은 로그인돼 있어요. 그 계정으로 검증하려면 계정을 바꿔요.`;
    return it;
  }
  return item("account", "todo", title, `Aside 상태를 확인하지 못했어요 · ${a.message}`, {
    steps: ["'Aside 열기'로 Aside 를 켜고 '다시 확인'을 눌러요", "계속 안 되면 '터미널에서 업데이트'로 CLI 를 올려요"],
    fixes: [{ kind: "openAside" }, { kind: "updateCLI" }],
  });
}

/** 창이 닫혀 있어도 실행할 때 ATM 이 Aside 를 열기 때문에 막지는 않는다. */
function windowItem(i: SetupInput): SetupItem | null {
  const p = i.probe;
  if (!p || p.account.kind !== "signedIn" || p.windowOpen === null) return null;
  const title = "Aside 창";
  if (p.windowOpen) return item("window", "ok", title, "열려 있어요");
  return item("window", "warn", title, "Aside 창이 닫혀 있어요 · 실행하면 ATM 이 Aside 를 열어요", { fixes: [{ kind: "openAside" }] });
}

function environment(env: string, i: SetupInput): SetupItem[] {
  if (!i.envURL.trim()) {
    return [item("envURL", "todo", `${env} 환경 주소`, `${env} 환경 주소가 없어요`, { steps: [`설정 > E2E 의 환경에 ${env} 주소를 넣어요`], fixes: [{ kind: "openSettings" }] })];
  }
  const account = i.envUser ? `테스트 계정(${i.envUser})` : "테스트 계정";
  const title = `${env} 로그인`;
  const l = i.lastLogin;
  if (l.kind === "ok") return [item("envLogin", "ok", title, "지난 검증에서 자동으로 로그인됐어요")];
  if (l.kind === "blocked") {
    return [item("envLogin", "warn", title, `지난 검증에서 막혔어요 · ${loginBlockReason(l.block)}`, { steps: loginBlockSteps(l.block, account), fixes: [{ kind: "openEnvironment" }] })];
  }
  return [item("envLogin", "info", title, "처음이면 테스트 계정 로그인을 Aside 에 저장해 두세요", {
    steps: [`'Aside 에서 열기'로 ${env} 환경을 열어 ${account}으로 직접 로그인해요`,
      "로그인 정보를 저장할지 물으면 Aside Vault 에 저장해요 (Vault 가 없으면 이때 만들어요)", "Vault 잠금을 풀어 둔 채로 실행해요"],
    note: "비밀번호는 Aside 에서 직접 입력해요. ATM 과 Aside 에이전트는 비밀번호를 보지 않아요.",
    fixes: [{ kind: "openEnvironment" }],
  })];
}


// ---- 실행 결과 판정 ----
/** 실행이 끝났을 때 job 상태와 오류 문장. 성공 판단은 exit code 가 아니라 result.json 으로만 한다. */
export function runOutcome(o: {
  cancelled: boolean; cancelReason: string | null; timedOut: boolean; timeoutMs: number; result: ResultLoad; exitCode: number; output: string;
}): { status: JobStatus; error: string | null } {
  if (o.cancelled) return { status: "cancelled", error: o.cancelReason };
  if (o.result.kind === "ok") return o.result.result.issues.length === 0 ? { status: "failed", error: "result.json 에 이슈 결과가 없어요" } : { status: "done", error: null };
  if (o.timedOut) {
    return { status: "failed", error: `제한 시간 ${Math.max(1, Math.floor(o.timeoutMs / 60_000))}분을 넘겨 멈췄어요 · 이슈를 나눠 실행하거나 설정 > E2E 에서 제한 시간을 늘려 보세요` };
  }
  if (o.result.kind === "invalid") return { status: "failed", error: `result.json 을 읽지 못했어요 (${o.result.message})` };
  return { status: "failed", error: missingResultMessage(o.exitCode, o.output) };
}
