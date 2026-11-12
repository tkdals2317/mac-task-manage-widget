// 요약 탭 상태 (Mac AppState 요약 부분 + SummaryService + Scheduler).
// 파일: summaries/YYYY-MM-DD.md, summaries/week-YYYY-Www.md, worklog/YYYY-MM-DD.md, activity.jsonl, logs/summary-*.log
import { sendNotification, isPermissionGranted, requestPermission } from "@tauri-apps/plugin-notification";
import { log, native, readJSON, writeJSON } from "./native";
import { settings } from "./settings.svelte";
import { runClaude } from "./claude";
import { jira } from "../tasks/jiraState.svelte";
import {
  WEEKLY_INSTRUCTIONS, buildPrompt, catchUpDays, dayKey, filterActivity, isEmptyInput, jiraKeysIn, nextFire, noRecordMarkdown,
  parseActivity, parseWorklog, projectOf, sameDay, weekDays, weekLabel, type SummaryInput,
} from "./summaryCore";

export interface Summary { key: string; markdown: string; generatedAt: Date }

export const sm = $state({
  summary: null as Summary | null,
  weekly: null as Summary | null,
  worklogRaw: null as string | null,
  generating: false,
  error: null as string | null,
  day: new Date(),
  edits: {} as Record<string, number>, // 파일 이름 → 직접 고친 시각(ms)
});

const EDITS = "summaries/.edits.json";
export const dailyFile = (d: Date) => `summaries/${dayKey(d)}.md`;
export const weeklyFile = (d: Date) => `summaries/week-${weekDays(d).key}.md`;
export const worklogFile = (d: Date) => `worklog/${dayKey(d)}.md`;
export const fileName = (d: Date, weekly: boolean) => (weekly ? weeklyFile(d) : dailyFile(d)).split("/").pop()!;

async function readSummary(name: string, key: string): Promise<Summary | null> {
  const md = await native.readText(name).catch(() => null);
  if (md == null) return null;
  const mtime = await native.fileMtime(name).catch(() => null);
  return { key, markdown: md, generatedAt: new Date(mtime ?? Date.now()) };
}

export const existingDaily = (d: Date) => readSummary(dailyFile(d), dayKey(d));
export const existingWeekly = (d: Date) => readSummary(weeklyFile(d), weekDays(d).key);

export async function loadSummary(d: Date): Promise<void> {
  sm.day = d;
  const [s, w] = await Promise.all([existingDaily(d), native.readText(worklogFile(d)).catch(() => null)]);
  if (!sameDay(sm.day, d)) return; // 그 사이 다른 날로 옮겼으면 버린다
  sm.summary = s;
  sm.worklogRaw = w;
}

export async function loadWeekly(d: Date): Promise<void> {
  sm.day = d;
  const w = await existingWeekly(d);
  if (weekDays(sm.day).key === weekDays(d).key) sm.weekly = w;
}

export async function loadEdits(): Promise<void> {
  sm.edits = await readJSON<Record<string, number>>(EDITS, {});
}

async function setEdit(name: string, at: number | null): Promise<void> {
  const next = { ...sm.edits };
  if (at == null) delete next[name]; else next[name] = at;
  sm.edits = next;
  await writeJSON(EDITS, next).catch(() => {});
}

// ---- 수집 ----

let gitPath: string | null | undefined;
async function git(args: string[]): Promise<{ code: number; out: string }> {
  if (gitPath === undefined) gitPath = (await native.which("git").catch(() => null))?.[0] ?? null;
  if (!gitPath) return { code: -1, out: "" };
  const r = await native.run(gitPath, args, { timeoutMs: 10_000 });
  return { code: r.code, out: r.stdout };
}

/** cwd 가 git 저장소면 그날 내 커밋 "<hash> <subject>" 최대 30개. */
async function commitsIn(cwd: string, day: Date): Promise<string[]> {
  if (!(await native.pathExists(cwd).catch(() => false))) return [];
  const probe = await git(["-C", cwd, "rev-parse", "--is-inside-work-tree"]);
  if (probe.code !== 0 || probe.out.trim() !== "true") return [];
  const me = await git(["-C", cwd, "config", "user.email"]);
  const args = ["-C", cwd, "log"];
  if (me.code === 0 && me.out.trim()) args.push(`--author=<${me.out.trim()}>`);
  const k = dayKey(day);
  const r = await git([...args, `--since=${k} 00:00:00`, `--until=${k} 23:59:59`, "--format=%h %s", "-n", "30"]);
  return r.code === 0 ? r.out.split("\n").map((l) => l.trim()).filter(Boolean) : [];
}

