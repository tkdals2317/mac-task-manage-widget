import { describe, expect, it } from "vitest";
import { attachmentName, commentDocument, esc, reportFileName, reportHtml, safe, stamp } from "./e2eReport";
import { newJob, parseResult, type IssueResult, type Job } from "./e2eCore";

// 로컬 시각으로 만든 날짜라 어떤 시간대(CI 는 UTC)에서도 같은 글자가 나온다
const when = new Date(2026, 10, 20, 9, 5);
const job = (p: Partial<Job> = {}): Job => ({
  ...newJob({ id: "20261120090500-ab12", env: "ST", baseUrl: "https://st.example.com", username: "qa", now: when,
    issues: [{ key: "ABC-1", url: "https://acme.atlassian.net/browse/ABC-1", title: "제목" }, { key: "ABC-2", url: "https://evil.example.com/browse/ABC-2", title: "" }] }), ...p,
});
const result = (o: unknown) => { const r = parseResult(JSON.stringify(o)); if (r.kind !== "ok") throw new Error("bad"); return r.result; };

describe("파일·첨부 이름", () => {
  it("로컬 시각 서식", () => {
    expect(stamp(when, "date")).toBe("20261120-0905");
    expect(stamp(when, "full")).toBe("2026-11-20 09:05");
    expect(stamp(when, "time")).toBe("09:05");
  });
  it("보고서 파일 이름: 첫 이슈 + 나머지 수 + 환경 + 시각", () => {
    expect(reportFileName(job())).toBe("ATM-E2E-ABC-1+1-ST-20261120-0905.html");
    expect(reportFileName(job({ issues: [] }))).toBe("ATM-E2E-20261120090500-ab12-ST-20261120-0905.html");
  });
  it("첨부 이름은 환경·시각을 붙이고 위험한 글자를 뺀다", () => {
    expect(attachmentName(job(), "ABC-1-1.png")).toBe("E2E-ST-20261120-0905-ABC-1-1.png");
    expect(attachmentName(job(), "dir/../a b.PNG")).toBe("E2E-ST-20261120-0905-ab.png");
    expect(attachmentName(job(), "")).toBe("E2E-ST-20261120-0905-shot");
    expect(safe("a/b c:d-e_f")).toBe("abcd-e_f");
  });
});

describe("HTML 보고서", () => {
  const issues = [{ key: "ABC-1", title: "<script>x</script>", verdict: "FAIL", assumptions: ["가정 <b>"], scenarios: [{ name: "시나리오 & 1", steps: ["a"], expected: "e", actual: "<img onerror=x>", verdict: "FAIL", screenshots: ["../shot.png", "none.png"] }] }, { key: "ABC-2", verdict: "PASS" }];
  const html = reportHtml({
    job: job({ notes: "메모 <i>" }), result: { kind: "ok", result: result({ summary: "요약 <u>", loginBlocked: "TWO_FACTOR", issues }) }, modelName: "기본", logTail: "",
    jiraBase: "https://acme.atlassian.net", image: (n) => (n.split("/").pop() === "shot.png" ? { mime: "image/png", base64: "QUJD" } : null),
  });
  it("Aside 가 쓴 글자는 모두 이스케이프한다", () => {
    expect(html).not.toContain("<script>x");
    expect(html).not.toContain("<img onerror");
    expect(html).toContain("&lt;script&gt;x&lt;/script&gt;");
    expect(html).toContain("요약 &lt;u&gt;");
    expect(html).toContain("메모 &lt;i&gt;");
    expect(esc(`<>&"'`)).toBe("&lt;&gt;&amp;&quot;&#39;");
  });
  it("스크린샷은 이름만 보고 data URI 로, 링크는 설정한 Jira 호스트의 것만", () => {
    expect(html).toContain('src="data:image/png;base64,QUJD"');
    expect(html).toContain('<a href="https://acme.atlassian.net/browse/ABC-1">ABC-1</a>');
    expect(html).not.toContain("evil.example.com");
    expect(html).toContain("Content-Security-Policy");
  });
  it("로그인 막힘과 판정 수가 들어간다", () => {
    expect(html).toContain("환경 로그인에서 막혔어요");
    expect(html).toContain("2단계 인증");
    expect(html).toContain("FAIL 1");
    expect(html).toContain("PASS 1");
  });
  it("결과가 없으면 run.log 끝부분을 보여준다", () => {
    const h = reportHtml({ job: job(), result: { kind: "missing" }, modelName: "m", logTail: "boom <x>", jiraBase: "", image: () => null });
    expect(h).toContain("결과가 없어요");
    expect(h).toContain("boom &lt;x&gt;");
  });
});

