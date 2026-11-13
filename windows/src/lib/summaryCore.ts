// 요약 로직 (Mac SummaryPrompt·Worklog·ActivityLog·SummaryService·Schedule 포팅). 파일·프로세스는 쓰지 않는 순수 함수.

export interface ActivityRecord { ts: Date; event: "prompt" | "stop"; session: string; cwd: string; text: string }
export interface WorklogEntry { time: string; project: string; body: string }
export interface SummaryInput {
  dayKey: string;
  worklogRaw: string | null;
  worklogProjects: Set<string>;
  activity: ActivityRecord[];
  commits: Record<string, string[]>;
  jiraKeys: Record<string, string[]>;
  worklogSectionCount: number;
  activityDropped: number;
  projects: string[];
}

export const PROMPT_CAP = 400;
export const STOP_CAP = 1200;
export const TOTAL_CAP = 80_000;

const pad = (n: number) => String(n).padStart(2, "0");
export const dayKey = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
export const sameDay = (a: Date, b: Date) => dayKey(a) === dayKey(b);
export const addDays = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes());
export const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

/** cwd 의 마지막 경로 요소 (Windows·POSIX 구분자 모두). */
export const projectOf = (cwd: string) => cwd.replace(/[\\/]+$/, "").split(/[\\/]/).pop() ?? cwd;

/** activity.jsonl 한 줄씩. 깨진 줄은 건너뛰고 그날(로컬 날짜) 것만, 시각 순. */
export function parseActivity(jsonl: string, day: Date): ActivityRecord[] {
  const key = dayKey(day);
  const out: ActivityRecord[] = [];
  for (const line of jsonl.split("\n")) {
    if (!line.trim()) continue;
    try {
      const o = JSON.parse(line);
      const ts = new Date(o.ts);
      if (isNaN(ts.getTime()) || typeof o.text !== "string" || typeof o.cwd !== "string") continue;
      if ((o.event !== "prompt" && o.event !== "stop") || dayKey(ts) !== key) continue;
      out.push({ ts, event: o.event, session: String(o.session ?? ""), cwd: o.cwd, text: o.text });
    } catch { /* 깨진 줄 */ }
  }
  return out.sort((a, b) => a.ts.getTime() - b.ts.getTime());
}

/** `## HH:mm · project` 헤더로 나눈다. 형식이 아닌 `##` 줄은 본문. */
export function parseWorklog(md: string): WorklogEntry[] {
  const out: WorklogEntry[] = [];
  let cur: { time: string; project: string; lines: string[] } | null = null;
  const flush = () => { if (cur) out.push({ time: cur.time, project: cur.project, body: cur.lines.join("\n").trim() }); };
  for (const line of md.replace(/\r\n/g, "\n").split("\n")) {
    const h = worklogHeader(line);
    if (h) { flush(); cur = { ...h, lines: [] }; } else if (cur) cur.lines.push(line);
  }
  flush();
  return out;
}

function worklogHeader(line: string): { time: string; project: string } | null {
  if (!line.startsWith("## ")) return null;
  const rest = line.slice(3);
  const i = rest.indexOf(" · ");
  if (i < 0) return null;
  const time = rest.slice(0, i), project = rest.slice(i + 3).trim();
  return /^\d{2}:\d{2}$/.test(time) && project ? { time, project } : null;
}

/** 일지가 있는 프로젝트의 대화는 버리고, 메시지별 길이 제한, 총량 초과분은 오래된 것부터 뺀다. */
export function filterActivity(recs: ActivityRecord[], covered: Set<string>): ActivityRecord[] {
  const kept = recs.filter((r) => !covered.has(projectOf(r.cwd))).map((r) => {
    const cap = r.event === "prompt" ? PROMPT_CAP : STOP_CAP;
    return [...r.text].length > cap ? { ...r, text: [...r.text].slice(0, cap).join("") + "…" } : r;
  });
  let total = kept.reduce((n, r) => n + r.text.length, 0);
  while (total > TOTAL_CAP && kept.length) total -= kept.shift()!.text.length;
  return kept;
}

