// Mac Tags.swift 포팅. 태그 정의는 데이터 폴더의 tags.json (version 2) 에 Mac 과 같은 모양으로 저장.
import { readJSON, writeJSON } from "./native";
import { compareDue, sortedByDue, type Dated } from "./due";

export interface Tag { id: string; name: string; colorHex: string }
export type TagSelection = "single" | "multiple";
export interface TagGroup { id: string; name: string; selection: TagSelection; tags: Tag[] }
export interface TagConfig { groups: TagGroup[]; sortGroupId?: string }

export const TAG_COLORS = {
  red: "#E24B4A", orange: "#EF9F27", yellow: "#E8C547", green: "#22C55E",
  teal: "#4FB3A3", blue: "#7896C8", purple: "#C77DFF", gray: "#9A9A9A",
} as const;
const HEX = /^#?([0-9a-f]{6})$/i;
export const isGray = (hex: string) => hex.toUpperCase() === TAG_COLORS.gray;
/** 잘못된 hex 는 회색. */
export const safeHex = (hex: string) => (HEX.test(hex.trim()) ? "#" + HEX.exec(hex.trim())![1] : TAG_COLORS.gray);

export const IMPORTANCE_GROUP_ID = "importance";

export function defaultTagConfig(): TagConfig {
  return {
    groups: [{
      id: IMPORTANCE_GROUP_ID, name: "중요도", selection: "single",
      tags: [
        { id: "urgent", name: "긴급", colorHex: TAG_COLORS.red },
        { id: "high", name: "높음", colorHex: TAG_COLORS.orange },
        { id: "normal", name: "보통", colorHex: TAG_COLORS.gray },
        { id: "low", name: "낮음", colorHex: TAG_COLORS.blue },
      ],
    }],
    sortGroupId: IMPORTANCE_GROUP_ID,
  };
}

export const allTags = (c: TagConfig): Tag[] => c.groups.flatMap((g) => g.tags);
export const groupOf = (c: TagConfig, tagId: string) => c.groups.find((g) => g.tags.some((t) => t.id === tagId));

/** 정렬 기준 그룹. id 가 없는 그룹을 가리키면 첫 그룹, 없으면 정렬 기준 없음. */
export function sortGroup(c: TagConfig): TagGroup | undefined {
  if (!c.sortGroupId) return undefined;
  return c.groups.find((g) => g.id === c.sortGroupId) ?? c.groups[0];
}

/** 켜기: 하나만 그룹이면 같은 그룹의 다른 태그를 뺀다. 끄기: 그냥 뺀다. 모르는 태그는 무시. */
export function toggled(c: TagConfig, tagId: string, ids: string[]): string[] {
  if (ids.includes(tagId)) return ids.filter((x) => x !== tagId);
  const g = groupOf(c, tagId);
  if (!g) return ids;
  const out = g.selection === "single" ? ids.filter((x) => !g.tags.some((t) => t.id === x)) : [...ids];
  out.push(tagId);
  return out;
}

/** 모르는 id 제거, 하나만 그룹은 태그 순서상 첫 번째만, 표시 순서로 반환. */
export function normalized(c: TagConfig, ids: string[]): string[] {
  return c.groups.flatMap((g) => {
    const mine = g.tags.map((t) => t.id).filter((id) => ids.includes(id));
    return g.selection === "single" ? mine.slice(0, 1) : mine;
  });
}

/** (그룹 순서, 태그 순서)로 정렬한 태그들. 모르는 id 제외. */
export const orderedTags = (c: TagConfig, ids: string[]): Tag[] => allTags(c).filter((t) => ids.includes(t.id));

export interface Tagged extends Dated { tagIds: string[] }

/** 정렬 기준 그룹 안에서 태그의 index. 없으면 Infinity. */
export function rank(t: Tagged, c: TagConfig): number {
  const g = sortGroup(c);
  if (!g) return Infinity;
  const idx = t.tagIds.map((id) => g.tags.findIndex((x) => x.id === id)).filter((i) => i >= 0);
  return idx.length ? Math.min(...idx) : Infinity;
}

/** byTag: rank → 마감 오름차순(없으면 뒤) → createdAt. 아니면 마감순. */
export function sortTodos<T extends Tagged>(todos: T[], c: TagConfig, byTag: boolean): T[] {
  if (!byTag) return sortedByDue(todos);
  return [...todos].sort((a, b) => {
    const ra = rank(a, c), rb = rank(b, c);
    return ra !== rb ? (ra < rb ? -1 : 1) : compareDue(a, b);
  });
}

// ---- 저장 (tags.json) ----
const FILE = "tags.json";

/** 파일 없으면 기본값. v1(평평한 [Tag], 또는 color 프리셋 이름)은 '중요도'(하나만) 그룹으로 옮기고 v2 로 다시 쓴다. 깨졌으면 옆으로 치우고 기본값. */
export async function loadTagConfig(): Promise<TagConfig> {
  const raw = await readJSON<unknown>(FILE, null);
  if (raw == null) return defaultTagConfig();
  if (Array.isArray(raw)) {
    const tags = raw.map(decodeTag).filter((t): t is Tag => t !== null);
    const cfg: TagConfig = {
      groups: [{ id: IMPORTANCE_GROUP_ID, name: "중요도", selection: "single", tags }],
      sortGroupId: IMPORTANCE_GROUP_ID,
    };
    await saveTagConfig(cfg).catch(() => {});
    return cfg;
  }
  return parseTagFile(raw) ?? defaultTagConfig();
}

export function parseTagFile(raw: unknown): TagConfig | null {
  const f = raw as { version?: number; groups?: unknown; sortGroupId?: unknown } | null;
  if (!f || f.version !== 2 || !Array.isArray(f.groups)) return null;
  const groups: TagGroup[] = [];
  for (const g of f.groups as Record<string, unknown>[]) {
    if (typeof g?.id !== "string" || typeof g.name !== "string" || !Array.isArray(g.tags)) return null;
    groups.push({
      id: g.id, name: g.name, selection: g.selection === "single" ? "single" : "multiple",
      tags: g.tags.map(decodeTag).filter((t): t is Tag => t !== null),
    });
  }
  return { groups, sortGroupId: typeof f.sortGroupId === "string" ? f.sortGroupId : undefined };
}

const PRESET_NAMES = Object.keys(TAG_COLORS) as (keyof typeof TAG_COLORS)[];

function decodeTag(v: unknown): Tag | null {
  const t = v as Record<string, unknown> | null;
  if (!t || typeof t.id !== "string" || typeof t.name !== "string") return null;
  const preset = PRESET_NAMES.find((n) => n === t.color);
  const colorHex = typeof t.colorHex === "string" ? t.colorHex : preset ? TAG_COLORS[preset] : null;
  return colorHex ? { id: t.id, name: t.name, colorHex } : null;
}

export function saveTagConfig(c: TagConfig): Promise<void> {
  return writeJSON(FILE, { version: 2, groups: c.groups, sortGroupId: c.sortGroupId });
}
