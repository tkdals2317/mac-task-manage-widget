import { describe, expect, it } from "vitest";
import { DEFAULT_JQL, REPORTER_JQL } from "./jira";
import { BOTH_JQL, TAB_ORDER, isValid, jqlFor, preset, previewLine, scopeForJQL, steps, tabsString } from "./rolePreset";

describe("presets", () => {
  it("developer", () => {
    const p = preset("developer");
    expect(tabsString(p.tabs)).toBe("tasks,summary,notes,pr,teleport");
    expect([p.jira, p.e2eScope]).toEqual(["assignee", "assignee"]);
  });
  it("planner", () => {
    const p = preset("planner");
    expect(tabsString(p.tabs)).toBe("tasks,notes,e2e");
    expect([p.jira, p.e2eScope]).toEqual(["reporter", "reporter"]);
  });
  it("custom has no tabs", () => {
    const p = preset("custom");
    expect(isValid(p.tabs)).toBe(false);
    expect(p.jira).toBe("assignee");
  });
});

describe("jql mapping", () => {
  it("scope -> jql", () => {
    expect(jqlFor("assignee")).toBe("");
    expect(jqlFor("reporter")).toBe(REPORTER_JQL);
    expect(jqlFor("both")).toBe(BOTH_JQL);
    expect(jqlFor("keep")).toBeNull();
  });
  it("jql -> scope round trip, custom -> keep", () => {
    for (const s of ["assignee", "reporter", "both"] as const) expect(scopeForJQL(jqlFor(s)!)).toBe(s);
    expect(scopeForJQL("  ")).toBe("assignee");
    expect(scopeForJQL(DEFAULT_JQL)).toBe("assignee");
    expect(scopeForJQL("project = X")).toBe("keep");
  });
});

describe("steps", () => {
  it("skips by tab", () => {
    expect(steps(new Set(["tasks"]))).toEqual(["role", "jira", "finish"]);
    expect(steps(new Set(["summary"]))).toEqual(["role", "summary", "finish"]);
    expect(steps(new Set(["teleport"]))).toEqual(["role", "teleport", "finish"]);
    expect(steps(new Set(["e2e"]))).toEqual(["role", "jira", "e2e", "finish"]);
    expect(steps(new Set(TAB_ORDER))).toEqual(["role", "jira", "notes", "summary", "pr", "e2e", "teleport", "finish"]);
  });
  it("preview", () => {
    expect(previewLine(steps(new Set(["tasks"])))).toBe("다음: Atlassian → 마무리");
    expect(previewLine(steps(new Set(TAB_ORDER)))).toBe("다음: Atlassian → 노트 → … → 마무리");
  });
});