export const isEmptyInput = (i: SummaryInput) =>
  !(i.worklogRaw ?? "").trim() && !i.activity.length && Object.values(i.commits).every((c) => !c.length);

const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
/** 알려진 프로젝트 접두사의 Jira 키만. 중복 제거, 정렬. */
export function jiraKeysIn(texts: string[], prefixes: Set<string>): string[] {
  if (!prefixes.size) return [];
  const re = new RegExp(`\\b(?:${[...prefixes].map(esc).sort().join("|")})-\\d+\\b`, "g");
  const keys = new Set<string>();
  for (const t of texts) for (const m of t.matchAll(re)) keys.add(m[0]);
  return [...keys].sort();
}

export const hhmm = (d: Date) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;

export const DEFAULT_INSTRUCTIONS = `{날짜} 개발자 업무 요약을 한국어 Markdown으로 쓰세요. 도구 사용 금지, 아래 데이터만 근거로.
근거 우선순위: 1) 업무 일지 > 3) 커밋 > 2) 대화 기록.

규칙:
- 끝낸 일의 결과만 짧게. 한 줄 = 한 항목, 동사로 끝내는 개조식 ("~ 수정", "~ 추가").
- 과정·시행착오·조사·잡담·질문 응답, 미완료·다음 할 일은 쓰지 않음.
- 비슷한 항목은 하나로 합침. 프로젝트당 최대 5개.
- 데이터에 Jira 키(예: ABC-123)가 있으면 관련 항목 끝에 (ABC-123) 처럼 붙임.
- 머리말·맺음말 없이 아래 형식만 출력.

# {날짜} 업무 요약
## {프로젝트명}
- 한 일`;

export const WEEKLY_INSTRUCTIONS = `{주} 개발자 주간 업무 요약을 한국어 Markdown으로 쓰세요. 도구 사용 금지, 아래 일간 요약만 근거로.
- 여러 날에 걸친 같은 작업은 하나로 합쳐 결과만 씀. 날짜별로 나열하지 않음.
- 한 줄 = 한 항목, 동사로 끝내는 개조식. 프로젝트당 최대 7개.
- Jira 키가 있으면 항목 끝에 그대로 유지.
- 과정·미완료·다음 할 일·머리말·맺음말 없음.

# {주} 주간 업무 요약
## {프로젝트명}
- 한 일`;

export function buildPrompt(i: SummaryInput, instructions?: string | null): string {
  const custom = (instructions ?? "").trim();
  let s = (custom || DEFAULT_INSTRUCTIONS).replaceAll("{날짜}", i.dayKey);
  const worklog = (i.worklogRaw ?? "").trim();
  s += "\n\n=== 1) 업무 일지 ===\n" + (worklog || "(없음)");
  const groups = new Map<string, ActivityRecord[]>();
  for (const r of i.activity) groups.set(projectOf(r.cwd), [...(groups.get(projectOf(r.cwd)) ?? []), r]);
  if (!groups.size) s += "\n\n=== 2) 대화 기록 ===\n(없음)";
  for (const p of [...groups.keys()].sort()) {
    const recs = groups.get(p)!.sort((a, b) => a.ts.getTime() - b.ts.getTime());
    s += `\n\n=== 2) 대화 기록: ${p} (${recs[0].cwd}) ===`;
    for (const r of recs) s += `\n[${hhmm(r.ts)}] ${r.event === "prompt" ? "user" : "assistant"}: ${r.text}`;
  }
  const commits = Object.entries(i.commits).filter(([, v]) => v.length);
  if (!commits.length) s += "\n\n=== 3) 커밋 ===\n(없음)";
  for (const [p, lines] of commits.sort(([a], [b]) => (a < b ? -1 : 1))) s += `\n\n=== 3) 커밋: ${p} ===\n` + lines.join("\n");
  const keys = Object.entries(i.jiraKeys).filter(([, v]) => v.length).sort(([a], [b]) => (a < b ? -1 : 1));
  if (keys.length) s += "\n\n=== 4) Jira 키 ===\n" + keys.map(([p, k]) => `${p}: ${k.join(", ")}`).join("\n");
  return s + "\n";
}

