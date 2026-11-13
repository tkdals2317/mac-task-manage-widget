// PR 모델·판단 로직 (Mac PullRequests.swift + GitHubClient/BitbucketClient 의 해석 부분). 네트워크는 쓰지 않는다.

export type PRProvider = "github" | "bitbucket";
export type ReviewState = "approved" | "changesRequested" | "pending" | "commented";
export interface PRReviewer { name: string; state: ReviewState; at?: number | null }
export interface PRActivity { id: string; author: string }
export interface PullRequest {
  id: string; // "github:owner/repo#12" / "bitbucket:ws/slug#34"
  provider: PRProvider;
  repo: string;
  number: number;
  title: string;
  url: string;
  author: string;
  isDraft: boolean;
  createdAt: number;
  updatedAt: number;
  lastCommitAt?: number | null;
  sourceBranch: string;
  targetBranch: string;
  additions?: number | null;
  deletions?: number | null;
  changedFiles?: number | null;
  reviewers: PRReviewer[];
  commentCount?: number | null;
  myReviewAt?: number | null;
  reviewRequested: boolean;
  recentActivity: PRActivity[];
}

export type Approval =
  | { kind: "approved"; n: number; m: number }
  | { kind: "changesRequested" }
  | { kind: "waiting"; n: number; m: number }
  | { kind: "noReviewers" };

export interface PRMineState { approvers: string[]; changers: string[]; activity: string[]; commentCount?: number | null }
export interface PRSnapshot { reviewRequestIDs: string[]; mine: Record<string, PRMineState>; providers: string[] }

export type PRNotice =
  | { kind: "newReviewRequest"; pr: PullRequest }
  | { kind: "approved"; pr: PullRequest; by: string; count: number; total: number; complete: boolean }
  | { kind: "changesRequested"; pr: PullRequest; by: string }
  | { kind: "comments"; pr: PullRequest; authors: string[]; count: number };

export function noticeTitle(n: PRNotice): string {
  switch (n.kind) {
    case "newReviewRequest": return "리뷰 요청";
    case "approved": return n.complete ? "PR 승인 완료 · 머지할 수 있어요" : `PR 승인 (${n.count}/${n.total})`;
    case "changesRequested": return "PR 변경 요청";
    case "comments": return "PR 새 댓글·리뷰";
  }
}

export function noticeBody(n: PRNotice): string {
  const tail = `${n.pr.repo} · ${n.pr.title}`;
  switch (n.kind) {
    case "newReviewRequest": return tail;
    case "approved": return `${n.by} 님이 승인 · ${tail}`;
    case "changesRequested": return `${n.by} 님이 변경 요청 · ${tail}`;
    case "comments": {
      const first = n.authors[0] ?? "(알 수 없음)";
      if (n.authors.length > 1) return `${first} 외 ${n.authors.length - 1}명 · 댓글 ${n.count}개 · ${tail}`;
      return n.count > 1 ? `${first} 님이 댓글 ${n.count}개 · ${tail}` : `${first} 님이 댓글 · ${tail}`;
    }
  }
}

export function approval(pr: PullRequest): Approval {
  if (pr.reviewers.some((r) => r.state === "changesRequested")) return { kind: "changesRequested" };
  const m = pr.reviewers.length;
  if (!m) return { kind: "noReviewers" };
  const n = pr.reviewers.filter((r) => r.state === "approved").length;
  return n === m ? { kind: "approved", n, m } : { kind: "waiting", n, m };
}

export const hasNewCommitsSinceMyReview = (pr: PullRequest) =>
  pr.myReviewAt != null && pr.lastCommitAt != null && pr.lastCommitAt > pr.myReviewAt;

/** 아직 리뷰 안 한 것 먼저, 그 안에서 오래된 것부터. */
export function sortReviewRequests(prs: PullRequest[]): PullRequest[] {
  return [...prs].sort((a, b) => {
    const x = a.myReviewAt != null, y = b.myReviewAt != null;
    if (x !== y) return x ? 1 : -1;
    if (a.createdAt !== b.createdAt) return a.createdAt - b.createdAt;
    return a.id < b.id ? -1 : 1;
  });
}

