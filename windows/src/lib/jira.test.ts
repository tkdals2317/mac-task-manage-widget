import { describe, expect, it } from "vitest";
import {
  commonPrefix, decodeIssueDetail, decodeRemoteLinks, mediaFileIdFromLocation, multipart, decodePage, displayVersion, effectiveJQL, DEFAULT_JQL, REPORTER_JQL, filterByVersion, groupedByStatus, groupedByVersion,
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
  it("REPORTER_JQL", () => {
    expect(REPORTER_JQL).toBe("reporter = currentUser() AND statusCategory != Done ORDER BY updated DESC");
    expect(REPORTER_JQL).not.toBe(DEFAULT_JQL);
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

describe("E2E 이슈 상세·첨부", () => {
  it("v2 응답을 이슈 상세로", () => {
    const d = decodeIssueDetail({
      key: "ABC-1",
      fields: {
        summary: "제목", description: "설명", status: { name: "진행" }, issuetype: { name: "버그" }, priority: { name: "High" }, assignee: { displayName: "나" },
        labels: ["a"], components: [{ name: "c" }], fixVersions: [{ name: "15.6.b" }], parent: { key: "ABC-0", fields: { summary: "에픽" } },
        subtasks: [{ key: "ABC-2", fields: { summary: "하위", status: { name: "Open" } } }],
        issuelinks: [{ type: { inward: "is blocked by", outward: "blocks" }, outwardIssue: { key: "ABC-3" } }, { type: {}, inwardIssue: { key: "ABC-4" } }],
        comment: { comments: [{ author: { displayName: "u" }, body: "b", created: "d" }] },
        attachment: [{ id: 10, filename: "a.png", mimeType: "image/png", size: 7, content: "https://x/a" }, { filename: "no-id" }],
      },
    });
    expect(d).toMatchObject({ key: "ABC-1", summary: "제목", type: "버그", assignee: "나", labels: ["a"], components: ["c"], fixVersions: ["15.6.b"], parent: { relation: "상위", key: "ABC-0" } });
    expect(d.related.map((r) => `${r.relation}:${r.key}`)).toEqual(["하위 작업:ABC-2", "blocks:ABC-3", "연결:ABC-4"]);
    expect(d.comments).toEqual([{ author: "u", created: "d", body: "b" }]);
    expect(d.attachments).toEqual([{ id: "10", filename: "a.png", mimeType: "image/png", size: 7, content: "https://x/a" }]);
    expect(decodeIssueDetail({}).key).toBe("");
  });
  it("원격 링크는 주소가 있는 것만", () => {
    expect(decodeRemoteLinks([{ object: { url: "https://git/pr/1", title: "PR" } }, { object: { title: "no url" } }, null])).toEqual([{ title: "PR", url: "https://git/pr/1" }]);
    expect(decodeRemoteLinks("x")).toEqual([]);
  });
  it("Media 파일 id 는 /file/<uuid>/binary 모양일 때만", () => {
    const id = "123e4567-e89b-12d3-a456-426614174000";
    expect(mediaFileIdFromLocation(`https://api.media.atlassian.com/file/${id}/binary?token=x`)).toBe(id);
    expect(mediaFileIdFromLocation("https://api.media.atlassian.com/file/not-a-uuid/binary")).toBeNull();
    expect(mediaFileIdFromLocation("https://x/other")).toBeNull();
    expect(mediaFileIdFromLocation(null)).toBeNull();
  });
  it("multipart 본문: 파일 이름의 줄바꿈·따옴표를 빼고 바이트를 그대로 싣는다", () => {
    const body = multipart("B", 'a"\r\nb.png', "image/png", new Uint8Array([1, 2, 3]));
    const text = new TextDecoder("latin1").decode(body);
    expect(text).toContain('Content-Disposition: form-data; name="file"; filename="ab.png"\r\nContent-Type: image/png\r\n\r\n');
    expect(text.endsWith("\x01\x02\x03\r\n--B--\r\n")).toBe(true);
  });
});
