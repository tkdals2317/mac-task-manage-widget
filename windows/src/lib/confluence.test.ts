import { describe, expect, it, vi } from "vitest";

vi.mock("./http", () => ({ requestJSON: vi.fn(), basicAuth: () => "", HttpError: class extends Error {} }));
import { decode, validBaseURL } from "./confluence";

const base = "https://example.atlassian.net";
const fixture = {
  results: [
    { id: "1001", type: "page", title: "배포 가이드", space: { key: "DEV", name: "개발" }, version: { when: "2026-10-01T09:30:00.000+09:00" }, _links: { webui: "/spaces/DEV/pages/1001/Deploy+Guide" } },
    { id: "1002", type: "page", title: "온보딩", space: { key: "HR" }, _links: { webui: "/spaces/HR/pages/1002/Onboarding" } },
  ],
  _links: { base: "https://example.atlassian.net/wiki", context: "/wiki" },
};

describe("confluence", () => {
  it("fixture 해석", () => {
    const p = decode(fixture, base);
    expect(p.map((x) => x.title)).toEqual(["배포 가이드", "온보딩"]);
    expect(p.map((x) => x.spaceKey)).toEqual(["DEV", "HR"]);
    expect(p[0].url).toBe("https://example.atlassian.net/wiki/spaces/DEV/pages/1001/Deploy+Guide");
    expect(p[0].updated).not.toBeNull();
    expect(p[1].updated).toBeNull();
  });
  it("base 없으면 /wiki", () => {
    const p = decode({ results: [{ id: "1", title: "t", _links: { webui: "/x" } }] }, base);
    expect(p[0].url).toBe("https://example.atlassian.net/wiki/x");
    expect(p[0].spaceKey).toBe("");
  });
  it("깨진 응답", () => {
    expect(() => decode("nope", base)).toThrow();
    expect(() => decode({}, base)).toThrow();
  });
  it("validBaseURL", () => {
    expect(validBaseURL(" https://a.atlassian.net ")).toBe("https://a.atlassian.net");
    expect(validBaseURL("http://a.atlassian.net")).toBeNull();
    expect(validBaseURL("https://localhost")).toBeNull();
  });
});