const rank = (pr: PullRequest) => ({ changesRequested: 0, approved: 1, waiting: 2, noReviewers: 2 })[approval(pr).kind];
/** 변경 요청 → 승인 → 대기, 같으면 최근 갱신 먼저. */
export function sortMine(prs: PullRequest[]): PullRequest[] {
  return [...prs].sort((a, b) => rank(a) - rank(b) || b.updatedAt - a.updatedAt || (a.id < b.id ? -1 : 1));
}

export const isStale = (pr: PullRequest, now: number, days: number) => now - pr.createdAt >= days * 86400_000;
export const waitDays = (pr: PullRequest, now: number) => Math.max(0, Math.floor((now - pr.createdAt) / 86400_000));

export function relative(at: number, now: number): string {
  const s = Math.max(0, (now - at) / 1000);
  if (s < 3600) return `${Math.max(1, Math.floor(s / 60))}분 전`;
  if (s < 86400) return `${Math.floor(s / 3600)}시간 전`;
  return `${Math.floor(s / 86400)}일 전`;
}

export const providerOf = (id: string): PRProvider | null => {
  const p = id.split(":")[0];
  return p === "github" || p === "bitbucket" ? p : null;
};
export const repoKey = (id: string) => id.split("#")[0];

function idParts(id: string, prefix: string): [string, string, number] | null {
  if (!id.startsWith(prefix)) return null;
  const hash = id.lastIndexOf("#");
  const n = Number(id.slice(hash + 1));
  const path = id.slice(prefix.length, hash).split("/");
  return hash > 0 && Number.isInteger(n) && path.length === 2 ? [path[0], path[1], n] : null;
}
export const githubParts = (id: string) => idParts(id, "github:");
export const bitbucketParts = (id: string) => idParts(id, "bitbucket:");

export const approvedBy = (pr: PullRequest, me: string | null) => !!me && pr.reviewers.some((r) => r.name === me && r.state === "approved");

export function markApproved(pr: PullRequest, me: string, at: number): PullRequest {
  const reviewers = pr.reviewers.some((r) => r.name === me)
    ? pr.reviewers.map((r) => (r.name === me ? { ...r, state: "approved" as const, at } : r))
    : [...pr.reviewers, { name: me, state: "approved" as const, at }];
  return { ...pr, reviewers, myReviewAt: at };
}

export function markUnapproved(pr: PullRequest, me: string): PullRequest {
  return { ...pr, reviewers: pr.reviewers.map((r) => (r.name === me ? { ...r, state: "pending" as const, at: null } : r)), myReviewAt: null };
}

// ---- 리뷰 요청 거르기 ----

export type ReviewStatus = "unreviewed" | "newCommits" | "reviewed";
export const REVIEW_STATUSES: ReviewStatus[] = ["unreviewed", "newCommits", "reviewed"];
export const statusLabel: Record<ReviewStatus, string> = { unreviewed: "아직 리뷰 안 함", newCommits: "리뷰함 · 새 커밋", reviewed: "리뷰함" };
export const statusShort: Record<ReviewStatus, string> = { unreviewed: "안 함", newCommits: "새 커밋", reviewed: "리뷰함" };

export const reviewStatus = (pr: PullRequest): ReviewStatus =>
  pr.myReviewAt == null ? "unreviewed" : hasNewCommitsSinceMyReview(pr) ? "newCommits" : "reviewed";

export function filterReviews(prs: PullRequest[], states: Set<string>, repos: Set<string>, authors: Set<string>): PullRequest[] {
  return prs.filter((p) =>
    (!states.size || states.has(reviewStatus(p))) && (!repos.size || repos.has(repoKey(p.id))) && (!authors.size || authors.has(p.author)));
}

export interface Facet { key: string; label: string; provider: PRProvider | null; count: number }
export type FacetKind = "status" | "repo" | "author";

