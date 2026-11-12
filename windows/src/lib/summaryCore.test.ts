import { describe, expect, it } from "vitest";
import {
  buildPrompt, catchUpDays, claudeHint, dayTitle, filterActivity, isEmptyInput, jiraKeysIn, nextFire, parseActivity, parseWorklog,
  projectOf, weekDays, weekLabel, weekTitle, PROMPT_CAP, type ActivityRecord, type SummaryInput,
} from "./summaryCore";
import { renderMarkdown } from "./markdown";

const rec = (h: number, event: "prompt" | "stop", cwd: string, text: string): ActivityRecord =>
  ({ ts: new Date(2026, 10, 13, h, 0), event, session: "s", cwd, text });

describe("summaryCore", () => {
  it("projectOf 는 Windows·POSIX 경로 모두", () => {
    expect(projectOf("C:\\work\\shop-api")).toBe("shop-api");
    expect(projectOf("/Users/a/shop-web/")).toBe("shop-web");
  });

  it("activity.jsonl 은 그날 것만, 깨진 줄은 건너뛴다", () => {
    const day = new Date(2026, 10, 13);
    const lines = [
      JSON.stringify({ ts: "2026-11-13T09:00:00+09:00", event: "prompt", session: "a", cwd: "C:\\p", text: "hi" }),
      "{broken",
      JSON.stringify({ ts: "2026-11-12T09:00:00+09:00", event: "stop", session: "a", cwd: "C:\\p", text: "old" }),
      JSON.stringify({ ts: "2026-11-13T08:00:00+09:00", event: "stop", session: "a", cwd: "C:\\p", text: "first" }),
    ].join("\n");
    const r = parseActivity(lines, day);
    expect(r.map((x) => x.text)).toEqual(["first", "hi"]);
  });

  it("업무 일지 헤더 `## HH:mm · 프로젝트` 로 나눈다", () => {
    const md = "# 2026-11-13 업무 일지\n\n## 10:30 · shop-api\n- 쿠폰 수정\n## 메모\n- x\n## 14:00 · shop-web\r\n- 버튼\n";
    const e = parseWorklog(md);
    expect(e.map((x) => [x.time, x.project])).toEqual([["10:30", "shop-api"], ["14:00", "shop-web"]]);
    expect(e[0].body).toContain("## 메모");
  });

  it("일지 있는 프로젝트의 대화는 빼고 길이를 자른다", () => {
    const long = "가".repeat(PROMPT_CAP + 10);
    const r = filterActivity([rec(9, "prompt", "C:\\a\\shop-api", "x"), rec(10, "prompt", "C:\\a\\web", long)], new Set(["shop-api"]));
    expect(r).toHaveLength(1);
    expect(r[0].text.endsWith("…")).toBe(true);
    expect([...r[0].text].length).toBe(PROMPT_CAP + 1);
  });

  it("Jira 키는 알려진 접두사만", () => {
    expect(jiraKeysIn(["SHOP-12 고침, UTF-8, SHA-256, SHOP-3"], new Set(["SHOP"]))).toEqual(["SHOP-12", "SHOP-3"]);
    expect(jiraKeysIn(["SHOP-1"], new Set())).toEqual([]);
  });

  it("프롬프트에 섹션이 다 들어간다", () => {
    const i: SummaryInput = {
      dayKey: "2026-11-13", worklogRaw: null, worklogProjects: new Set(), activity: [rec(9, "prompt", "C:\\w\\api", "질문")],
      commits: { api: ["abc123 fix"] }, jiraKeys: { api: ["SHOP-1"] }, worklogSectionCount: 0, activityDropped: 0, projects: ["api"],
    };
    const p = buildPrompt(i);
    expect(p).toContain("2026-11-13 개발자 업무 요약");
    expect(p).toContain("=== 1) 업무 일지 ===\n(없음)");
    expect(p).toContain("[09:00] user: 질문");
    expect(p).toContain("=== 3) 커밋: api ===\nabc123 fix");
    expect(p).toContain("=== 4) Jira 키 ===\napi: SHOP-1");
    expect(buildPrompt(i, "커스텀 {날짜}").startsWith("커스텀 2026-11-13")).toBe(true);
    expect(isEmptyInput({ ...i, activity: [], commits: {} })).toBe(true);
  });

  it("ISO 주와 화면 이름", () => {
    const d = new Date(2026, 10, 13); // 금
    expect(weekDays(d).key).toBe("2026-W46");
    expect(weekDays(new Date(2027, 0, 1)).key).toBe("2026-W53");
    expect(weekLabel(d)).toBe("2026-W46 (11/09~11/15)");
    expect(weekTitle(d, d)).toEqual({ title: "11월 2주차", range: "11/9(월) ~ 11/15(일)" });
    expect(dayTitle(d, d)).toBe("11월 13일 (금)");
    expect(dayTitle(d, new Date(2027, 0, 1))).toBe("2026년 11월 13일 (금)");
  });

  it("다음 생성 시각과 놓친 날", () => {
    const now = new Date(2026, 10, 13, 17, 0);
    expect(nextFire(now, 18, 0).getHours()).toBe(18);
    expect(nextFire(new Date(2026, 10, 13, 18, 0), 18, 0).getDate()).toBe(14);
    expect(catchUpDays(now, 18, 0)).toHaveLength(7);
    expect(catchUpDays(new Date(2026, 10, 13, 19, 0), 18, 0)).toHaveLength(8);
  });

  it("claude 오류 안내", () => {
    expect(claudeHint("Error: Please run /login")).toContain("로그인");
    expect(claudeHint("rate_limit_error")).toContain("한도");
    expect(claudeHint("boom")).toBeNull();
  });

  it("Markdown 은 이스케이프 후 강조만", () => {
    const h = renderMarkdown("# 제목\n## 프로젝트\n- **굵게** `코드` <script>\n  - 하위\n[링크](https://a.com)");
    expect(h).toContain("<h1>제목</h1>");
    expect(h).toContain("<b>굵게</b>");
    expect(h).toContain("<code>코드</code>");
    expect(h).toContain("&lt;script&gt;");
    expect(h).toContain('class="li li2"');
    expect(h).toContain('<a href="https://a.com" data-ext>링크</a>');
  });
});