async function branchIn(cwd: string): Promise<string | null> {
  const r = await git(["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"]);
  const b = r.out.trim();
  return r.code === 0 && b && b !== "HEAD" ? b : null;
}

/** Jira 에서 본 이슈들의 프로젝트 키 (ABC-123 → ABC). */
const jiraPrefixes = () => new Set(jira.issues.map((i) => i.id.split("-")[0]).filter(Boolean));

export async function collect(day: Date): Promise<SummaryInput> {
  const key = dayKey(day);
  const raw = await native.readText(worklogFile(day)).catch(() => null);
  const entries = raw ? parseWorklog(raw) : [];
  const covered = new Set(entries.map((e) => e.project));
  const all = parseActivity((await native.readText("activity.jsonl").catch(() => null)) ?? "", day);
  const prefixes = jiraPrefixes();
  const commits: Record<string, string[]> = {};
  const branches: Record<string, string> = {};
  const seen = new Set<string>();
  for (const cwd of [...new Set(all.map((r) => r.cwd))].filter(Boolean).sort()) {
    const lines = (await commitsIn(cwd, day)).filter((l) => {
      const h = l.split(" ")[0];
      if (seen.has(h)) return false;
      seen.add(h);
      return true;
    });
    const p = projectOf(cwd);
    if (prefixes.size) { const b = await branchIn(cwd); if (b) branches[p] = b; }
    if (lines.length) commits[p] = [...(commits[p] ?? []), ...lines];
  }
  const activity = filterActivity(all, covered);
  const projects = [...new Set([...all.map((r) => projectOf(r.cwd)), ...covered])].sort();
  const jiraKeys: Record<string, string[]> = {};
  for (const p of projects) {
    const texts = [
      ...entries.filter((e) => e.project === p).map((e) => e.body),
      ...all.filter((r) => projectOf(r.cwd) === p).map((r) => r.text),
      ...(commits[p] ?? []),
      ...(branches[p] ? [branches[p]] : []),
    ];
    const keys = jiraKeysIn(texts, prefixes);
    if (keys.length) jiraKeys[p] = keys;
  }
  return {
    dayKey: key, worklogRaw: raw, worklogProjects: covered, activity, commits, jiraKeys,
    worklogSectionCount: entries.length, activityDropped: all.length - activity.length, projects,
  };
}

const claudeOpts = async () => ({ configured: settings.claudePath, model: settings.claudeModel, cwd: await native.dataDir() });

async function writeLog(key: string, text: string) {
  await native.writeText(`logs/summary-${key}.log`, text).catch(() => {});
}

// ---- 생성 ----

/** 성공하면 true. 실패 문구는 sm.error. */
export async function generateDaily(day: Date, force: boolean): Promise<boolean> {
  if (sm.generating) return false;
  if (!force && (await existingDaily(day))) return true;
  sm.generating = true;
  sm.error = null;
  const input = await collect(day).catch(() => null);
  const key = dayKey(day);
  let logText = input
    ? `[${key}] worklog_sections=${input.worklogSectionCount} activity_kept=${input.activity.length} activity_dropped=${input.activityDropped} projects=${input.projects.join(",")} commits=${Object.values(input.commits).reduce((n, c) => n + c.length, 0)}\n`
    : `[${key}] collect failed\n`;
  try {
    let md: string;
    if (!input || isEmptyInput(input)) {
      md = noRecordMarkdown(key);
      logText += "no records\n";
    } else {
      md = await runClaude(buildPrompt(input, settings.summaryInstructions), await claudeOpts());
    }
    await native.writeText(dailyFile(day), md);
    await writeLog(key, logText + "ok\n");
    if (force) await setEdit(fileName(day, false), null);
    if (sameDay(sm.day, day)) sm.summary = { key, markdown: md, generatedAt: new Date() };
    return true;
  } catch (e) {
    const m = e instanceof Error ? e.message : String(e);
    sm.error = m;
    await writeLog(key, logText + `error: ${m}\n`);
    log(`summary error: ${m}`);
    return false;
  } finally {
    sm.generating = false;
  }
}