/** 팝오버의 값과 개수. 이 차원의 선택은 개수에 적용하지 않는다 (하나 골라도 나머지가 사라지지 않게). */
export function facets(prs: PullRequest[], kind: FacetKind, states: Set<string>, repos: Set<string>, authors: Set<string>): Facet[] {
  const none = new Set<string>();
  const base = filterReviews(prs, kind === "status" ? none : states, kind === "repo" ? none : repos, kind === "author" ? none : authors);
  if (kind === "status") {
    return REVIEW_STATUSES.map((st) => ({ key: st, label: statusLabel[st], provider: null, count: base.filter((p) => reviewStatus(p) === st).length }));
  }
  const map = new Map<string, Facet>();
  for (const p of base) {
    const key = kind === "repo" ? repoKey(p.id) : p.author;
    const f = map.get(key) ?? { key, label: kind === "repo" ? p.repo : p.author, provider: kind === "repo" ? p.provider : null, count: 0 };
    f.count++;
    map.set(key, f);
  }
  const live = [...map.values()].sort((a, b) => b.count - a.count || a.label.localeCompare(b.label, "ko"));
  const selected = kind === "repo" ? repos : authors;
  const gone = [...selected].filter((k) => !map.has(k)).sort().map((key) =>
    kind === "repo" ? { key, label: key.split("/").pop() ?? key, provider: providerOf(key), count: 0 } : { key, label: key, provider: null, count: 0 });
  return [...live, ...gone];
}

// ---- 알림 기준 ----

const ACTIVITY_CAP = 50;

export function snapshot(reviewRequests: PullRequest[], mine: PullRequest[], old?: PRSnapshot | null): PRSnapshot {
  const states: Record<string, PRMineState> = {};
  for (const pr of mine) {
    const o = old?.mine[pr.id];
    const current = pr.recentActivity.map((a) => a.id);
    states[pr.id] = {
      approvers: pr.reviewers.filter((r) => r.state === "approved").map((r) => r.name).sort(),
      changers: pr.reviewers.filter((r) => r.state === "changesRequested").map((r) => r.name).sort(),
      activity: [...current, ...(o?.activity ?? []).filter((x) => !current.includes(x))].slice(0, ACTIVITY_CAP),
      commentCount: pr.commentCount ?? o?.commentCount ?? null,
    };
  }
  return { reviewRequestIDs: reviewRequests.filter((p) => p.reviewRequested).map((p) => p.id).sort(), mine: states, providers: [] };
}

/** 이번에 성공한 제공자 항목만 새 것으로, 나머지는 직전 그대로. */
export function mergedSnapshot(old: PRSnapshot | null, fresh: PRSnapshot, succeeded: Set<PRProvider>): PRSnapshot {
  const ok = (id: string) => { const p = providerOf(id); return p != null && succeeded.has(p); };
  const ids = new Set(fresh.reviewRequestIDs.filter(ok));
  const mine: Record<string, PRMineState> = Object.fromEntries(Object.entries(fresh.mine).filter(([k]) => ok(k)));
  if (old) {
    old.reviewRequestIDs.filter((x) => !ok(x)).forEach((x) => ids.add(x));
    for (const [k, v] of Object.entries(old.mine)) if (!ok(k)) mine[k] = v;
  }
  return { reviewRequestIDs: [...ids].sort(), mine, providers: [...new Set([...(old?.providers ?? []), ...succeeded])].sort() };
}

export function trimSeen(seen: Set<string>, present: Set<string>, succeeded: Set<PRProvider>): Set<string> {
  return new Set([...seen].filter((id) => { const p = providerOf(id); return p && succeeded.has(p) ? present.has(id) : true; }));
}

