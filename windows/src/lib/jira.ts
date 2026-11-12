// Mac JiraClient / JiraVersions 포팅.
import { basicAuth, HttpError, requestJSON } from "./http";

export const JIRA_KEYCHAIN_SERVICE = "com.lsm0506.TaskWidget.jira";
export const JIRA_TOKEN_URL = "https://id.atlassian.com/manage-profile/security/api-tokens";

export interface JiraTransition { id: string; name: string; toName: string; toCategory: string }
export interface JiraIssue {
  id: string; // issue key
  summary: string;
  status: string;
  statusCategory: string; // new | indeterminate | done
  priority?: string;
  updated: number; // epoch ms
  fixVersions: string[];
  transitions?: JiraTransition[];
}

/** userMessage 를 그대로 화면에 보여준다. */
export class JiraError extends Error {
  constructor(public kind: "unauthorized" | "badQuery" | "http" | "network" | "message", public userMessage: string) {
    super(userMessage);
  }
}

export const DEFAULT_JQL = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC";
export const effectiveJQL = (custom: string) => custom.trim() || DEFAULT_JQL;

/** https 주소만 (토큰·링크가 엉뚱한 곳으로 나가지 않게). 끝 '/' 제거. */
export function normalizeBase(raw: string): string | null {
  try {
    const u = new URL(raw.trim());
    return u.protocol === "https:" && u.hostname.includes(".") ? u.href.replace(/\/+$/, "") : null;
  } catch { return null; }
}

export const issueURL = (base: string, key: string) => `${base.replace(/\/+$/, "")}/browse/${encodeURIComponent(key)}`;

// ---- 오류 ----
export function transitionError(status: number): JiraError {
  switch (status) {
    case 400: return new JiraError("message", "이 상태로 바꿀 수 없음 (필수 입력값이 필요할 수 있음 — Jira 에서 직접 변경)");
    case 401: return new JiraError("message", "토큰 만료 — 설정에서 토큰을 다시 입력하세요");
    case 403: return new JiraError("message", "권한 없음");
    case 404: return new JiraError("message", "이슈 없음");
    default: return new JiraError("http", `HTTP ${status}`);
  }
}

function searchError(e: unknown): JiraError {
  if (e instanceof JiraError) return e;
  if (e instanceof HttpError) {
    if (e.status === 401 || e.status === 403) return new JiraError("unauthorized", "토큰 확인 필요 (401/403)");
    if (e.status === 400) return new JiraError("badQuery", `JQL 오류: ${errorMessage(e.body)}`);
    return new JiraError("http", `HTTP ${e.status}`);
  }
  return new JiraError("network", `네트워크: ${e instanceof Error ? e.message : String(e)}`);
}

export function errorMessage(body: string): string {
  try { return (JSON.parse(body) as { errorMessages?: string[] }).errorMessages?.[0] ?? "요청 오류"; } catch { return "요청 오류"; }
}

// ---- 디코딩 ----
interface RawTransition { id: string; name: string; to: { name: string; statusCategory?: { key: string } } }
interface RawIssue {
  key: string;
  fields: {
    summary: string; status: { name: string; statusCategory: { key: string } };
    priority?: { name: string } | null; updated: string; fixVersions?: { name: string }[] | null;
  };
  transitions?: RawTransition[];
}

const toTransition = (t: RawTransition): JiraTransition =>
  ({ id: t.id, name: t.name, toName: t.to.name, toCategory: t.to.statusCategory?.key ?? "" });

/** Jira 날짜 "2026-11-12T08:30:00.000+0900" → epoch ms. 못 읽으면 0. */
export function parseJiraDate(s: string): number {
  const t = Date.parse(s.replace(/([+-]\d{2})(\d{2})$/, "$1:$2"));
  return Number.isNaN(t) ? 0 : t;
}

export function decodePage(r: { issues: RawIssue[]; isLast?: boolean }): { issues: JiraIssue[]; truncated: boolean } {
  return {
    issues: r.issues.map((i) => ({
      id: i.key,
      summary: i.fields.summary,
      status: i.fields.status.name,
      statusCategory: i.fields.status.statusCategory.key,
      priority: i.fields.priority?.name,
      updated: parseJiraDate(i.fields.updated),
      fixVersions: (i.fields.fixVersions ?? []).map((v) => v.name),
      transitions: i.transitions?.map(toTransition),
    })),
    truncated: r.isLast === false, // 서버에 더 있는데 100건에서 잘림
  };
}

// ---- 네트워크 ----
export interface JiraCreds { baseURL: string; email: string; token: string }
const headers = (c: JiraCreds) => ({ Authorization: basicAuth(c.email, c.token) });

export async function fetchMyOpenIssues(c: JiraCreds, jql: string) {
  const q = new URLSearchParams({
    jql,
    fields: "summary,status,priority,updated,fixVersions",
    maxResults: "100",
    // 상태 변경 팝오버가 열 때마다 기다리지 않게, 바꿀 수 있는 상태를 목록과 같이 받는다.
    expand: "transitions",
  });
  try {
    return decodePage(await requestJSON(`${c.baseURL}/rest/api/3/search/jql?${q}`, { headers: headers(c) }));
  } catch (e) { throw searchError(e); }
}

const transitionsURL = (c: JiraCreds, key: string) => `${c.baseURL}/rest/api/3/issue/${encodeURIComponent(key)}/transitions`;

