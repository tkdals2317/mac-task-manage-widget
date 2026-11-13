// PR 탭 데이터 (Mac PRModel). GitHub 은 gh CLI 토큰으로 GraphQL, Bitbucket 은 이메일 + API 토큰으로 REST 2.0.
// 두 제공자를 따로 받아 한쪽이 실패해도 그쪽의 직전 목록을 유지한다. 토큰은 메모리에서만 쓰고 로그·파일에 남기지 않는다.
import { fetch as tauriFetch } from "@tauri-apps/plugin-http";
import { sendNotification, isPermissionGranted, requestPermission } from "@tauri-apps/plugin-notification";
import { log, native, readJSON, writeJSON } from "./native";
import { basicAuth } from "./http";
import { settings, setSetting, enabledTabs } from "./settings.svelte";
import {
  GH_QUERY, approvedBy, badgeCount, classifyHttp, decodeBitbucketComments, decodeBitbucketPRs, decodeGitHub, decodeWorkspaces,
  bitbucketParts, githubParts, markApproved, markUnapproved, mergedSnapshot, noticeBody, noticeTitle, notifications, repoKey,
  safeNext, snapshot, sortMine, sortReviewRequests, trimSeen, type PRProvider, type PRSnapshot, type PullRequest, type PRNotice,
  parseBitbucketRemote,
} from "./prCore";

export const BITBUCKET_SERVICE = "com.lsm0506.TaskWidget.bitbucket";
const STATE_FILE = "pr-state.json";
const BB = "https://api.bitbucket.org/2.0";

export type GitHubStatus = { kind: "off" } | { kind: "ok"; login: string } | { kind: "ghMissing" } | { kind: "loggedOut" } | { kind: "error"; message: string };
export type BitbucketStatus = { kind: "off" } | { kind: "ok"; name: string } | { kind: "notConfigured" } | { kind: "error"; message: string };

export const pr = $state({
  reviewRequests: [] as PullRequest[],
  mine: [] as PullRequest[],
  lastRefresh: null as number | null,
  loading: false,
  github: { kind: "off" } as GitHubStatus,
  bitbucket: { kind: "off" } as BitbucketStatus,
  githubError: null as string | null,
  bitbucketError: null as string | null,
  seen: new Set<string>(),
  acting: [] as string[],
  actionError: {} as Record<string, string>,
  bbNoWrite: false,
});

interface Persisted { seen?: string[]; snapshot?: PRSnapshot | null; mine404?: string[]; repoKey?: string; recent?: Record<string, { at: number; slugs: string[] }> }
let persisted: Persisted = {};
let loadedState = false;
async function loadState() {
  if (loadedState) return;
  persisted = await readJSON<Persisted>(STATE_FILE, {});
  pr.seen = new Set(persisted.seen ?? []);
  pr.bbNoWrite = settings.prBitbucketNoWrite;
  loadedState = true;
}
const saveState = () => writeJSON(STATE_FILE, { ...persisted, seen: [...pr.seen].sort() }).catch(() => {});

export const badge = () => badgeCount(pr.reviewRequests, pr.mine, pr.seen);
export const anyEnabled = () => settings.prGitHubEnabled || settings.prBitbucketEnabled;

// 제공자별 원본 (숨긴 저장소·Draft 거르기 전)
let ghRR: PullRequest[] = [], ghMine: PullRequest[] = [], bbRR: PullRequest[] = [], bbMine: PullRequest[] = [];
const nextAllowed: Partial<Record<PRProvider, number>> = {};
let lastBB = 0;
let pending = false;

class PRErr extends Error {
  constructor(message: string, public kind: "auth" | "rate" | "http" | "net" | "noWrite" | "msg" = "msg", public code = 0, public waitSec: number | null = null) { super(message); }
}

function rateLimit(p: PRProvider, e: unknown) {
  if (e instanceof PRErr && e.kind === "rate") nextAllowed[p] = Date.now() + (e.waitSec ?? 300) * 1000;
}