/** 직전 기준과 비교해 알릴 것. 첫 실행·처음 켠 제공자는 알리지 않는다. */
export function notifications(old: PRSnapshot | null, next: PRSnapshot, reviewRequests: PullRequest[], mine: PullRequest[]): PRNotice[] {
  if (!old) return [];
  const out: PRNotice[] = [];
  const oldRR = new Set(old.reviewRequestIDs), newRR = new Set(next.reviewRequestIDs);
  for (const pr of reviewRequests) {
    if (pr.reviewRequested && old.providers.includes(pr.provider) && newRR.has(pr.id) && !oldRR.has(pr.id)) out.push({ kind: "newReviewRequest", pr });
  }
  for (const pr of mine) {
    if (!old.providers.includes(pr.provider)) continue;
    const was = old.mine[pr.id];
    const total = pr.reviewers.length;
    const wasApprovers = new Set(was?.approvers ?? []);
    const fresh = pr.reviewers.filter((r) => r.state === "approved" && !wasApprovers.has(r.name));
    const a = approval(pr);
    const allDone = a.kind === "approved" && a.n === total;
    let n = wasApprovers.size;
    fresh.forEach((r, i) => { n++; out.push({ kind: "approved", pr, by: r.name, count: n, total, complete: allDone && i === fresh.length - 1 }); });
    const wasChangers = new Set(was?.changers ?? []);
    for (const r of pr.reviewers) if (r.state === "changesRequested" && !wasChangers.has(r.name)) out.push({ kind: "changesRequested", pr, by: r.name });
    if (was) {
      const seen = new Set(was.activity), ids = new Set<string>();
      const fresh2 = pr.recentActivity.filter((x) => !seen.has(x.id) && !ids.has(x.id) && (ids.add(x.id), true));
      if (fresh2.length) out.push({ kind: "comments", pr, authors: [...new Set(fresh2.map((x) => x.author))], count: fresh2.length });
    }
  }
  return out;
}

export const badgeCount = (rr: PullRequest[], mine: PullRequest[], seen: Set<string>) =>
  rr.filter((p) => p.reviewRequested && !seen.has(p.id)).length + mine.filter((p) => approval(p).kind === "changesRequested").length;

export const todoTitle = (pr: PullRequest, isReview: boolean) => (isReview ? "[PR 리뷰] " : "[PR] ") + pr.title;

/** ISO 8601. 소수 초·오프셋 모두 Date 가 읽는다. */
export const parseDate = (s: unknown): number | null => {
  if (typeof s !== "string" || !s) return null;
  const t = Date.parse(s.replace(/\.(\d{3})\d+/, ".$1"));
  return isNaN(t) ? null : t;
};

// ---- GitHub GraphQL ----

const GH_FIELDS = `number title url isDraft createdAt updatedAt additions deletions changedFiles headRefName baseRefName repository { nameWithOwner name } author { login } comments { totalCount } commits(last: 1) { nodes { commit { committedDate } } } reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } ... on Team { name } } } } latestOpinionatedReviews(first: 20) { nodes { author { login } state submittedAt } }`;
const GH_ACTIVITY = `recentComments: comments(last: 20) { nodes { id author { login } } } recentReviews: reviews(last: 20) { nodes { id author { login } state } } threads: reviewThreads(last: 20) { nodes { comments(first: 1) { nodes { id author { login } } } } }`;
const ghSearch = (q: string, extra = "") => `search(query: "${q}", type: ISSUE, first: 50) { nodes { ... on PullRequest { ${GH_FIELDS} ${extra} } } }`;
export const GH_QUERY = `query { viewer { login } requested: ${ghSearch("is:pr is:open review-requested:@me archived:false")} reviewed: ${ghSearch("is:pr is:open reviewed-by:@me -author:@me archived:false")} mine: ${ghSearch("is:pr is:open author:@me archived:false", GH_ACTIVITY)} }`;

/* eslint-disable @typescript-eslint/no-explicit-any */
export function decodeGitHub(json: any, me: string): { reviewRequests: PullRequest[]; mine: PullRequest[] } {
  if (!json?.data && json?.errors?.[0]?.message) throw new Error(json.errors[0].message);
  const d = json?.data ?? {};
  const prs = (s: any, requested: boolean) =>
    ((s?.nodes ?? []) as any[]).filter(Boolean).map((n) => ghPR(n, me)).filter((p): p is PullRequest => !!p).map((p) => ({ ...p, reviewRequested: requested }));
  const seen = new Set<string>();
  const rr = [...prs(d.requested, true), ...prs(d.reviewed, false)].filter((p) => !seen.has(p.id) && (seen.add(p.id), true));
  return { reviewRequests: rr, mine: prs(d.mine, true) };
}