export async function fetchTransitions(c: JiraCreds, key: string): Promise<JiraTransition[]> {
  try {
    const r = await requestJSON<{ transitions: RawTransition[] }>(transitionsURL(c, key), { headers: headers(c) });
    return r.transitions.map(toTransition);
  } catch (e) {
    throw e instanceof HttpError ? transitionError(e.status) : searchError(e);
  }
}

export async function doTransition(c: JiraCreds, key: string, transitionId: string): Promise<void> {
  try {
    await requestJSON(transitionsURL(c, key), { method: "POST", headers: headers(c), body: { transition: { id: transitionId } } });
  } catch (e) {
    throw e instanceof HttpError ? transitionError(e.status) : searchError(e);
  }
}

// ---- 표시 순서 ----
const categoryRank = (k: string) => (k === "indeterminate" ? 0 : k === "new" ? 1 : 2);

export function sortedForDisplay(issues: JiraIssue[]): JiraIssue[] {
  return [...issues].sort((a, b) => {
    const ra = categoryRank(a.statusCategory), rb = categoryRank(b.statusCategory);
    if (ra !== rb) return ra - rb;
    if (a.status !== b.status) return a.status < b.status ? -1 : 1;
    return b.updated - a.updated;
  });
}

export function groupedByStatus(issues: JiraIssue[]): { status: string; issues: JiraIssue[] }[] {
  const out: { status: string; issues: JiraIssue[] }[] = [];
  for (const i of sortedForDisplay(issues)) {
    const last = out[out.length - 1];
    if (last && last.status === i.status) last.issues.push(i);
    else out.push({ status: i.status, issues: [i] });
  }
  return out;
}

// ---- 버전 ----
export type VersionFilter = { kind: "all" } | { kind: "none" } | { kind: "named"; name: string };
const NONE_TOKEN = "\u0001none";

export function parseVersionFilter(storage: string): VersionFilter {
  return storage === "" ? { kind: "all" } : storage === NONE_TOKEN ? { kind: "none" } : { kind: "named", name: storage };
}
export function versionFilterStorage(f: VersionFilter): string {
  return f.kind === "all" ? "" : f.kind === "none" ? NONE_TOKEN : f.name;
}
export const sameFilter = (a: VersionFilter, b: VersionFilter) => versionFilterStorage(a) === versionFilterStorage(b);

const collator = new Intl.Collator("en", { numeric: true });
/** 먼저 나갈 버전 먼저 (숫자 인지 비교 오름차순: 15.5.a → 15.6.0, 동률은 이름순). */
export function releaseOrder(a: string, b: string): number {
  const r = collator.compare(a, b);
  return r !== 0 ? r : a < b ? -1 : a > b ? 1 : 0;
}

export function versionCounts(issues: JiraIssue[]): { versions: { name: string; count: number }[]; noneCount: number } {
  const c = new Map<string, number>();
  let none = 0;
  for (const i of issues) {
    if (i.fixVersions.length === 0) none++;
    for (const v of new Set(i.fixVersions)) c.set(v, (c.get(v) ?? 0) + 1);
  }
  return { versions: [...c.keys()].sort(releaseOrder).map((name) => ({ name, count: c.get(name)! })), noneCount: none };
}

export function filterByVersion(issues: JiraIssue[], f: VersionFilter): JiraIssue[] {
  switch (f.kind) {
    case "all": return issues;
    case "none": return issues.filter((i) => i.fixVersions.length === 0);
    case "named": return issues.filter((i) => i.fixVersions.includes(f.name));
  }
}

/** 버전별 묶음. title null = "버전 없음". 여러 버전 이슈는 각 버전에 한 번씩. */
export function groupedByVersion(issues: JiraIssue[]): { title: string | null; issues: JiraIssue[] }[] {
  const sorted = sortedForDisplay(issues);
  const out: { title: string | null; issues: JiraIssue[] }[] = versionCounts(issues).versions.map((v) => ({
    title: v.name, issues: sorted.filter((i) => i.fixVersions.includes(v.name)),
  }));
  const none = sorted.filter((i) => i.fixVersions.length === 0);
  if (none.length) out.push({ title: null, issues: none });
  return out;
}

/** 모든 버전 이름이 같은 "XXX_" 접두어(첫 '_' 까지 포함)로 시작하면 그 접두어, 아니면 "". 접두어를 빼면 빈 문자열이 되는 이름이 있으면 "". */
export function commonPrefix(names: string[]): string {
  const i = names[0]?.indexOf("_") ?? -1;
  if (i < 0) return "";
  const prefix = names[0].slice(0, i + 1);
  return names.every((n) => n.startsWith(prefix) && n.length > prefix.length) ? prefix : "";
}

export const displayVersion = (name: string, prefix: string) => (name.startsWith(prefix) ? name.slice(prefix.length) : name);

/** 이슈 옆 버전 칩. 여러 버전이면 가장 먼저 나갈 버전 + "+n". */
export function versionTag(issue: JiraIssue, prefix = ""): string | null {
  const first = [...issue.fixVersions].sort(releaseOrder)[0];
  if (first === undefined) return null;
  const shown = displayVersion(first, prefix);
  return issue.fixVersions.length > 1 ? `${shown} +${issue.fixVersions.length - 1}` : shown;
}