async function http(url: string, init: { method?: string; headers: Record<string, string>; body?: string }, provider: string): Promise<unknown> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 25_000);
  let res: Response;
  try {
    res = await tauriFetch(url, { method: init.method ?? "GET", headers: init.headers, body: init.body, signal: ctrl.signal });
  } catch (e) {
    throw new PRErr(`네트워크: ${e instanceof Error ? e.message : String(e)}`, "net");
  } finally {
    clearTimeout(t);
  }
  const text = await res.text().catch(() => "");
  if (!res.ok) {
    const h = (k: string) => res.headers.get(k);
    const c = classifyHttp(res.status, h("x-ratelimit-remaining"), h("retry-after"), h("x-ratelimit-reset"), provider);
    if (c.kind === "rate") throw new PRErr(c.message, "rate", res.status, c.waitSec);
    if (c.kind === "auth") throw new PRErr("인증 실패 (401/403)", "auth", res.status);
    throw new PRErr(`HTTP ${res.status}`, "http", res.status);
  }
  try { return text ? JSON.parse(text) : null; } catch { throw new PRErr("응답 해석 실패", "msg"); }
}

// ---- GitHub ----

let ghPath: string | null | undefined;
async function resolveGh(force: boolean): Promise<string | null> {
  if (!force && ghPath) return ghPath;
  ghPath = (await native.which("gh").catch(() => null))?.[0] ?? null;
  return ghPath;
}

/** `gh auth token`. 로그인 안 돼 있으면 null. */
async function ghToken(gh: string): Promise<string | null> {
  const r = await native.run(gh, ["auth", "token"], { env: { GH_PROMPT_DISABLED: "1" }, timeoutMs: 10_000 }).catch(() => null);
  const t = r && r.code === 0 ? r.stdout.trim() : "";
  return t || null;
}

const ghHeaders = (token: string) => ({ Authorization: `Bearer ${token}`, "Content-Type": "application/json", "User-Agent": "ATM" });

export async function probeGitHub(force = false): Promise<void> {
  const gh = await resolveGh(force);
  if (!gh) { pr.github = { kind: "ghMissing" }; return; }
  const t = await ghToken(gh);
  if (!t) { pr.github = { kind: "loggedOut" }; return; }
  try {
    const j = (await http("https://api.github.com/graphql", { method: "POST", headers: ghHeaders(t), body: JSON.stringify({ query: "query { viewer { login } }" }) }, "GitHub")) as { data?: { viewer?: { login?: string } } };
    const login = j?.data?.viewer?.login;
    pr.github = login ? { kind: "ok", login } : { kind: "error", message: "viewer 없음" };
  } catch (e) {
    pr.github = { kind: "error", message: e instanceof Error ? e.message : String(e) };
  }
}

async function refreshGitHub(): Promise<boolean> {
  if (!settings.prGitHubEnabled) { pr.github = { kind: "off" }; pr.githubError = null; ghRR = []; ghMine = []; return false; }
  if ((nextAllowed.github ?? 0) > Date.now()) return false;
  const gh = await resolveGh(false);
  if (!gh) { pr.github = { kind: "ghMissing" }; pr.githubError = null; return false; }
  const t = await ghToken(gh);
  if (!t) { pr.github = { kind: "loggedOut" }; pr.githubError = null; return false; }
  try {
    const j = (await http("https://api.github.com/graphql", { method: "POST", headers: ghHeaders(t), body: JSON.stringify({ query: GH_QUERY }) }, "GitHub")) as { data?: { viewer?: { login?: string } } };
    const login = j?.data?.viewer?.login;
    if (!login) throw new PRErr("viewer 없음");
    const d = decodeGitHub(j, login);
    ghRR = d.reviewRequests; ghMine = d.mine;
    pr.github = { kind: "ok", login }; pr.githubError = null;
    return true;
  } catch (e) {
    rateLimit("github", e);
    const m = e instanceof Error ? e.message : String(e);
    pr.githubError = m;
    if (pr.github.kind !== "ok") pr.github = { kind: "error", message: m };
    log(`github refresh error: ${m}`);
    return false;
  }
}

// ---- Bitbucket ----

let bbToken: { email: string; token: string } | null = null;
let bbUser: { email: string; uuid: string; name: string } | null = null;

export async function bitbucketToken(email: string): Promise<string | null> {
  if (bbToken?.email === email) return bbToken.token;
  const t = await native.secretGet(BITBUCKET_SERVICE, email).catch(() => null);
  if (t) bbToken = { email, token: t };
  return t;
}

export function resetBitbucketCache() { bbToken = null; bbUser = null; }