function ghPR(n: any, me: string): PullRequest | null {
  const created = parseDate(n.createdAt);
  if (n.number == null || !n.url || !n.repository || created == null) return null;
  const reviewers: PRReviewer[] = [];
  let myReviewAt: number | null = null;
  for (const r of (n.latestOpinionatedReviews?.nodes ?? []).filter(Boolean)) {
    const state = ({ APPROVED: "approved", CHANGES_REQUESTED: "changesRequested", COMMENTED: "commented" } as Record<string, ReviewState>)[r.state];
    if (!state) continue;
    const name = r.author?.login ?? "(알 수 없음)";
    const at = parseDate(r.submittedAt);
    reviewers.push({ name, state, at });
    if (name === me && at != null) myReviewAt = Math.max(myReviewAt ?? at, at);
  }
  for (const r of (n.reviewRequests?.nodes ?? []).filter(Boolean)) {
    const name = r.requestedReviewer?.login ?? r.requestedReviewer?.name;
    if (!name || reviewers.some((x) => x.name === name)) continue;
    reviewers.push({ name, state: "pending", at: null });
  }
  const activity: PRActivity[] = [];
  const ids = new Set<string>();
  const add = (i: any) => {
    if (!i?.id || i.author?.login === me || ids.has(i.id)) return;
    ids.add(i.id);
    activity.push({ id: i.id, author: i.author?.login ?? "(알 수 없음)" });
  };
  (n.recentComments?.nodes ?? []).forEach(add);
  (n.recentReviews?.nodes ?? []).forEach((x: any) => { if (x?.state === "COMMENTED") add(x); });
  (n.threads?.nodes ?? []).forEach((t: any) => add((t?.comments?.nodes ?? []).filter(Boolean)[0]));
  const commits = (n.commits?.nodes ?? []).filter(Boolean);
  return {
    id: `github:${n.repository.nameWithOwner}#${n.number}`, provider: "github", repo: n.repository.name, number: n.number,
    title: n.title ?? "", url: n.url, author: n.author?.login ?? "(알 수 없음)", isDraft: !!n.isDraft,
    createdAt: created, updatedAt: parseDate(n.updatedAt) ?? created, lastCommitAt: parseDate(commits[commits.length - 1]?.commit?.committedDate),
    sourceBranch: n.headRefName ?? "", targetBranch: n.baseRefName ?? "",
    additions: n.additions ?? null, deletions: n.deletions ?? null, changedFiles: n.changedFiles ?? null,
    reviewers, commentCount: n.comments?.totalCount ?? null, myReviewAt, reviewRequested: true, recentActivity: activity,
  };
}

// ---- Bitbucket ----

export function decodeBitbucketPRs(json: any, me: string): { prs: PullRequest[]; next: string | null } {
  const prs = ((json?.values ?? []) as any[]).map((v): PullRequest | null => {
    const created = parseDate(v.created_on);
    const dest = v.destination?.repository?.full_name;
    if (created == null || !dest) return null;
    const reviewers: PRReviewer[] = [];
    let myReviewAt: number | null = null;
    const reacted = new Set<string>();
    for (const p of v.participants ?? []) {
      if (p.role !== "REVIEWER") continue;
      const name = p.user?.display_name ?? p.user?.nickname ?? "(알 수 없음)";
      const at = parseDate(p.participated_on);
      const state: ReviewState = p.state === "changes_requested" ? "changesRequested" : p.approved ? "approved" : "pending";
      reviewers.push({ name, state, at: state === "pending" ? null : at });
      if (p.user?.uuid) reacted.add(p.user.uuid);
      if (p.user?.uuid === me && state !== "pending" && at != null) myReviewAt = at;
    }
    for (const r of v.reviewers ?? []) {
      if (r.uuid && reacted.has(r.uuid)) continue;
      reviewers.push({ name: r.display_name ?? r.nickname ?? "(알 수 없음)", state: "pending", at: null });
    }
    const slug = dest.split("/").pop() ?? dest;
    return {
      id: `bitbucket:${dest}#${v.id}`, provider: "bitbucket", repo: v.destination?.repository?.name ?? slug, number: v.id,
      title: v.title ?? "", url: v.links?.html?.href ?? `https://bitbucket.org/${dest}/pull-requests/${v.id}`,
      author: v.author?.display_name ?? v.author?.nickname ?? "(알 수 없음)", isDraft: !!v.draft,
      createdAt: created, updatedAt: parseDate(v.updated_on) ?? created, lastCommitAt: null,
      sourceBranch: v.source?.branch?.name ?? "", targetBranch: v.destination?.branch?.name ?? "",
      reviewers, commentCount: v.comment_count ?? null, myReviewAt, reviewRequested: true, recentActivity: [],
    };
  }).filter((p): p is PullRequest => !!p);
  return { prs, next: json?.next ?? null };
}

