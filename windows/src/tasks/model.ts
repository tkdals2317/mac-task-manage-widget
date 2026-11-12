// Mac Models.swift(Todo/Subtask) + TodoInbox 포팅. todos.json 은 Mac 과 같은 모양:
// createdAt/completedAt 은 소수점 없는 ISO8601(UTC), id 는 대문자 UUID, dueDate 는 "yyyy-MM-dd".
import { validDue } from "../lib/due";
import { normalized, allTags, type TagConfig } from "../lib/tags";

export interface Subtask { id: string; title: string; done: boolean; dueDate?: string }
export interface Todo {
  id: string;
  title: string;
  done: boolean;
  createdAt: string;
  completedAt?: string;
  dueDate?: string;
  tagIds: string[];
  memo: string;
  subtasks: Subtask[];
}

export const newId = (): string => crypto.randomUUID().toUpperCase();
/** Swift .iso8601 와 같은 형태 (밀리초 없음). */
export const isoNow = (d = new Date()): string => d.toISOString().replace(/\.\d+Z$/, "Z");

export const newTodo = (title: string, extra: Partial<Todo> = {}): Todo =>
  ({ id: newId(), title, done: false, createdAt: isoNow(), tagIds: [], memo: "", subtasks: [], ...extra });

/** 앞뒤 공백 제거. 비면 null. */
export const normalizedTitle = (raw: string): string | null => raw.trim() || null;

const str = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);

function decodeSubtask(v: unknown): Subtask | null {
  const o = v as Record<string, unknown> | null;
  if (!o || typeof o.id !== "string" || typeof o.title !== "string" || typeof o.done !== "boolean") return null;
  return { id: o.id, title: o.title, done: o.done, dueDate: str(o.dueDate) };
}

/** 필수 필드(id,title,done,createdAt)가 없으면 null. 옵션은 Mac 기본값(tagIds [], memo "", subtasks []). */
export function decodeTodo(v: unknown): Todo | null {
  const o = v as Record<string, unknown> | null;
  if (!o || typeof o.id !== "string" || typeof o.title !== "string" || typeof o.done !== "boolean" || typeof o.createdAt !== "string") return null;
  return {
    id: o.id, title: o.title, done: o.done, createdAt: o.createdAt,
    completedAt: str(o.completedAt), dueDate: str(o.dueDate),
    tagIds: Array.isArray(o.tagIds) ? o.tagIds.filter((x): x is string => typeof x === "string") : [],
    memo: str(o.memo) ?? "",
    subtasks: Array.isArray(o.subtasks) ? o.subtasks.map(decodeSubtask).filter((s): s is Subtask => s !== null) : [],
  };
}

/** 하나라도 못 읽으면 null (Mac 은 배열 전체 디코딩 실패 → 파일을 옆으로 치움). */
export function decodeTodos(raw: unknown): Todo[] | null {
  if (!Array.isArray(raw)) return null;
  const out = raw.map(decodeTodo);
  return out.every((t) => t !== null) ? (out as Todo[]) : null;
}

/** 완료 토글. 완료로 바꾸면 하위 할 일도 모두 완료, 되돌릴 땐 하위는 그대로. */
export function toggleDone(t: Todo, now = new Date()): void {
  t.done = !t.done;
  t.completedAt = t.done ? isoNow(now) : undefined;
  if (t.done) for (const s of t.subtasks) s.done = true;
}

export const subtaskProgress = (t: Todo) => ({ done: t.subtasks.filter((s) => s.done).length, total: t.subtasks.length });

/** 메모 첫 비어 있지 않은 줄. 없으면 null. */
export const memoPreview = (t: Todo): string | null =>
  t.memo.split(/\r?\n/).map((l) => l.trim()).find((l) => l) ?? null;

// ---- inbox ----
/** 태그 이름(대소문자 무시, 앞뒤 공백 제거) → id. 하나만 그룹은 앞의 것만 남긴다. */
export function resolveTagNames(names: string[], c: TagConfig): { ids: string[]; unknown: string[] } {
  const ids: string[] = [], unknown: string[] = [];
  const tags = allTags(c);
  for (const raw of names) {
    const n = raw.trim();
    if (!n) continue;
    const t = tags.find((x) => x.name.toLowerCase() === n.toLowerCase());
    if (t) { if (!ids.includes(t.id)) ids.push(t.id); } else unknown.push(n);
  }
  return { ids: normalized(c, ids), unknown };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** inbox/<UUID>.json 한 개 → 할 일. 못 읽으면 null (호출 쪽이 bad/ 로 옮긴다). 할 일 id = 파일 이름(UUID). */
export function todoFromInbox(fileName: string, text: string, c: TagConfig): Todo | null {
  let item: Record<string, unknown>;
  try { item = JSON.parse(text); } catch { return null; }
  if (!item || typeof item.title !== "string" || !Array.isArray(item.tags) || typeof item.createdAt !== "string") return null;
  const title = normalizedTitle(item.title);
  const due = item.due == null ? undefined : str(item.due);
  if (!title || (item.due != null && (due === undefined || !validDue(due)))) return null;
  const base = fileName.replace(/\.json$/i, "");
  const subs = Array.isArray(item.subtasks) ? item.subtasks.filter((x): x is string => typeof x === "string") : [];
  return {
    id: UUID_RE.test(base) ? base.toUpperCase() : newId(),
    title, done: false, createdAt: item.createdAt, dueDate: due,
    tagIds: resolveTagNames(item.tags.filter((x): x is string => typeof x === "string"), c).ids,
    memo: str(item.memo)?.trim() ?? "",
    subtasks: subs.map(normalizedTitle).filter((s): s is string => s !== null).map((s) => ({ id: newId(), title: s, done: false })),
  };
}