const bbHeaders = (email: string, token: string) => ({ Authorization: basicAuth(email, token), Accept: "application/json" });
const bbGet = (path: string, email: string, token: string) => http(path.startsWith("https://") ? path : BB + path, { headers: bbHeaders(email, token) }, "Bitbucket");
const q = (o: Record<string, string | string[]>) => {
  const u = new URLSearchParams();
  for (const [k, v] of Object.entries(o)) for (const x of Array.isArray(v) ? v : [v]) u.append(k, x);
  return "?" + u.toString();
};
const PR_FIELDS = "+values.participants,+values.reviewers";

/** 설정의 "연결 확인": 입력한 값으로 사용자·워크스페이스를 읽는다. 아무것도 저장하지 않는다. */
export async function testBitbucket(email: string, token: string): Promise<{ name: string; uuid: string; workspaces: { slug: string; name: string }[] }> {
  const u = (await bbGet("/user", email, token)) as { uuid?: string; display_name?: string };
  if (!u?.uuid) throw new PRErr("uuid 없음");
  let workspaces: { slug: string; name: string }[] = [];
  for (const path of ["/user/workspaces", "/user/permissions/workspaces"]) {
    try {
      let next: string | null = path + q({ pagelen: "100" });
      let pages = 0;
      workspaces = [];
      while (next && pages++ < 10) {
        const d = decodeWorkspaces(await bbGet(next, email, token));
        workspaces.push(...d.workspaces);
        next = safeNext(d.next);
      }
      break;
    } catch (e) {
      if (e instanceof PRErr && (e.kind === "rate" || e.kind === "net")) throw e;
    }
  }
  return { name: u.display_name ?? "", uuid: u.uuid, workspaces };
}

/** 연결 확인이 성공한 뒤: 이메일·토큰 저장, 이메일이 바뀌었으면 옛 토큰 삭제. */
export async function commitBitbucket(email: string, token: string | null): Promise<void> {
  const old = settings.prBitbucketEmail;
  if (token) {
    await native.secretSet(BITBUCKET_SERVICE, email, token);
    bbToken = { email, token };
    setSetting("prBitbucketNoWrite", false);
    pr.bbNoWrite = false;
  }
  if (old && old !== email) await native.secretDelete(BITBUCKET_SERVICE, old).catch(() => {});
  setSetting("prBitbucketEmail", email);
  bbUser = null;
}

async function bbClient(): Promise<{ email: string; token: string } | null> {
  const email = settings.prBitbucketEmail.trim();
  const t = email ? await bitbucketToken(email) : null;
  return t ? { email, token: t } : null;
}

async function bbMe(c: { email: string; token: string }) {
  if (bbUser?.email === c.email) return bbUser;
  const u = (await bbGet("/user", c.email, c.token)) as { uuid?: string; display_name?: string };
  if (!u?.uuid) throw new PRErr("uuid 없음");
  bbUser = { email: c.email, uuid: u.uuid, name: u.display_name ?? "" };
  return bbUser;
}

async function mapLimit<T, R>(items: T[], limit: number, f: (x: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (i < items.length) { const k = i++; out[k] = await f(items[k]); }
  }));
  return out;
}

export const bitbucketRepoList = () => settings.prBitbucketRepos.split(",").map((s) => s.trim()).filter(Boolean);

