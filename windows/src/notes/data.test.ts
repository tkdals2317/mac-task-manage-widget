import { describe, expect, it } from "vitest";
import { agoText, firstLine, isLocked, orderMemos, parseNotes, preview, siteIcon, type Memo } from "./data";

const memo = (o: Partial<Memo>): Memo => ({ id: "A", title: "t", body: "", pinned: false, createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:00Z", ...o });

describe("notes data", () => {
  it("빈 객체와 빠진 키", () => {
    expect(parseNotes({})).toEqual({ memos: [], links: [], lock: undefined });
    const m = parseNotes({ memos: [{ title: "x" }] }).memos[0];
    expect([m.title, m.body, m.pinned, isLocked(m)]).toEqual(["x", "", false, false]);
  });
  it("Mac JSON 을 읽는다", () => {
    const d = parseNotes({ memos: [{ id: "ABC", title: "a", body: "", sealed: "AAAA", pinned: true, createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-02T00:00:00Z" }], links: [{ id: "L", title: "t", url: "https://a.io", createdAt: "2026-01-01T00:00:00Z" }], lock: { salt: "s", iterations: 1000, verifier: "v" } });
    expect(isLocked(d.memos[0])).toBe(true);
    expect(d.lock?.iterations).toBe(1000);
  });
  it("미리보기", () => {
    expect(firstLine("\n  \n  첫 줄 \n둘째")).toBe("첫 줄");
    expect(firstLine("")).toBeNull();
    expect(preview(memo({ sealed: "x" }))).toBeNull();
  });
  it("고정 먼저, 최근 수정 순", () => {
    const l = orderMemos([
      memo({ title: "old", updatedAt: "2026-01-01T00:00:00Z" }),
      memo({ title: "new", updatedAt: "2026-01-01T00:01:40Z" }),
      memo({ title: "pinned", pinned: true, updatedAt: "2025-12-31T00:00:00Z" }),
    ]);
    expect(l.map((m) => m.title)).toEqual(["pinned", "new", "old"]);
  });
  it("수정 문구·아이콘", () => {
    const now = new Date(2026, 5, 10, 12);
    expect(agoText(new Date(2026, 5, 10, 1), now)).toBe("오늘 수정");
    expect(agoText(new Date(2026, 5, 7, 23), now)).toBe("3일 전 수정");
    expect(siteIcon("gist.github.com")).toBe("code");
    expect(siteIcon("x.org")).toBe("globe");
  });
});
