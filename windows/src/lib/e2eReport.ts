// 검증 결과를 HTML 파일 하나로 내보내고(Mac E2EReport), Jira 댓글(ADF)로 만든다(Mac E2EJiraComment).
// Aside 가 쓴 글자는 모두 글자로만 넣는다 (HTML 은 이스케이프, ADF 는 텍스트 노드). 링크는 ATM 이 만든 Jira 주소만.
import { failureOfMessage, failureSteps } from "./asideCore";
import {
  jiraURL, loginBlockReason, loginBlockSteps, statusLabel, verdictCounts, VERDICT_ORDER, type IssueResult, type Job, type Result, type ResultLoad, type Scenario, type Verdict,
} from "./e2eCore";

const pad = (n: number) => String(n).padStart(2, "0");
/** 로컬 시각 서식: date = yyyyMMdd-HHmm, full = yyyy-MM-dd HH:mm, time = HH:mm */
export function stamp(d: Date, f: "date" | "full" | "time"): string {
  const day = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`, hm = `${pad(d.getHours())}${pad(d.getMinutes())}`;
  return f === "date" ? `${day}-${hm}` : f === "full" ? `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}` : `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** 파일 이름에 써도 되는 글자(영문·숫자·-·_)만 남긴다. */
export const safe = (s: string) => [...s].filter((c) => /[A-Za-z0-9_-]/.test(c)).slice(0, 40).join("");
const baseName = (n: string) => n.split(/[\\/]/).pop() ?? "";
const extOf = (n: string) => { const i = n.lastIndexOf("."); return i > 0 ? n.slice(i + 1).toLowerCase() : ""; };
const stemOf = (n: string) => { const i = n.lastIndexOf("."); return i > 0 ? n.slice(0, i) : n; };

export function mimeOf(ext: string): string {
  switch (ext.toLowerCase()) {
    case "jpg": case "jpeg": return "image/jpeg";
    case "webp": return "image/webp";
    case "gif": return "image/gif";
    default: return "image/png";
  }
}

/** `ATM-E2E-<첫 이슈 키>[+N]-<환경>-<yyyyMMdd-HHmm>.html`. 이슈가 없으면 job id. */
export function reportFileName(job: Job): string {
  const keys = job.issues.map((i) => safe(i.key)).filter(Boolean);
  let name = keys[0] ?? safe(job.id);
  if (keys.length > 1) name += `+${keys.length - 1}`;
  return `ATM-E2E-${name}-${job.env}-${stamp(job.createdAt, "date")}.html`;
}

// ---- HTML ----
export const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

export interface ReportImage { mime: string; base64: string }

export function reportHtml(o: { job: Job; result: ResultLoad; modelName: string; logTail?: string; jiraBase: string; image: (name: string) => ReportImage | null }): string {
  const { job, result } = o;
  const b: string[] = [];
  const keys = job.issues.map((i) => i.key).join(", ");
  b.push("<!doctype html>", '<html lang="ko"><head><meta charset="utf-8">', '<meta name="viewport" content="width=device-width, initial-scale=1">',
    `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">`,
    `<title>E2E 검증 결과 · ${esc(keys || job.id)}</title>`, `<style>${STYLE}</style></head><body>`, "<h1>E2E 검증 결과</h1>", meta(job, o.modelName));
  if (job.error) {
    const k = job.status === "failed" ? failureOfMessage(job.error) : null;
    b.push(box("warn", "검증을 돌리지 못했어요", job.error, k ? failureSteps(k) : []));
  }
  switch (result.kind) {
    case "ok": {
      const r = result.result;
      if (r.loginBlocked) {
        const account = job.username ? `테스트 계정(${job.username})` : "테스트 계정";
        b.push(box("warn", "환경 로그인에서 막혔어요", loginBlockReason(r.loginBlocked), loginBlockSteps(r.loginBlocked, account)));
      }
      b.push(summary(r));
      for (const i of r.issues) b.push(issueSection(i, job, o.jiraBase, o.image));
      break;
    }
    case "invalid":
      b.push(box("warn", "result.json 을 읽지 못했어요", result.message, []), logBlock(o.logTail ?? ""));
      break;
    case "missing":
      if (!job.error) b.push('<p class="dim">결과가 없어요</p>');
      b.push(logBlock(o.logTail ?? ""));
      break;
  }
  b.push("<footer>ATM 자동 검증 결과는 참고용이에요. 가정과 스크린샷을 같이 확인해 주세요.</footer>", "</body></html>");
  return b.filter(Boolean).join("\n");
}