async function refreshBitbucket(background: boolean): Promise<boolean> {
  if (!settings.prBitbucketEnabled) { pr.bitbucket = { kind: "off" }; pr.bitbucketError = null; bbRR = []; bbMine = []; return false; }
  if ((nextAllowed.bitbucket ?? 0) > Date.now()) return false;
  // 숨겨져 있을 때는 10분에 한 번만 (요청이 저장소 수만큼 나간다)
  if (background && Date.now() - lastBB < 600_000) return false;
  const ws = settings.prBitbucketWorkspace;
  const c = await bbClient();
  if (!c || !ws) { pr.bitbucket = { kind: "notConfigured" }; return false; }
  try {
    const me = await bbMe(c);
    const repos = bitbucketRepoList();
    const mine404 = new Set(persisted.mine404 ?? []);
    const skip = mine404.has(ws);
    const fetchMine = async (): Promise<{ prs: PullRequest[]; fallback: boolean }> => {
      if (!skip) {
        try {
          const j = await bbGet(`/workspaces/${ws}/pullrequests/${encodeURIComponent(me.uuid)}` + q({ pagelen: "50", fields: PR_FIELDS, state: "OPEN" }), c.email, c.token);
          return { prs: decodeBitbucketPRs(j, me.uuid).prs, fallback: false };
        } catch (e) { if (!(e instanceof PRErr && e.code === 404)) throw e; }
      }
      const query = `author.uuid="${me.uuid}" AND state="OPEN"`;
      const res = await mapLimit(repos, 6, async (slug) => {
        try { return decodeBitbucketPRs(await bbGet(`/repositories/${ws}/${slug}/pullrequests` + q({ pagelen: "50", fields: PR_FIELDS, q: query }), c.email, c.token), me.uuid).prs; }
        catch (e) { if (e instanceof PRErr && (e.kind === "auth" || e.kind === "rate")) throw e; return []; }
      });
      return { prs: res.flat(), fallback: true };
    };
    const fetchRR = async () => {
      const query = `state="OPEN" AND reviewers.uuid="${me.uuid}"`;
      const res = await mapLimit(repos, 6, async (slug) => {
        try { return { slug, prs: decodeBitbucketPRs(await bbGet(`/repositories/${ws}/${slug}/pullrequests` + q({ pagelen: "50", fields: PR_FIELDS, q: query }), c.email, c.token), me.uuid).prs, err: null as PRErr | null }; }
        catch (e) { return { slug, prs: [] as PullRequest[], err: e instanceof PRErr ? e : new PRErr(String(e), "net") }; }
      });
      const errors: string[] = [], failed = new Set<string>(), gone = new Set<string>(), prs: PullRequest[] = [];
      for (const r of res) {
        if (!r.err) prs.push(...r.prs);
        else if (r.err.kind === "auth" || r.err.kind === "rate") throw r.err;
        else if (r.err.code === 404) gone.add(r.slug);
        else { errors.push(`${r.slug}: ${r.err.message}`); failed.add(r.slug); }
      }
      return { prs, errors, failed, gone };
    };
    const [m, r] = await Promise.all([fetchMine(), fetchRR()]);
    if (m.fallback && !skip) { persisted.mine404 = [...mine404, ws].sort(); void saveState(); }
    bbMine = await withNewComments(m.prs, c, ws, me.uuid);
    const failed = [...r.failed].map((s) => `bitbucket:${ws}/${s}#`);
    bbRR = [...r.prs, ...bbRR.filter((p) => failed.some((f) => p.id.startsWith(f)))];
    if (r.gone.size) {
      setSetting("prBitbucketRepos", bitbucketRepoList().filter((s) => !r.gone.has(s)).join(","));
      log(`bitbucket repos removed (404): ${[...r.gone].sort().join(",")}`);
    }
    lastBB = Date.now();
    pr.bitbucket = { kind: "ok", name: me.name };
    pr.bitbucketError = r.errors.length ? `저장소 ${r.errors.length}개를 못 읽었어요 · ${r.errors[0]}` : null;
    return true;
  } catch (e) {
    rateLimit("bitbucket", e);
    const m = e instanceof Error ? e.message : String(e);
    if (e instanceof PRErr && e.kind === "auth") resetBitbucketCache();
    pr.bitbucketError = m;
    if (pr.bitbucket.kind !== "ok") pr.bitbucket = { kind: "error", message: m };
    log(`bitbucket refresh error: ${m}`);
    return false;
  }
}

/** comment_count 가 늘어난 내 PR 만 댓글을 따로 가져온다 (한 번에 10개까지). 못 가져오면 직전 값으로 되돌려 다음에 다시. */
async function withNewComments(prs: PullRequest[], c: { email: string; token: string }, ws: string, me: string): Promise<PullRequest[]> {
  const old = persisted.snapshot;
  let fetched = 0;
  const out: PullRequest[] = [];
  for (const p of prs) {
    const was = old?.mine[p.id]?.commentCount;
    if (p.commentCount == null || was == null || p.commentCount <= was) { out.push(p); continue; }
    if ((nextAllowed.bitbucket ?? 0) > Date.now() || fetched >= 10) { out.push({ ...p, commentCount: was }); continue; }
    fetched++;
    try {
      const slug = repoKey(p.id).split("/").pop() ?? "";
      const j = await bbGet(`/repositories/${ws}/${slug}/pullrequests/${p.number}/comments` + q({ sort: "-created_on", pagelen: "20" }), c.email, c.token);
      out.push({ ...p, recentActivity: decodeBitbucketComments(j, me) });
    } catch (e) {
      rateLimit("bitbucket", e);
      out.push({ ...p, commentCount: was });
    }
  }
  return out;
}

