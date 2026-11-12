import { describe, expect, it } from "vitest";
import {
  commonPrefix, decodePage, displayVersion, effectiveJQL, DEFAULT_JQL, filterByVersion, groupedByStatus, groupedByVersion,
  normalizeBase, parseJiraDate, parseVersionFilter, releaseOrder, transitionError, versionCounts, versionFilterStorage, versionTag,
  type JiraIssue,
} from "./jira";

const issue = (id: string, v: string[], status = "진행 중", cat = "indeterminate", updated = 0): JiraIssue =>
  ({ id, summary: id, status, statusCategory: cat, updated, fixVersions: v });
const sample = [issue("A", ["15.9.2"]), issue("B", ["15.10.0"]), issue("C", ["15.9.2", "15.10.0"]), issue("D", [])];

describe("versions", () => {
  it("storage round trip", () => {
    for (const s of ["", "\u0001none", "15.3.0"]) expect(versionFilterStorage(parseVersionFilter(s))).toBe(s);
  });
  it("counts in release order (numeric aware)", () => {
    const c = versionCounts(sample);
    expect(c.versions).toEqual([{ name: "15.9.2", count: 2 }, { name: "15.10.0", count: 2 }]);
    expect(c.noneCount).toBe(1);
    expect(releaseOrder("15.5.a", "15.6.0")).toBeLessThan(0);
  });
  it("filter", () => {
    expect(filterByVersion(sample, { kind: "all" })).toHaveLength(4);
    expect(filterByVersion(sample, { kind: "none" }).map((i) => i.id)).toEqual(["D"]);
    expect(filterByVersion(sample, { kind: "named", name: "15.9.2" }).map((i) => i.id).sort()).toEqual(["A", "C"]);
    expect(filterByVersion(sample, { kind: "named", name: "9.9" })).toEqual([]);
  });
  it("grouped", () => {
    const g = groupedByVersion(sample);
    expect(g.map((x) => x.title)).toEqual(["15.9.2", "15.10.0", null]);
    expect(g[2].issues.map((i) => i.id)).toEqual(["D"]);
  });
  it("tag / prefix", () => {
    expect(versionTag(issue("a", []))).toBeNull();
    expect(versionTag(issue("a", ["15.3.0", "15.2.1"]))).toBe("15.2.1 +1");
    expect(commonPrefix(["NMRS_v15.6.0", "NMRS_v15.5.a"])).toBe("NMRS_");
    expect(commonPrefix(["NMRS_v1", "ATS_v1"])).toBe("");
    expect(commonPrefix(["NMRS_"])).toBe("");
    expect(commonPrefix([])).toBe("");
    expect(displayVersion("ATS_v1", "NMRS_")).toBe("ATS_v1");
    expect(versionTag(issue("a", ["NMRS_v15.6.0", "NMRS_v15.5.a"]), "NMRS_")).toBe("v15.5.a +1");
  });
});

describe("display order", () => {
  it("indeterminate, new, done; then status, then updated desc", () => {
    const l = [issue("n", [], "To Do", "new"), issue("d", [], "Done", "done"), issue("p1", [], "진행 중", "indeterminate", 1), issue("p2", [], "진행 중", "indeterminate", 2)];
    expect(groupedByStatus(l).map((g) => `${g.status}:${g.issues.map((i) => i.id)}`)).toEqual(["진행 중:p2,p1", "To Do:n", "Done:d"]);
  });
});

describe("decodePage", () => {
  it("maps fields, dates, transitions and truncation", () => {
    const p = decodePage({
      isLast: false,
      issues: [{
        key: "NMRS-1",
        fields: { summary: "s", status: { name: "진행 중", statusCategory: { key: "indeterminate" } }, priority: null, updated: "2026-11-12T08:30:00.000+0900", fixVersions: [{ name: "v1" }] },
        transitions: [{ id: "31", name: "완료", to: { name: "Done", statusCategory: { key: "done" } } }],
      }],
    });
    expect(p.truncated).toBe(true);
    expect(p.issues[0]).toMatchObject({ id: "NMRS-1", priority: undefined, fixVersions: ["v1"], updated: Date.UTC(2026, 10, 11, 23, 30) });
    expect(p.issues[0].transitions).toEqual([{ id: "31", name: "완료", toName: "Done", toCategory: "done" }]);
  });
  it("parseJiraDate falls back to 0", () => expect(parseJiraDate("nope")).toBe(0));
});

describe("misc", () => {
  it("effectiveJQL", () => {
    expect(effectiveJQL("  ")).toBe(DEFAULT_JQL);
    expect(effectiveJQL(" project = X ")).toBe("project = X");
  });
  it("normalizeBase only https", () => {
    expect(normalizeBase(" https://a.atlassian.net/ ")).toBe("https://a.atlassian.net");
    expect(normalizeBase("http://a.atlassian.net")).toBeNull();
    expect(normalizeBase("https://localhost")).toBeNull();
    expect(normalizeBase("")).toBeNull();
  });
  it("transition errors", () => {
    expect(transitionError(403).userMessage).toBe("권한 없음");
    expect(transitionError(500).userMessage).toBe("HTTP 500");
  });
});
