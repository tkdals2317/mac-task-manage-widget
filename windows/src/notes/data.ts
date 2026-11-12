// notes.json 모양 (Mac Codable 과 같다). 날짜는 소수초 없는 ISO8601, UUID 는 대문자.
import type { NoteLock } from "../lib/noteCrypto";

export interface Memo {
  id: string;
  title: string;
  /** 잠긴 메모는 "" (평문을 디스크에 남기지 않는다). */
  body: string;
  /** 잠겼을 때 body 를 AES-GCM 으로 봉인한 base64. 안 잠겼으면 undefined (키 자체를 쓰지 않는다). */
  sealed?: string;
  pinned: boolean;
  createdAt: string;
  updatedAt: string;
}
export interface SavedLink { id: string; title: string; url: string; createdAt: string }
export interface NotesData { memos: Memo[]; links: SavedLink[]; lock?: NoteLock }

export const newId = () => crypto.randomUUID().toUpperCase();
export const nowISO = () => new Date().toISOString().replace(/\.\d+Z$/, "Z");
export const normalizedTitle = (raw: string) => raw.trim() || null;

const str = (v: unknown, d: string) => (typeof v === "string" ? v : d);

/** 빠진 키는 기본값 (Mac 의 decodeIfPresent). */
export function parseNotes(raw: unknown): NotesData {
  const o = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const memos = (Array.isArray(o.memos) ? o.memos : []).map((x): Memo => {
    const m = (x ?? {}) as Record<string, unknown>;
    const createdAt = str(m.createdAt, nowISO());
    return {
      id: str(m.id, newId()), title: str(m.title, ""), body: str(m.body, ""),
      sealed: typeof m.sealed === "string" ? m.sealed : undefined,
      pinned: m.pinned === true, createdAt, updatedAt: str(m.updatedAt, createdAt),
    };
  });
  const links = (Array.isArray(o.links) ? o.links : []).map((x): SavedLink => {
    const l = (x ?? {}) as Record<string, unknown>;
    const url = str(l.url, "");
    return { id: str(l.id, newId()), url, title: str(l.title, url), createdAt: str(l.createdAt, nowISO()) };
  });
  const k = o.lock as Record<string, unknown> | null | undefined;
  const lock = k && typeof k.salt === "string" && typeof k.iterations === "number" && typeof k.verifier === "string"
    ? { salt: k.salt, iterations: k.iterations, verifier: k.verifier } : undefined;
  return { memos, links, lock };
}

export const isLocked = (m: Memo) => m.sealed !== undefined;

/** 본문 첫 비어있지 않은 줄. */
export function firstLine(text: string): string | null {
  for (const line of text.split(/\r\n|[\r\n\u2028\u2029\u0085\u000b\u000c]/)) {
    const t = line.trim();
    if (t) return t;
  }
  return null;
}

/** 목록 둘째 줄 미리보기. 잠긴 메모는 null. */
export const preview = (m: Memo) => (isLocked(m) ? null : firstLine(m.body));

/** 고정된 메모 먼저, 그 안에서 최근 수정 순. */
export function orderMemos(list: Memo[]): Memo[] {
  return [...list].sort((a, b) => (a.pinned !== b.pinned ? (a.pinned ? -1 : 1) : Date.parse(b.updatedAt) - Date.parse(a.updatedAt)));
}

export const orderLinks = (list: SavedLink[]) => [...list].sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));

/** 확인 문구: 오늘 수정 / N일 전 수정 (달력 날짜 기준). */
export function agoText(d: Date, now = new Date()): string {
  const day = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  const days = Math.round((day(now) - day(d)) / 86_400_000);
  return days <= 0 ? "오늘 수정" : `${days}일 전 수정`;
}

export type LinkSiteIconName = "code" | "chart" | "palette" | "ticket" | "doc" | "hash" | "docrich" | "note" | "globe";

/** 자주 쓰는 사이트는 알아보기 쉬운 아이콘, 나머지는 지구본. */
export function siteIcon(host: string | undefined): LinkSiteIconName {
  const h = (host ?? "").toLowerCase();
  const has = (s: string) => h === s || h.endsWith("." + s);
  if (has("github.com") || has("bitbucket.org") || has("gitlab.com")) return "code";
  if (has("datadoghq.com")) return "chart";
  if (has("figma.com")) return "palette";
  if (h.includes("jira")) return "ticket";
  if (has("atlassian.net")) return "doc";
  if (has("slack.com")) return "hash";
  if (has("google.com")) return "docrich";
  if (has("notion.so") || has("notion.site")) return "note";
  return "globe";
}