/** 그 주의 일간 요약(“기록 없음” 제외)을 합쳐 주간 요약. 일간이 하나도 없으면 claude 를 부르지 않는다. */
export async function generateWeekly(day: Date, force: boolean): Promise<boolean> {
  if (sm.generating) return false;
  if (!force && (await existingWeekly(day))) return true;
  sm.generating = true;
  sm.error = null;
  const { key, days } = weekDays(day);
  try {
    let body = "", used = 0;
    for (const d of days) {
      const s = await existingDaily(d);
      if (!s || s.markdown === noRecordMarkdown(s.key)) continue;
      body += `\n\n=== ${s.key} ===\n` + s.markdown.trim();
      used++;
    }
    if (!used) {
      await writeLog(`week-${key}`, `[${key}] weekly daily_summaries=0\nno daily summaries\n`);
      sm.error = "이번 주 일간 요약 없음";
      return false;
    }
    const md = await runClaude(WEEKLY_INSTRUCTIONS.replaceAll("{주}", weekLabel(day)) + body + "\n", await claudeOpts());
    await native.writeText(weeklyFile(day), md);
    await writeLog(`week-${key}`, `[${key}] weekly daily_summaries=${used}\nok\n`);
    if (force) await setEdit(fileName(day, true), null);
    if (weekDays(sm.day).key === key) sm.weekly = { key, markdown: md, generatedAt: new Date() };
    return true;
  } catch (e) {
    sm.error = e instanceof Error ? e.message : String(e);
    await writeLog(`week-${key}`, `[${key}] error: ${sm.error}\n`);
    return false;
  } finally {
    sm.generating = false;
  }
}

/** 직접 고친 요약 저장. 수정 시각을 원래 생성 시각으로 되돌려 "생성" 시각이 바뀌지 않게 한다. */
export async function saveEdit(markdown: string, day: Date, weekly: boolean): Promise<boolean> {
  const name = weekly ? weeklyFile(day) : dailyFile(day);
  const old = weekly ? sm.weekly : sm.summary;
  try {
    await native.writeText(name, markdown);
    if (old) await native.setFileMtime(name, old.generatedAt.getTime()).catch(() => {});
    await setEdit(fileName(day, weekly), Date.now());
    const s = { key: weekly ? weekDays(day).key : dayKey(day), markdown, generatedAt: old?.generatedAt ?? new Date() };
    if (weekly) sm.weekly = s; else if (sameDay(sm.day, day)) sm.summary = s;
    return true;
  } catch (e) {
    sm.error = e instanceof Error ? e.message : String(e);
    return false;
  }
}

// ---- 일정 (Scheduler) ----

async function notify(title: string, body: string) {
  if (!settings.summaryNotify) return;
  try {
    let ok = await isPermissionGranted();
    if (!ok) ok = (await requestPermission()) === "granted";
    if (ok) sendNotification({ title, body });
  } catch { /* 알림 불가 */ }
}

/** 최근 7일 + (예정 시각이 지났으면) 오늘 중 요약이 없는 날을 오래된 날부터. 과거 날은 기록이 있을 때만. */
async function catchUpMissed(): Promise<void> {
  let skipPast = false;
  for (const day of catchUpDays(new Date(), settings.summaryHour, settings.summaryMinute)) {
    const isToday = sameDay(day, new Date());
    if (skipPast && !isToday) continue;
    if (sm.generating) return;
    if (await existingDaily(day)) continue;
    if (!isToday && isEmptyInput(await collect(day))) continue;
    const ok = await generateDaily(day, false);
    if (ok) await notify(isToday ? "오늘 요약 완료" : `${dayKey(day)} 요약 완료`, "");
    else if (sm.error) await notify("요약 실패", `${dayKey(day)}: ${sm.error}`);
    if (!ok && !isToday) skipPast = true;
  }
}

/** 패널이 떠 있는 동안 요약 시각을 지킨다. 깨어남·시각 변경은 1분마다 다시 확인해서 따라간다. */
export function startSummaryScheduler(): () => void {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let lastKey = "";
  let fireAt = 0;
  const arm = () => {
    clearTimeout(timer);
    const at = nextFire(new Date(), settings.summaryHour, settings.summaryMinute);
    fireAt = at.getTime();
    lastKey = `${settings.summaryHour}:${settings.summaryMinute}`;
    timer = setTimeout(async () => { await catchUpMissed(); arm(); }, Math.max(1000, fireAt - Date.now()));
  };
  // 잠자기 뒤엔 setTimeout 이 밀리므로 1분마다 시각·설정 변경을 본다
  const watch = setInterval(() => {
    const k = `${settings.summaryHour}:${settings.summaryMinute}`;
    if (k !== lastKey || Date.now() > fireAt + 60_000) { arm(); void catchUpMissed(); }
  }, 60_000);
  arm();
  setTimeout(() => void catchUpMissed(), 15_000); // 시작 직후는 Jira 등 다른 로딩을 먼저
  void loadEdits();
  return () => { clearTimeout(timer); clearInterval(watch); };
}