export const noRecordMarkdown = (key: string) => `# ${key} 업무 요약\n\n오늘 기록 없음\n`;

// ---- 주 ----

/** ISO 주 (월~일). key 는 "2026-W46". */
export function weekDays(day: Date): { key: string; days: Date[] } {
  const d = startOfDay(day);
  const dow = (d.getDay() + 6) % 7; // 월=0
  const monday = addDays(d, -dow);
  const days = Array.from({ length: 7 }, (_, i) => addDays(monday, i));
  const thu = days[3];
  const year = thu.getFullYear();
  const jan4 = new Date(year, 0, 4);
  const week1Monday = addDays(jan4, -((jan4.getDay() + 6) % 7));
  const week = Math.round((startOfDay(monday).getTime() - week1Monday.getTime()) / (7 * 86400000)) + 1;
  return { key: `${year}-W${pad(week)}`, days };
}

const WD = ["일", "월", "화", "수", "목", "금", "토"];
const short = (d: Date) => `${d.getMonth() + 1}/${d.getDate()}(${WD[d.getDay()]})`;

/** "2026-W46 (11/09~11/15)" (프롬프트용) */
export function weekLabel(day: Date): string {
  const { key, days } = weekDays(day);
  const md = (d: Date) => `${pad(d.getMonth() + 1)}/${pad(d.getDate())}`;
  return `${key} (${md(days[0])}~${md(days[6])})`;
}

/** 화면용 ("11월 2주차", "11/9(월) ~ 11/15(일)"). 목요일이 있는 달로 센다. */
export function weekTitle(day: Date, now = new Date()): { title: string; range: string } {
  const days = weekDays(day).days;
  const thu = days[3];
  const nth = Math.floor((thu.getDate() - 1) / 7) + 1;
  const year = thu.getFullYear() === now.getFullYear() ? "" : `${thu.getFullYear()}년 `;
  return { title: `${year}${thu.getMonth() + 1}월 ${nth}주차`, range: `${short(days[0])} ~ ${short(days[6])}` };
}

/** "11월 13일 (금)", 올해가 아니면 연도. */
export function dayTitle(d: Date, now = new Date()): string {
  const year = d.getFullYear() === now.getFullYear() ? "" : `${d.getFullYear()}년 `;
  return `${year}${d.getMonth() + 1}월 ${d.getDate()}일 (${WD[d.getDay()]})`;
}

// ---- 일정 ----

export function nextFire(now: Date, hour: number, minute: number): Date {
  const t = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, minute, 0);
  return t > now ? t : addDays(t, 1);
}

/** 놓친 날 후보: 최근 lookback 일 + (예정 시각이 지났으면) 오늘. 오래된 날부터. */
export function catchUpDays(now: Date, hour: number, minute: number, lookback = 7): Date[] {
  const today = startOfDay(now);
  const days = Array.from({ length: lookback }, (_, i) => addDays(today, -(lookback - i)));
  if (now >= new Date(today.getFullYear(), today.getMonth(), today.getDate(), hour, minute)) days.push(today);
  return days;
}

// ---- claude 오류 ----

export function claudeHint(output: string): string | null {
  const t = output.toLowerCase();
  const has = (...w: string[]) => w.some((x) => t.includes(x));
  if (has("failed to authenticate", "oauth", "not logged in", "please run /login", "invalid api key", "authentication_error"))
    return "Claude Code 로그인이 만료됐어요 · 터미널에서 claude 실행 → /login 후 다시 생성";
  if (has("usage limit", "rate limit", "rate_limit", "limit reached", "overloaded"))
    return "Claude 사용 한도에 걸렸거나 붐벼요 · 잠시 뒤 다시 생성";
  if (has("enotfound", "econnrefused", "econnreset", "network error", "getaddrinfo", "unable to connect"))
    return "Claude 서버에 연결하지 못했어요 · 인터넷 연결 확인 후 다시 생성";
  return null;
}

export const CLAUDE_NOT_FOUND = "claude CLI를 찾지 못했어요. PowerShell 에서 `(Get-Command claude).Source` 결과를 설정 > 요약 > claude 경로에 넣어 주세요.";