function meta(job: Job, modelName: string): string {
  const rows: [string, string][] = [];
  if (job.issues.length) rows.push(["이슈", job.issues.map((i) => i.key).join(", ")]);
  rows.push(["환경", job.env + (job.readOnly ? " · 조회만" : "")], ["주소", job.baseUrl]);
  if (job.username) rows.push(["테스트 계정", job.username]);
  rows.push(["모델", modelName]);
  let time = stamp(job.createdAt, "full");
  if (job.finishedAt) time += " ~ " + stamp(job.finishedAt, "time");
  rows.push(["실행", time], ["상태", statusLabel(job.status)]);
  if (job.notes) rows.push(["추가 요청사항", job.notes]);
  return `<table class="meta">${rows.map(([k, v]) => `<tr><th>${esc(k)}</th><td>${esc(v)}</td></tr>`).join("")}</table>`;
}

function summary(r: Result): string {
  const counts = verdictCounts(r);
  const badges = VERDICT_ORDER.filter((v) => counts[v] !== undefined).map((v) => badge(v, counts[v]));
  if (!badges.length && !r.summary) return "";
  return `<section class="summary"><div>${badges.join(" ")}</div>${r.summary ? `<p>${esc(r.summary)}</p>` : ""}</section>`;
}

function issueSection(issue: IssueResult, job: Job, jiraBase: string, image: (n: string) => ReportImage | null): string {
  const ref = job.issues.find((i) => i.key === issue.key);
  const url = ref ? jiraURL(ref.url, jiraBase) : null;
  const key = url ? `<a href="${esc(url)}">${esc(issue.key)}</a>` : esc(issue.key);
  const title = issue.title || ref?.title || "";
  const b = ['<section class="issue">', `<h2>${key} ${esc(title)} ${badge(issue.verdict)}</h2>`];
  if (issue.assumptions.length) b.push(`<div class="box warn"><strong>가정</strong>${list(issue.assumptions, false)}</div>`);
  for (const s of issue.scenarios) b.push(scenario(s, image));
  if (issue.notes) b.push(`<p class="dim">${esc(issue.notes)}</p>`);
  b.push("</section>");
  return b.join("\n");
}

function scenario(s: Scenario, image: (n: string) => ReportImage | null): string {
  const b = ['<div class="scenario">', `<h3>${esc(s.name)} ${badge(s.verdict)}</h3>`];
  if (s.steps.length) b.push(list(s.steps, true));
  const rows: string[] = [];
  if (s.expected) rows.push(`<tr><th>기대</th><td>${esc(s.expected)}</td></tr>`);
  if (s.actual) rows.push(`<tr><th>실제</th><td>${esc(s.actual)}</td></tr>`);
  if (rows.length) b.push(`<table class="meta">${rows.join("")}</table>`);
  for (const name of s.screenshots) {
    const img = image(name);
    if (!img) continue;
    const caption = baseName(name);
    b.push(`<figure><img alt="${esc(caption)}" src="data:${esc(img.mime)};base64,${img.base64}"><figcaption>${esc(caption)}</figcaption></figure>`);
  }
  b.push("</div>");
  return b.join("\n");
}

const box = (kind: string, title: string, text: string, steps: string[]) =>
  `<div class="box ${kind}"><strong>${esc(title)}</strong><p>${esc(text)}</p>${steps.length ? list(steps, true) : ""}</div>`;
