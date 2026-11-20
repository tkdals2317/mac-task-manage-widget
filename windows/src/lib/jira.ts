// Mac JiraClient / JiraVersions 포팅.
import { basicAuth, HttpError, requestBytes, requestJSON } from "./http";
import { isIssueKey } from "./e2eCore";

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

// ---- E2E: 이슈 내용·댓글·첨부 (Mac JiraIssueDetail·JiraClient) ----
export interface JiraRelated { relation: string; key: string; summary: string; status: string }
export interface JiraAttachment { id: string; filename: string; mimeType: string; size: number; content: string }
/** E2E 검증에 넘길 이슈 본문 (REST API v2: 설명·댓글이 위키 마크업 문자열로 온다). */
export interface JiraIssueDetail {
  key: string; summary: string; type: string; status: string; priority: string; assignee: string; reporter: string;
  labels: string[]; components: string[]; fixVersions: string[]; description: string; parent: JiraRelated | null; related: JiraRelated[];
  comments: { author: string; created: string; body: string }[]; attachments: JiraAttachment[]; remoteLinks: { title: string; url: string }[];
}
export const isImageAttachment = (a: JiraAttachment) => a.mimeType.toLowerCase().startsWith("image/");

const DETAIL_FIELDS = "summary,description,status,issuetype,priority,assignee,reporter,labels,components,fixVersions,parent,subtasks,issuelinks,comment,attachment";
type Obj = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any
const str = (v: unknown) => (typeof v === "string" ? v : "");
const names = (v: unknown) => (Array.isArray(v) ? v.map((x) => str(x?.name)).filter(Boolean) : []);

export function decodeIssueDetail(raw: Obj): JiraIssueDetail {
  const f: Obj = raw.fields ?? {};
  const rel = (r: Obj, relation: string): JiraRelated => ({ relation, key: str(r.key), summary: str(r.fields?.summary), status: str(r.fields?.status?.name) });
  const related: JiraRelated[] = (Array.isArray(f.subtasks) ? f.subtasks : []).map((s: Obj) => rel(s, "하위 작업"));
  for (const l of Array.isArray(f.issuelinks) ? f.issuelinks : []) {
    if (l.outwardIssue) related.push(rel(l.outwardIssue, str(l.type?.outward) || "연결"));
    if (l.inwardIssue) related.push(rel(l.inwardIssue, str(l.type?.inward) || "연결"));
  }
  return {
    key: str(raw.key), summary: str(f.summary), type: str(f.issuetype?.name), status: str(f.status?.name), priority: str(f.priority?.name),
    assignee: str(f.assignee?.displayName), reporter: str(f.reporter?.displayName), labels: Array.isArray(f.labels) ? f.labels.filter((x: unknown) => typeof x === "string") : [],
    components: names(f.components), fixVersions: names(f.fixVersions), description: str(f.description), parent: f.parent ? rel(f.parent, "상위") : null, related,
    comments: (Array.isArray(f.comment?.comments) ? f.comment.comments : []).map((c: Obj) => ({ author: str(c.author?.displayName), created: str(c.created), body: str(c.body) })),
    attachments: (Array.isArray(f.attachment) ? f.attachment : []).flatMap((a: Obj) =>
      a.id ? [{ id: String(a.id), filename: str(a.filename) || String(a.id), mimeType: str(a.mimeType), size: typeof a.size === "number" ? a.size : 0, content: str(a.content) }] : []),
    remoteLinks: [],
  };
}

export function decodeRemoteLinks(raw: unknown): { title: string; url: string }[] {
  return (Array.isArray(raw) ? raw : []).flatMap((r: Obj) => (str(r?.object?.url) ? [{ title: str(r.object.title) || str(r.object.url), url: str(r.object.url) }] : []));
}

function detailError(e: unknown): JiraError {
  if (e instanceof JiraError) return e;
  if (e instanceof HttpError) {
    if (e.status === 401 || e.status === 403) return new JiraError("unauthorized", "토큰 확인 필요 (401/403)");
    if (e.status === 404) return new JiraError("message", "이슈를 찾지 못했어요 (없거나 볼 권한이 없어요)");
    return new JiraError("http", `HTTP ${e.status}`);
  }
  return new JiraError("network", `네트워크: ${e instanceof Error ? e.message : String(e)}`);
}

/** 이슈 본문·댓글·연결·첨부 목록. 원격 링크(PR 등)는 실패해도 빈 목록으로. */
export async function fetchIssueDetail(c: JiraCreds, key: string): Promise<JiraIssueDetail> {
  if (!isIssueKey(key)) throw new JiraError("message", `이슈 키가 올바르지 않아요 (${key})`);
  let d: JiraIssueDetail;
  try {
    d = decodeIssueDetail(await requestJSON(`${c.baseURL}/rest/api/2/issue/${key}?fields=${DETAIL_FIELDS}`, { headers: headers(c) }));
  } catch (e) { throw detailError(e); }
  // 응답의 key 가 요청한 키와 다르면 (이동·잘못된 응답) 다른 이슈 내용을 쓰지 않는다
  if (d.key !== key) throw new JiraError("message", `요청한 이슈(${key})와 다른 이슈(${d.key || "?"})가 왔어요`);
  try { d.remoteLinks = decodeRemoteLinks(await requestJSON(`${c.baseURL}/rest/api/2/issue/${key}/remotelink`, { headers: headers(c) })); } catch { /* 빈 목록 */ }
  return d;
}

