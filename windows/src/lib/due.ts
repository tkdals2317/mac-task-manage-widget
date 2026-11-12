// Mac DueBadge/DayKey 포팅. dueDate 는 "yyyy-MM-dd" 로컬 날짜 문자열.
export type DueStyle = "none" | "overdue" | "today" | "normal";

const pad = (n: number) => String(n).padStart(2, "0");

export function dayKey(d: Date): string {
  return `${String(d.getFullYear()).padStart(4, "0")}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** "yyyy-MM-dd" → 실제 있는 날짜면 {y,m,d}, 아니면 null. */
export function parseDayKey(key: string): { y: number; m: number; d: number } | null {
  const parts = key.split("-");
  if (parts.length !== 3 || !parts.every((p) => /^\d+$/.test(p))) return null;
  const [y, m, d] = parts.map(Number);
  const back = new Date(y, m - 1, d);
  if (back.getFullYear() !== y || back.getMonth() !== m - 1 || back.getDate() !== d) return null;
  return { y, m, d };
}

/** "yyyy-MM-dd" 형식이고 실제로 있는 날짜인지 (inbox 검증용). */
export function validDue(s: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(s) && parseDayKey(s) !== null;
}

/** 잘못된 dueDate 문자열은 null 처럼 취급. */
export function badge(due: string | null | undefined, today: Date): { text: string; style: DueStyle } {
  const p = due ? parseDayKey(due) : null;
  if (!p) return { text: "", style: "none" };
  // UTC 로 맞춰 세어 서머타임에 흔들리지 않게
  const days = Math.round((Date.UTC(p.y, p.m - 1, p.d) - Date.UTC(today.getFullYear(), today.getMonth(), today.getDate())) / 86400000);
  if (days < 0) return { text: `D+${-days}`, style: "overdue" };
  if (days === 0) return { text: "오늘", style: "today" };
  if (days <= 7) return { text: `D-${days}`, style: "normal" };
  return { text: `${p.m}/${p.d}`, style: "normal" };
}

export interface Dated { dueDate?: string; createdAt: string }

const ts = (s: string) => Date.parse(s);

/** dueDate 오름차순, 없는 건 뒤, 동률은 createdAt 오름차순. */
export function compareDue(a: Dated, b: Dated): number {
  if (!a.dueDate && !b.dueDate) return ts(a.createdAt) - ts(b.createdAt);
  if (!a.dueDate) return 1;
  if (!b.dueDate) return -1;
  return a.dueDate === b.dueDate ? ts(a.createdAt) - ts(b.createdAt) : a.dueDate < b.dueDate ? -1 : 1;
}

export function sortedByDue<T extends Dated>(items: T[]): T[] {
  return [...items].sort(compareDue);
}

/** 오늘 이후 처음 오는 월요일 (오늘이 월요일이면 다음 주). */
export function nextMonday(from: Date): Date {
  const d = new Date(from.getFullYear(), from.getMonth(), from.getDate());
  d.setDate(d.getDate() + (((8 - d.getDay()) % 7) || 7));
  return d;
}