const logBlock = (tail: string) => (tail ? `<h3>run.log 마지막 부분</h3><pre>${esc(tail)}</pre>` : "");
const list = (items: string[], ordered: boolean) => { const t = ordered ? "ol" : "ul"; return `<${t}>${items.map((i) => `<li>${esc(i)}</li>`).join("")}</${t}>`; };
const badge = (v: Verdict | null, count?: number) =>
  `<span class="badge ${v ? v.toLowerCase() : "unknown"}">${[v ?? "?", count].filter((x) => x !== undefined).join(" ")}</span>`;

const STYLE = `:root { color-scheme: light dark; --line: rgba(128,128,128,.3); --soft: rgba(128,128,128,.1); }
body { font: 14px/1.55 "Segoe UI", "Malgun Gothic", -apple-system, sans-serif; max-width: 920px; margin: 0 auto; padding: 24px 20px 48px; }
h1 { font-size: 20px; margin: 0 0 12px; }
h2 { font-size: 16px; margin: 0 0 10px; }
h3 { font-size: 14px; margin: 0 0 6px; }
p, td, li, pre { white-space: pre-wrap; overflow-wrap: anywhere; }
p { margin: 6px 0; }
ol, ul { margin: 4px 0; padding-left: 22px; }
table.meta { border-collapse: collapse; margin: 6px 0; }
table.meta th { text-align: left; font-weight: 600; opacity: .65; padding: 2px 14px 2px 0; vertical-align: top; white-space: nowrap; }
table.meta td { padding: 2px 0; }
section { border: 1px solid var(--line); border-radius: 8px; padding: 14px 16px; margin: 14px 0; }
.scenario { border-top: 1px solid var(--line); padding-top: 12px; margin-top: 12px; }
.box { border-radius: 6px; padding: 10px 12px; margin: 10px 0; background: var(--soft); }
.box.warn { background: rgba(255,149,0,.14); }
.badge { display: inline-block; font-size: 11px; font-weight: 700; padding: 1px 6px; border-radius: 4px; vertical-align: middle; background: var(--soft); }
.badge.pass { color: #1a7f37; background: rgba(26,127,55,.14); }
.badge.fail { color: #d1242f; background: rgba(209,36,47,.14); }
.badge.blocked { color: #b35900; background: rgba(255,149,0,.18); }
.dim, footer, figcaption { opacity: .65; }
figure { margin: 10px 0 0; }
figure img { max-width: 100%; border: 1px solid var(--line); border-radius: 4px; }
figcaption { font-size: 12px; }
pre { font: 12px/1.45 Consolas, ui-monospace, monospace; background: var(--soft); border-radius: 6px; padding: 10px 12px; }
footer { font-size: 12px; margin-top: 20px; }`;

// ---- Jira 댓글 (ADF) ----
export const MAX_TEXT = 1500;
export const MAX_SCENARIOS = 30;

type Node = Record<string, unknown>;
const text = (s: string, strong = false): Node => ({ type: "text", text: s || " ", ...(strong ? { marks: [{ type: "strong" }] } : {}) }); // ADF 는 빈 텍스트 노드를 받지 않는다
const node = (type: string, content: Node[], attrs?: Node): Node => ({ type, content, ...(attrs ? { attrs } : {}) });
const paragraph = (c: Node[]) => node("paragraph", c);
const HARD_BREAK: Node = { type: "hardBreak" };
const clip = (s: string) => (s.length > MAX_TEXT ? s.slice(0, MAX_TEXT) + "…" : s);
/** 줄마다의 노드를 hardBreak 로 이어 한 문단의 내용으로 만든다. */
const broken = (lines: Node[][]): Node[] => lines.flatMap((l, i) => (i ? [HARD_BREAK, ...l] : l));
/** 줄바꿈은 hardBreak 로, 빈 줄은 건너뛴다. 너무 긴 글은 줄인다. */
const inline = (s: string): Node[] => {
  const lines = clip(s).split(/\r?\n/).filter((l) => l.trim());
  return lines.length ? broken(lines.map((l) => [text(l)])) : [text(" ")];
};
const adfList = (type: string, items: string[]) => node(type, items.map((i) => node("listItem", [paragraph(inline(i))])));
/** 이슈 첨부 이미지. Jira 편집기가 붙여 넣은 이미지와 같은 모양(collection 은 빈 값)이다. */
const imageNode = (mediaId: string) => node("mediaSingle", [{ type: "media", attrs: { type: "file", id: mediaId, collection: "" } }], { layout: "center" });