export function decodeBitbucketComments(json: any, me: string): PRActivity[] {
  return ((json?.values ?? []) as any[])
    .filter((c) => !c.deleted && c.user?.uuid !== me)
    .map((c) => ({ id: `bb:${c.id}`, author: c.user?.display_name ?? c.user?.nickname ?? "(알 수 없음)" }));
}

export function decodeWorkspaces(json: any): { workspaces: { slug: string; name: string }[]; next: string | null } {
  const ws = ((json?.values ?? []) as any[]).map((v) => {
    const slug = v.workspace?.slug ?? v.slug;
    return slug ? { slug, name: v.workspace?.name ?? v.name ?? slug } : null;
  }).filter((x): x is { slug: string; name: string } => !!x);
  return { workspaces: ws, next: json?.next ?? null };
}
/* eslint-enable @typescript-eslint/no-explicit-any */

/** next 는 https://api.bitbucket.org 일 때만 따라간다 (토큰이 다른 곳으로 나가지 않게). */
export function safeNext(s: string | null): string | null {
  if (!s) return null;
  try { const u = new URL(s); return u.protocol === "https:" && u.hostname.toLowerCase() === "api.bitbucket.org" ? s : null; } catch { return null; }
}

/** `git@bitbucket.org:ws/slug.git`, `https://user@bitbucket.org/ws/slug.git`, `ssh://git@bitbucket.org:7999/ws/slug` */
export function parseBitbucketRemote(remote: string): { workspace: string; slug: string } | null {
  const s = remote.trim();
  const i = s.toLowerCase().indexOf("bitbucket.org");
  if (i < 0) return null;
  if (i > 0 && s[i - 1] !== "@" && s[i - 1] !== "/") return null;
  let path = s.slice(i + "bitbucket.org".length);
  if (path.startsWith(":")) {
    path = path.slice(1);
    const m = /^(\d+)\//.exec(path);
    if (m) path = path.slice(m[1].length);
  }
  path = path.replace(/^\/+|\/+$/g, "").replace(/\.git$/, "");
  const parts = path.split("/");
  return parts.length >= 2 && parts[0] && parts[1] ? { workspace: parts[0], slug: parts[1] } : null;
}

/** git config 의 [remote "origin"] url. */
export function originFromConfig(text: string): string | null {
  let inOrigin = false;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (line.startsWith("[")) inOrigin = line.replace(/\s/g, "") === '[remote"origin"]';
    else if (inOrigin && line.startsWith("url") && line.includes("=")) return line.slice(line.indexOf("=") + 1).trim();
  }
  return null;
}

export function classifyHttp(code: number, remaining: string | null, retryAfter: string | null, reset: string | null, provider: string, now = Date.now()):
  { kind: "rate"; waitSec: number | null; message: string } | { kind: "auth" } | { kind: "http"; code: number } {
  if (code === 429 || retryAfter != null || (code === 403 && remaining === "0")) {
    let wait = retryAfter != null ? Number(retryAfter) : null;
    if (wait == null && reset != null) wait = Math.max(0, Number(reset) - now / 1000);
    return { kind: "rate", waitSec: wait, message: `${provider} 요청 한도 초과 — 잠시 후 다시 시도` };
  }
  return code === 401 || code === 403 ? { kind: "auth" } : { kind: "http", code };
}

/** 셸에 그대로 붙여도 되는 브랜치면 그대로, 아니면 작은따옴표. */
export function checkoutCommand(branch: string): string {
  const safe = /^[\p{L}\p{N}/_.-]+$/u.test(branch);
  return "git fetch origin && git checkout " + (safe ? branch : `'${branch.replace(/'/g, "'\\''")}'`);
}