export async function bitbucketRepositories(workspace: string): Promise<{ slug: string; name: string; updatedOn: number | null }[]> {
  const c = await bbClient();
  if (!c) throw new PRErr("토큰이 없어요");
  const out: { slug: string; name: string; updatedOn: number | null }[] = [];
  let next: string | null = `/repositories/${workspace}` + q({ pagelen: "100", sort: "-updated_on", fields: "values.slug,values.name,values.updated_on,next" });
  let pages = 0;
  while (next && pages++ < 10) {
    const j = (await bbGet(next, c.email, c.token)) as { values?: { slug: string; name?: string; updated_on?: string }[]; next?: string };
    for (const v of j?.values ?? []) out.push({ slug: v.slug, name: v.name ?? v.slug, updatedOn: v.updated_on ? Date.parse(v.updated_on) : null });
    next = safeNext(j?.next ?? null);
  }
  return out;
}

/** 최근 30일 안에 내가 리뷰어였던 저장소 (워크스페이스별 24시간 캐시). */
export async function recentReviewed(workspace: string, slugs: string[], progress: (done: number, total: number) => void): Promise<string[]> {
  await loadState();
  const cached = persisted.recent?.[workspace];
  if (cached && Date.now() - cached.at < 86400_000) return cached.slugs;
  const c = await bbClient();
  if (!c) return [];
  const me = await bbMe(c).catch(() => null);
  if (!me) return [];
  const since = new Date(Date.now() - 30 * 86400_000).toISOString().replace(/\.\d+Z$/, "Z");
  const query = `reviewers.uuid="${me.uuid}" AND updated_on>${since}`;
  let done = 0;
  const hits = await mapLimit(slugs, 6, async (slug) => {
    let hit = false;
    try {
      const j = (await bbGet(`/repositories/${workspace}/${slug}/pullrequests` + q({ pagelen: "1", q: query, state: ["OPEN", "MERGED", "DECLINED"], fields: "values.id" }), c.email, c.token)) as { values?: unknown[] };
      hit = !!j?.values?.length;
    } catch { /* 건너뜀 */ }
    progress(++done, slugs.length);
    return hit ? slug : null;
  });
  const found = hits.filter((x): x is string => !!x);
  persisted.recent = { ...(persisted.recent ?? {}), [workspace]: { at: Date.now(), slugs: found } };
  void saveState();
  return found;
}

// ---- 로컬 클론 ----

export async function defaultCloneRoots(): Promise<string[]> {
  const home = await native.homeDir();
  return ["projects", "Projects", "dev", "workspace", "IdeaProjects", "source\\repos", "git", "repos"].map((d) => `${home}\\${d}`);
}

export async function cloneRoots(): Promise<string[]> {
  try { const v = JSON.parse(settings.prCloneRoots || "null"); if (Array.isArray(v)) return v; } catch { /* 기본 */ }
  return defaultCloneRoots();
}

/** 이 PC 에 클론된 저장소 중 workspace 에 속한 slug. 폴더 아래 두 단계까지. */
export async function localBitbucketSlugs(workspace: string, roots?: string[]): Promise<string[]> {
  const found = new Set<string>();
  let git: string | null = null;
  const origin = async (dir: string): Promise<string | null> => {
    git ??= (await native.which("git").catch(() => null))?.[0] ?? null;
    if (!git) return null;
    const r = await native.run(git, ["-C", dir, "config", "--get", "remote.origin.url"], { timeoutMs: 5000 });
    return r.code === 0 ? r.stdout.trim() : null;
  };
  const check = async (dir: string) => {
    const url = await origin(dir);
    const p = url ? parseBitbucketRemote(url) : null;
    if (p && p.workspace.toLowerCase() === workspace.toLowerCase()) found.add(p.slug);
  };
  const isRepo = (dir: string) => native.pathExists(`${dir}\\.git`).catch(() => false);
  for (const root of roots ?? (await cloneRoots())) {
    if (!(await native.pathExists(root).catch(() => false))) continue;
    for (const child of await native.listSubdirs(root)) {
      if (child.startsWith(".")) continue;
      const d = `${root}\\${child}`;
      if (await isRepo(d)) { await check(d); continue; }
      for (const g of await native.listSubdirs(d)) if (!g.startsWith(".") && (await isRepo(`${d}\\${g}`))) await check(`${d}\\${g}`);
    }
  }
  return [...found].sort();
}