/** 첨부 내려받기. redirect=false 면 미디어 서버로 넘기지 않고 바로 내용을 준다 (인증 헤더가 다른 호스트로 가지 않게). */
export async function downloadAttachment(c: JiraCreds, a: JiraAttachment): Promise<Uint8Array> {
  let u: URL;
  try { u = new URL(a.content); } catch { throw new JiraError("message", "첨부 주소 없음"); }
  if (u.host !== new URL(c.baseURL).host) throw new JiraError("message", "다른 호스트의 첨부");
  u.searchParams.set("redirect", "false");
  try {
    const r = await requestBytes(u.href, { headers: headers(c), timeoutMs: 60000 });
    if (r.status < 200 || r.status > 299) throw new HttpError(r.status, "", `HTTP ${r.status}`);
    return r.bytes;
  } catch (e) { throw detailError(e); }
}

function writeError(status: number, body: string, what: string): JiraError {
  switch (status) {
    case 400: return new JiraError("message", `Jira 가 ${what} 요청을 받아 주지 않았어요 (${errorMessage(body)})`);
    case 401: return new JiraError("message", "토큰 만료 — 설정에서 토큰을 다시 입력하세요");
    case 403: return new JiraError("message", `이 이슈에 ${what} 권한이 없어요`);
    case 404: return new JiraError("message", "이슈를 찾지 못했어요 (없거나 볼 권한이 없어요)");
    case 413: return new JiraError("message", `너무 커서 Jira 가 받지 않았어요 (${what})`);
    default: return new JiraError("http", `HTTP ${status}`);
  }
}

const issueApi = (c: JiraCreds, key: string, tail: string) => {
  if (!isIssueKey(key)) throw new JiraError("message", `이슈 키가 올바르지 않아요 (${key})`);
  return `${c.baseURL}/rest/api/3/issue/${key}/${tail}`;
};

/** ADF 문서를 이슈 댓글로 남기고 댓글 id 를 돌려준다. */
export async function addComment(c: JiraCreds, key: string, document: unknown): Promise<string> {
  try {
    const r = await requestJSON<{ id?: string }>(issueApi(c, key, "comment"), { method: "POST", headers: headers(c), body: { body: document } });
    return r?.id ?? "";
  } catch (e) {
    if (e instanceof HttpError) throw writeError(e.status, e.body, "댓글");
    throw detailError(e);
  }
}

/** multipart/form-data 본문 (파일 하나). */
export function multipart(boundary: string, fileName: string, mime: string, data: Uint8Array): Uint8Array {
  const name = fileName.replace(/[\r\n"\\]/g, ""); // 헤더에 줄이 끼어들지 않게
  const enc = new TextEncoder();
  const head = enc.encode(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${name}"\r\nContent-Type: ${mime}\r\n\r\n`);
  const tail = enc.encode(`\r\n--${boundary}--\r\n`);
  const out = new Uint8Array(head.length + data.length + tail.length);
  out.set(head, 0); out.set(data, head.length); out.set(tail, head.length + data.length);
  return out;
}

/** 파일 하나를 이슈에 첨부하고 첨부 id 를 돌려준다 (응답을 못 읽으면 빈 값). */
export async function addAttachment(c: JiraCreds, key: string, fileName: string, mime: string, data: Uint8Array): Promise<string> {
  const boundary = `atm-${crypto.randomUUID()}`;
  try {
    const r = await requestBytes(issueApi(c, key, "attachments"), {
      method: "POST", body: multipart(boundary, fileName, mime, data), timeoutMs: 120000,
      // X-Atlassian-Token 이 없으면 Jira 가 첨부 요청을 거절한다 (XSRF 검사).
      headers: { ...headers(c), Accept: "application/json", "Content-Type": `multipart/form-data; boundary=${boundary}`, "X-Atlassian-Token": "no-check" },
    });
    const body = new TextDecoder().decode(r.bytes);
    if (r.status < 200 || r.status > 299) throw writeError(r.status, body, "첨부");
    try { return (JSON.parse(body) as { id?: string }[])[0]?.id ?? ""; } catch { return ""; }
  } catch (e) { throw e instanceof JiraError ? e : detailError(e); }
}

/** `.../file/<uuid>/binary?...` 에서 uuid. 모양이 다르면 null. */
export function mediaFileIdFromLocation(location: string | null): string | null {
  if (!location) return null;
  let parts: string[];
  try { parts = new URL(location).pathname.split("/").filter(Boolean); } catch { return null; }
  const i = parts.indexOf("file");
  const id = i >= 0 ? parts[i + 1] : undefined;
  return id && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id) ? id : null;
}

/**
 * 첨부의 Media 파일 id. 댓글(ADF) 안에 이미지로 넣을 때 쓴다. 알아내지 못하면 null.
 * 첨부 내려받기 주소가 `api.media.atlassian.com/file/<id>/binary` 로 넘겨 주는 Location 에서 읽고, 따라가지는 않는다.
 * (Windows 의 plugin-http 가 3xx 를 그대로 돌려주는지는 아직 확인하지 못했다. 못 읽으면 첨부 이름만 댓글에 적힌다.)
 */
export async function mediaFileId(c: JiraCreds, attachmentId: string): Promise<string | null> {
  if (!/^[0-9]+$/.test(attachmentId)) return null;
  try {
    const r = await requestBytes(`${c.baseURL}/rest/api/3/attachment/content/${attachmentId}`, { headers: headers(c), noRedirect: true, timeoutMs: 20000 });
    return r.status >= 300 && r.status <= 399 ? mediaFileIdFromLocation(r.headers.get("location")) : null;
  } catch { return null; }
}
