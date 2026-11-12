import { describe, expect, it } from "vitest";
import { defaultTagConfig, normalized, orderedTags, parseTagFile, rank, sortTodos, toggled, type TagConfig } from "./tags";

const cfg = (): TagConfig => ({
  groups: [
    ...defaultTagConfig().groups,
    { id: "kind", name: "종류", selection: "multiple", tags: [{ id: "bug", name: "버그", colorHex: "#E24B4A" }, { id: "doc", name: "문서", colorHex: "#22C55E" }] },
  ],
  sortGroupId: "importance",
});
const todo = (id: string, tagIds: string[], dueDate?: string, createdAt = "2026-01-01T00:00:00Z") => ({ id, tagIds, dueDate, createdAt });

describe("toggled", () => {
  it("single group replaces sibling", () => {
    expect(toggled(cfg(), "high", ["urgent", "bug"])).toEqual(["bug", "high"]);
  });
  it("multiple group adds, toggling off removes, unknown ignored", () => {
    expect(toggled(cfg(), "doc", ["bug"])).toEqual(["bug", "doc"]);
    expect(toggled(cfg(), "bug", ["bug", "doc"])).toEqual(["doc"]);
    expect(toggled(cfg(), "zzz", ["bug"])).toEqual(["bug"]);
  });
});

describe("normalized / orderedTags", () => {
  it("drops unknown, keeps first of single, display order", () => {
    expect(normalized(cfg(), ["doc", "low", "urgent", "x", "bug"])).toEqual(["urgent", "bug", "doc"]);
    expect(orderedTags(cfg(), ["doc", "urgent"]).map((t) => t.id)).toEqual(["urgent", "doc"]);
  });
});

describe("sortTodos", () => {
  it("by tag rank, then due, then createdAt", () => {
    const r = sortTodos([todo("n", []), todo("low", ["low"]), todo("u2", ["urgent"], "2026-10-05"), todo("u1", ["urgent"], "2026-10-01"), todo("u0", ["urgent"])], cfg(), true);
    expect(r.map((x) => x.id)).toEqual(["u1", "u2", "u0", "low", "n"]);
    expect(rank(todo("n", []), cfg())).toBe(Infinity);
  });
  it("without tag sort uses due order", () => {
    const r = sortTodos([todo("a", ["urgent"]), todo("b", [], "2026-10-01")], cfg(), false);
    expect(r.map((x) => x.id)).toEqual(["b", "a"]);
  });
  it("sortGroupId pointing at a missing group falls back to first group; undefined = no ranking", () => {
    expect(rank(todo("a", ["high"]), { ...cfg(), sortGroupId: "gone" })).toBe(1);
    expect(rank(todo("a", ["high"]), { ...cfg(), sortGroupId: undefined })).toBe(Infinity);
  });
});

describe("parseTagFile", () => {
  it("reads v2 and rejects other versions", () => {
    const f = { version: 2, sortGroupId: "g", groups: [{ id: "g", name: "G", selection: "single", tags: [{ id: "t", name: "T", colorHex: "#112233" }] }] };
    expect(parseTagFile(f)?.groups[0].tags[0].colorHex).toBe("#112233");
    expect(parseTagFile({ ...f, version: 1 })).toBeNull();
  });
  it("reads v1 color preset names inside tags", () => {
    const f = { version: 2, groups: [{ id: "g", name: "G", selection: "multiple", tags: [{ id: "t", name: "T", color: "red" }] }] };
    expect(parseTagFile(f)?.groups[0].tags[0].colorHex).toBe("#E24B4A");
  });
});