// ---- 새로고침 ----

function keep(p: PullRequest): boolean {
  let hidden: string[] = [];
  try { hidden = JSON.parse(settings.prHiddenRepos || "[]"); } catch { /* 없음 */ }
  return !hidden.includes(repoKey(p.id)) && !(settings.prHideDrafts && p.isDraft);
}

async function notify(n: PRNotice) {
  const on = { newReviewRequest: settings.prNotifyNewReview, approved: settings.prNotifyApproved, changesRequested: settings.prNotifyChanges, comments: settings.prNotifyComments }[n.kind];
  if (!on) return;
  try {
    let ok = await isPermissionGranted();
    if (!ok) ok = (await requestPermission()) === "granted";
    if (ok) sendNotification({ title: noticeTitle(n), body: noticeBody(n) });
  } catch { /* 알림 불가 */ }
}

function apply(succeeded: Set<PRProvider>) {
  const rawRR = [...ghRR, ...bbRR], rawMine = [...ghMine, ...bbMine];
  pr.reviewRequests = sortReviewRequests(rawRR.filter(keep));
  pr.mine = sortMine(rawMine.filter(keep));
  const trimmed = trimSeen(pr.seen, new Set(rawRR.map((p) => p.id)), succeeded);
  if (trimmed.size !== pr.seen.size) { pr.seen = trimmed; void saveState(); }
  if (!succeeded.size) return;
  let old = persisted.snapshot ?? null;
  const key = settings.prBitbucketWorkspace + "|" + settings.prBitbucketRepos;
  if (succeeded.has("bitbucket") && persisted.repoKey !== key) {
    if (old) old = { ...old, providers: old.providers.filter((p) => p !== "bitbucket") };
    persisted.repoKey = key;
  }
  const next = mergedSnapshot(old, snapshot(rawRR, rawMine, old), succeeded);
  const notices = notifications(old, next, rawRR.filter((p) => succeeded.has(p.provider) && keep(p)), rawMine.filter((p) => succeeded.has(p.provider) && keep(p)));
  notices.forEach((n) => void notify(n));
  persisted.snapshot = next;
  void saveState();
}

export const reapplyFilters = () => apply(new Set());

export async function refreshPR(background = false): Promise<void> {
  await loadState();
  if (pr.loading) { pending = true; return; }
  pr.loading = true;
  try {
    let bg = background;
    do {
      pending = false;
      if (!anyEnabled()) {
        ghRR = []; ghMine = []; bbRR = []; bbMine = [];
        pr.github = { kind: "off" }; pr.bitbucket = { kind: "off" }; pr.githubError = null; pr.bitbucketError = null;
        apply(new Set());
      } else {
        const [g, b] = await Promise.all([refreshGitHub(), refreshBitbucket(bg)]);
        pr.lastRefresh = Date.now();
        const ok = new Set<PRProvider>();
        if (g) ok.add("github");
        if (b) ok.add("bitbucket");
        apply(ok);
      }
      bg = false;
    } while (pending);
  } finally {
    pr.loading = false;
  }
}

export async function refreshIfStale(): Promise<void> {
  if (pr.lastRefresh && Date.now() - pr.lastRefresh < 60_000) return;
  await refreshPR();
}

/** PR 탭이 보이고 목록이 나와 있을 때: 지금 리뷰 요청을 모두 봤다로. */
export function markSeen(): void {
  const ids = pr.reviewRequests.map((p) => p.id);
  if (ids.every((id) => pr.seen.has(id))) return;
  pr.seen = new Set([...pr.seen, ...ids]);
  void saveState();
}

/** 1분마다 "설정한 분이 지났나"만 본다. 패널이 보이면 늘, 숨겨져 있으면 알림이 하나라도 켜져 있을 때만. */
export function startPRLoop(isVisible: () => boolean): () => void {
  void loadState();
  const tick = () => {
    const tabOn = enabledTabs(settings.enabledTabs, ["tasks", "summary", "notes", "pr", "teleport"]).includes("pr");
    if (!tabOn || !anyEnabled()) return;
    const notifies = settings.prNotifyNewReview || settings.prNotifyApproved || settings.prNotifyChanges || settings.prNotifyComments;
    if (!isVisible() && !notifies) return;
    if (pr.lastRefresh && Date.now() - pr.lastRefresh < settings.prRefreshMinutes * 60_000 - 5000) return;
    void refreshPR(!isVisible());
  };
  const t = setInterval(tick, 60_000);
  setTimeout(tick, 5000);
  return () => clearInterval(t);
}