/** Jira 에 올릴 첨부 이름. 다른 실행의 같은 이름 스크린샷과 섞이지 않게 환경·실행 시각을 붙인다. */
export function attachmentName(job: Job, screenshot: string): string {
  const base = baseName(screenshot), ext = safe(extOf(base)), stem = safe(stemOf(base));
  const name = `E2E-${job.env}-${stamp(job.createdAt, "date")}-${stem || "shot"}`;
  return ext ? `${name}.${ext}` : name;
}

/**
 * attached: 스크린샷 이름 → Jira 에 올린 첨부 이름 (올린 것만).
 * media: 스크린샷 이름 → 그 첨부의 Media 파일 id. 있으면 시나리오 아래 이미지로 넣고, 없으면 첨부 이름만 적는다.
 */
export function commentDocument(o: { job: Job; issue: IssueResult; modelName: string; attached?: Record<string, string>; media?: Record<string, string> }): Node {
  const { job, issue } = o, attached = o.attached ?? {}, media = o.media ?? {};
  const content: Node[] = [node("heading", [text("E2E 자동 검증 · "), text(issue.verdict ?? "판정 없음", true)], { level: 3 })];
  let m = `환경 ${job.env}`;
  if (job.readOnly) m += " (조회만)";
  if (job.baseUrl) m += ` · ${job.baseUrl}`;
  m += ` · 모델 ${o.modelName} · ${stamp(job.createdAt, "full")}`;
  content.push(paragraph(inline(m)));
  if (job.notes) content.push(paragraph([text("추가 요청사항: ", true), ...inline(job.notes)]));
  if (issue.assumptions.length) content.push(paragraph([text("가정", true)]), adfList("bulletList", issue.assumptions));
  for (const s of issue.scenarios.slice(0, MAX_SCENARIOS)) {
    content.push(paragraph([text(s.verdict ?? "?", true), text(" " + (s.name ? clip(s.name) : "시나리오"))]));
    if (s.steps.length) content.push(adfList("orderedList", s.steps));
    const lines: Node[][] = [];
    if (s.expected) lines.push([text("기대: ", true), ...inline(s.expected)]);
    if (s.actual) lines.push([text("실제: ", true), ...inline(s.actual)]);
    const seen = new Set<string>();
    const shots = s.screenshots.map(baseName).filter((n) => n && !seen.has(n) && seen.add(n));
    const named = shots.filter((n) => !media[n]).flatMap((n) => (attached[n] ? [attached[n]] : []));
    if (named.length) lines.push([text("스크린샷(첨부): ", true), text(named.join(", "))]);
    if (lines.length) content.push(paragraph(broken(lines)));
    content.push(...shots.flatMap((n) => (media[n] ? [imageNode(media[n])] : [])));
  }
  if (issue.scenarios.length > MAX_SCENARIOS) content.push(paragraph([text(`… 시나리오 ${issue.scenarios.length - MAX_SCENARIOS}개는 줄였어요`)]));
  if (issue.notes) content.push(paragraph(inline(issue.notes)));
  content.push(paragraph([text("ATM 이 Aside 로 돌린 자동 검증 결과예요. 참고용이니 가정과 스크린샷을 같이 확인해 주세요.")]));
  return { type: "doc", version: 1, content };
}