describe("Jira 댓글(ADF)", () => {
  const issue = result({ issues: [{ key: "ABC-1", verdict: "pass", assumptions: ["가정"], notes: "비고", scenarios: [
    { name: "s1", steps: ["a", "b"], expected: "E", actual: "A\n\nB", verdict: "PASS", screenshots: ["one.png", "two.png", "one.png"] }] }] }).issues[0] as IssueResult;
  const doc = (o: Partial<Parameters<typeof commentDocument>[0]> = {}) => commentDocument({ job: job({ notes: "n" }), issue, modelName: "M", ...o }) as { type: string; version: number; content: Record<string, unknown>[] };
  const flat = (d: unknown): string => JSON.stringify(d);

  it("doc 모양과 머리글·환경 줄", () => {
    const d = doc();
    expect(d.type).toBe("doc");
    expect(d.version).toBe(1);
    expect(d.content[0]).toMatchObject({ type: "heading", attrs: { level: 3 } });
    expect(flat(d)).toContain("환경 ST · https://st.example.com · 모델 M · 2026-11-20 09:05");
    expect(flat(d)).toContain("추가 요청사항: ");
  });
  it("이미지로 넣은 스크린샷은 mediaSingle, 못 넣은 것은 첨부 이름만 적는다 (중복은 한 번)", () => {
    const d = doc({ attached: { "one.png": "E2E-one.png", "two.png": "E2E-two.png" }, media: { "one.png": "11111111-1111-1111-1111-111111111111" } });
    const media = d.content.filter((n) => n.type === "mediaSingle");
    expect(media).toHaveLength(1);
    expect(flat(media[0])).toContain('"collection":""');
    expect(flat(d)).toContain("스크린샷(첨부): ");
    expect(flat(d)).toContain("E2E-two.png");
    expect(flat(d)).not.toContain("E2E-one.png");
  });
  it("빈 텍스트 노드를 만들지 않고, Aside 글자는 마크업 없이 텍스트로만", () => {
    const evil = result({ issues: [{ key: "A-1", scenarios: [{ name: "", actual: "@everyone [x](http://e) {code}" }] }] }).issues[0];
    const d = commentDocument({ job: job(), issue: evil, modelName: "M" });
    const texts: string[] = [];
    (function walk(n: unknown) { if (Array.isArray(n)) n.forEach(walk); else if (n && typeof n === "object") { const o = n as Record<string, unknown>; if (o.type === "text") texts.push(o.text as string); Object.values(o).forEach(walk); } })(d);
    expect(texts.every((t) => t.length > 0)).toBe(true);
    expect(texts).toContain("@everyone [x](http://e) {code}");
    expect(flat(d)).not.toContain('"type":"mention"');
    expect(flat(d)).not.toContain('"type":"link"');
  });
  it("시나리오가 많으면 줄인다", () => {
    const many = result({ issues: [{ key: "A-1", scenarios: Array.from({ length: 33 }, (_, i) => ({ name: `s${i}` })) }] }).issues[0];
    expect(flat(commentDocument({ job: job(), issue: many, modelName: "M" }))).toContain("시나리오 3개는 줄였어요");
  });
});
