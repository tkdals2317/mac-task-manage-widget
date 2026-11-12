import { describe, expect, it } from "vitest";
import { badge, dayKey, nextMonday, parseDayKey, sortedByDue, validDue } from "./due";

const today = new Date(2026, 9, 2, 23, 50); // 2026-10-02 23:50 (로컬)
const b = (d: string | null) => badge(d, today);

describe("badge", () => {
  it("handles none/invalid", () => {
    expect(b(null).style).toBe("none");
    expect(b("2026-02-30").style).toBe("none");
    expect(b("abc").style).toBe("none");
  });
  it("overdue / today / week / month-day", () => {
    expect(b("2026-10-01")).toEqual({ text: "D+1", style: "overdue" });
    expect(b("2026-10-02")).toEqual({ text: "오늘", style: "today" });
    expect(b("2026-10-03").text).toBe("D-1");
    expect(b("2026-10-09")).toEqual({ text: "D-7", style: "normal" });
    expect(b("2026-10-10").text).toBe("10/10");
    expect(b("2026-11-05").text).toBe("11/5");
  });
});

describe("dayKey", () => {
  it("round-trips", () => {
    expect(dayKey(new Date(2026, 0, 5))).toBe("2026-01-05");
    expect(parseDayKey("2026-01-05")).toEqual({ y: 2026, m: 1, d: 5 });
    expect(validDue("2026-1-5")).toBe(false);
    expect(validDue("2026-02-29")).toBe(false);
  });
  it("nextMonday is strictly after", () => {
    expect(dayKey(nextMonday(new Date(2026, 9, 2)))).toBe("2026-10-05"); // 금 → 월
    expect(dayKey(nextMonday(new Date(2026, 9, 5)))).toBe("2026-10-12"); // 월 → 다음 월
    expect(dayKey(nextMonday(new Date(2026, 9, 4)))).toBe("2026-10-05"); // 일 → 월
  });
});

describe("sortedByDue", () => {
  it("due asc, none last, tie by createdAt", () => {
    const t = (id: string, dueDate: string | undefined, createdAt: string) => ({ id, dueDate, createdAt });
    const r = sortedByDue([t("a", undefined, "2026-01-01T00:00:00Z"), t("b", "2026-10-03", "2026-01-02T00:00:00Z"),
      t("c", "2026-10-03", "2026-01-01T00:00:00Z"), t("d", "2026-10-01", "2026-01-03T00:00:00Z")]);
    expect(r.map((x) => x.id)).toEqual(["d", "c", "b", "a"]);
  });
});