// ---- 승인 ----

export function myName(p: PRProvider): string | null {
  if (p === "github") return pr.github.kind === "ok" ? pr.github.login : null;
  return pr.bitbucket.kind === "ok" ? pr.bitbucket.name : null;
}
export const approvedByMe = (p: PullRequest) => approvedBy(p, myName(p.provider));

/** 사용자가 확인 팝오버에서 누른 경우에만 부른다. */
export async function approve(p: PullRequest, undo = false): Promise<void> {
  if (pr.acting.includes(p.id) || (undo && p.provider === "github") || (p.provider === "bitbucket" && pr.bbNoWrite && !undo)) return;
  pr.acting = [...pr.acting, p.id];
  const errs = { ...pr.actionError }; delete errs[p.id]; pr.actionError = errs;
  try {
    if (p.provider === "github") {
      const parts = githubParts(p.id);
      if (!parts) throw new PRErr("PR 주소를 해석하지 못했어요");
      const gh = await resolveGh(false);
      const t = gh ? await ghToken(gh) : null;
      if (!t) throw new PRErr("gh 로그인이 필요해요");
      try {
        await http(`https://api.github.com/repos/${parts[0]}/${parts[1]}/pulls/${parts[2]}/reviews`, {
          method: "POST", headers: { ...ghHeaders(t), Accept: "application/vnd.github+json" }, body: '{"event":"APPROVE"}',
        }, "GitHub");
      } catch (e) {
        if (e instanceof PRErr && e.code === 422) throw new PRErr("승인할 수 없는 PR 이에요 (이미 닫혔거나 내가 올린 PR)");
        if (e instanceof PRErr && (e.kind === "auth" || e.code === 404)) throw new PRErr("이 저장소에서 승인할 권한이 없어요");
        throw e;
      }
      log(`github approve ${parts[0]}/${parts[1]}#${parts[2]} ok`);
    } else {
      const parts = bitbucketParts(p.id);
      if (!parts) throw new PRErr("PR 주소를 해석하지 못했어요");
      const c = await bbClient();
      if (!c) throw new PRErr("Bitbucket 토큰이 필요해요");
      try {
        await http(`${BB}/repositories/${parts[0]}/${parts[1]}/pullrequests/${parts[2]}/approve`, { method: undo ? "DELETE" : "POST", headers: bbHeaders(c.email, c.token) }, "Bitbucket");
      } catch (e) {
        if (e instanceof PRErr && e.kind === "auth") {
          setSetting("prBitbucketNoWrite", true);
          pr.bbNoWrite = true;
          throw new PRErr("Bitbucket 토큰에 PR 쓰기 권한(write:pullrequest:bitbucket)이 필요해요", "noWrite");
        }
        throw e;
      }
      log(`bitbucket ${undo ? "unapprove" : "approve"} ${parts[0]}/${parts[1]}#${parts[2]} ok`);
    }
    const me = myName(p.provider);
    if (me) {
      const now = Date.now();
      const change = (x: PullRequest) => (x.id !== p.id ? x : undo ? markUnapproved(x, me) : markApproved(x, me, now));
      ghRR = ghRR.map(change); bbRR = bbRR.map(change);
      apply(new Set());
    }
    setTimeout(() => void refreshPR(), 2000);
  } catch (e) {
    rateLimit(p.provider, e);
    pr.actionError = { ...pr.actionError, [p.id]: e instanceof Error ? e.message : String(e) };
  } finally {
    pr.acting = pr.acting.filter((x) => x !== p.id);
  }
}

export function hideRepo(p: PullRequest) {
  let hidden: string[] = [];
  try { hidden = JSON.parse(settings.prHiddenRepos || "[]"); } catch { /* 없음 */ }
  setSetting("prHiddenRepos", JSON.stringify([...new Set([...hidden, repoKey(p.id)])]));
  setTimeout(reapplyFilters, 0);
}

export function unhideRepo(key: string) {
  let hidden: string[] = [];
  try { hidden = JSON.parse(settings.prHiddenRepos || "[]"); } catch { /* 없음 */ }
  setSetting("prHiddenRepos", JSON.stringify(hidden.filter((k) => k !== key)));
  setTimeout(reapplyFilters, 0);
}
