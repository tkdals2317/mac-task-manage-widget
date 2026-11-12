import { describe, expect, it } from "vitest";
import { decodeTodo, decodeTodos, isoNow, memoPreview, newId, normalizedTitle, subtaskProgress, todoFromInbox, toggleDone } from "../tasks/model";
import { defaultTagConfig } from "./tags";

describe("decodeTodo", () => {
  it("applies Mac defaults for missing optionals", () => {
    const t = decodeTodo({ id: "A", title: "x", done: false, createdAt: "2026-11-12T08:30:00Z" })!;
    expect(t.tagIds).toEqual([]);
    expect(t.memo).toBe("");
    expect(t.subtasks).toEqual([]);
    expect(t.dueDate).toBeUndefined();
  });
  it("requires id/title/done/createdAt; whole array fails if one is bad", () => {
    expect(decodeTodo({ id: "A", title: "x", done: false })).toBeNull();
    expect(decodeTodos([{ id: "A", title: "x", done: false, createdAt: "z" }, { title: "bad" }])).toBeNull();
    expect(decodeTodos({})).toBeNull();
  });
});

describe("helpers", () => {
  it("uuid is uppercase, iso has no millis", () => {
    expect(newId()).toMatch(/^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/);
    expect(isoNow(new Date("2026-11-12T08:30:00.123Z"))).toBe("2026-11-12T08:30:00Z");
  });
  it("toggleDone completes subtasks, undo keeps them", () => {
    const t = decodeTodo({ id: "A", title: "x", done: false, createdAt: "z", subtasks: [{ id: "S", title: "s", done: false }] })!;
    toggleDone(t, new Date("2026-11-12T08:30:00Z"));
    expect(t.done).toBe(true);
    expect(t.completedAt).toBe("2026-11-12T08:30:00Z");
    expect(subtaskProgress(t)).toEqual({ done: 1, total: 1 });
    toggleDone(t);
    expect(t.done).toBe(false);
    expect(t.completedAt).toBeUndefined();
    expect(t.subtasks[0].done).toBe(true);
  });
  it("memoPreview / normalizedTitle", () => {
    expect(memoPreview({ memo: "\n  \n 둘째 \n셋째" } as never)).toBe("둘째");
    expect(memoPreview({ memo: "" } as never)).toBeNull();
    expect(normalizedTitle("  \n")).toBeNull();
    expect(normalizedTitle(" a ")).toBe("a");
  });
});

describe("todoFromInbox", () => {
  const id = "0a1b2c3d-0000-4000-8000-000000000001";
  const c = defaultTagConfig();
  const body = (o: object) => JSON.stringify({ title: " 할 일 ", tags: ["긴급", "높음", "없는태그"], createdAt: "2026-11-12T08:30:00Z", subtasks: ["a", " "], memo: " m ", due: "2026-11-20", ...o });
  it("converts, resolving tags and using file name as id", () => {
    const t = todoFromInbox(`${id}.json`, body({}), c)!;
    expect(t.id).toBe(id.toUpperCase());
    expect(t.title).toBe("할 일");
    expect(t.tagIds).toEqual(["urgent"]); // 하나만 그룹은 앞의 것
    expect(t.memo).toBe("m");
    expect(t.subtasks.map((s) => s.title)).toEqual(["a"]);
    expect(t.dueDate).toBe("2026-11-20");
  });
  it("rejects bad json / empty title / bad due / missing fields", () => {
    expect(todoFromInbox(`${id}.json`, "{", c)).toBeNull();
    expect(todoFromInbox(`${id}.json`, body({ title: "  " }), c)).toBeNull();
    expect(todoFromInbox(`${id}.json`, body({ due: "2026-13-01" }), c)).toBeNull();
    expect(todoFromInbox(`${id}.json`, JSON.stringify({ title: "x" }), c)).toBeNull();
  });
});
