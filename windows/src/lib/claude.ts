// Claude Code 연동 (Mac ClaudeRunner·ClaudeIntegration 포팅).
// - claude CLI 로 요약 생성 (도구·MCP 없이 텍스트만)
// - ~/.claude/settings.json 에 활동 훅(UserPromptSubmit·Stop → atm.exe --hook) 넣고 빼기 (백업 후)
// - /worklog 스킬, atm-todo 스킬 설치
import { native } from "./native";
import { CLAUDE_NOT_FOUND, claudeHint } from "./summaryCore";

export const HOOK_EVENTS = ["UserPromptSubmit", "Stop"] as const;
export type HookStatus = "installed" | "notInstalled" | "pathMismatch";

const SETTINGS = ".claude/settings.json";
const WORKLOG_SKILL = ".claude/skills/worklog/SKILL.md";
const TODO_SKILL = ".claude/skills/atm-todo/SKILL.md";

/** bash·cmd 어디서 실행돼도 되게 슬래시 경로 + 따옴표. */
export const hookCommand = (exe: string) => `"${exe.replace(/\\/g, "/")}" --hook`;

/** 우리 훅인가 (Mac 판의 TaskWidget, Windows 판의 atm.exe). */
export function isOurs(cmd: unknown): boolean {
  if (typeof cmd !== "string") return false;
  const c = cmd.toLowerCase();
  return (c.includes("taskwidget") || c.includes("atm.exe") || c.includes("/atm\"")) && c.trimEnd().endsWith("--hook");
}

type Json = Record<string, unknown>;
type HookGroup = { hooks?: { command?: unknown; [k: string]: unknown }[]; [k: string]: unknown };

export function hookStatusOf(root: Json, command: string): HookStatus {
  const hooks = (root.hooks ?? {}) as Record<string, HookGroup[]>;
  let found = 0, exact = 0;
  for (const ev of HOOK_EVENTS) {
    for (const g of Array.isArray(hooks[ev]) ? hooks[ev] : []) {
      for (const h of Array.isArray(g.hooks) ? g.hooks : []) {
        if (!isOurs(h.command)) continue;
        found++;
        if (h.command === command) exact++;
      }
    }
  }
  if (!found) return "notInstalled";
  return found === HOOK_EVENTS.length && exact === found ? "installed" : "pathMismatch";
}

/** 두 이벤트에 우리 훅을 넣거나 경로만 고친다. 다른 훅·키는 그대로. */
export function withHook(root: Json, command: string): Json {
  const hooks = { ...((root.hooks ?? {}) as Record<string, unknown>) };
  for (const ev of HOOK_EVENTS) {
    const groups: HookGroup[] = Array.isArray(hooks[ev]) ? structuredClone(hooks[ev] as HookGroup[]) : [];
    let found = false;
    for (const g of groups) {
      g.hooks = (Array.isArray(g.hooks) ? g.hooks : []).map((h) => (isOurs(h.command) ? ((found = true), { ...h, command }) : h));
    }
    if (!found) groups.push({ hooks: [{ type: "command", command, timeout: 5 }] });
    hooks[ev] = groups;
  }
  return { ...root, hooks };
}

/** 우리 훅만 뺀다. 비게 된 그룹·이벤트·hooks 키는 지운다. */
export function withoutHook(root: Json): Json {
  if (!root.hooks || typeof root.hooks !== "object") return root;
  const hooks = { ...(root.hooks as Record<string, unknown>) };
  for (const ev of HOOK_EVENTS) {
    if (!Array.isArray(hooks[ev])) continue;
    const kept = (hooks[ev] as HookGroup[])
      .map((g) => ({ ...g, hooks: (Array.isArray(g.hooks) ? g.hooks : []).filter((h) => !isOurs(h.command)) }))
      .filter((g) => g.hooks.length);
    if (kept.length) hooks[ev] = kept; else delete hooks[ev];
  }
  const out = { ...root };
  if (Object.keys(hooks).length) out.hooks = hooks; else delete out.hooks;
  return out;
}

/** 파일이 없으면 {}. 있는데 JSON 이 아니면 던진다 (사용자 설정을 덮어쓰지 않게). */
async function readSettings(): Promise<Json> {
  const raw = await native.homeRead(SETTINGS);
  if (raw == null || !raw.trim()) return {};
  const v = JSON.parse(raw);
  if (!v || typeof v !== "object" || Array.isArray(v)) throw new Error("~/.claude/settings.json 이 올바른 JSON 객체가 아니에요");
  return v as Json;
}

const writeSettings = (root: Json) => native.homeWrite(SETTINGS, JSON.stringify(sortKeys(root), null, 2) + "\n", true);

function sortKeys(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(sortKeys);
  if (v && typeof v === "object") return Object.fromEntries(Object.keys(v).sort().map((k) => [k, sortKeys((v as Json)[k])]));
  return v;
}

export async function hookStatus(): Promise<HookStatus> {
  try { return hookStatusOf(await readSettings(), hookCommand(await native.exePath())); } catch { return "notInstalled"; }
}
/** 백업 경로(있으면)를 돌려준다. */
export async function installHook(): Promise<string | null> {
  return writeSettings(withHook(await readSettings(), hookCommand(await native.exePath())));
}
export async function removeHook(): Promise<string | null> {
  return writeSettings(withoutHook(await readSettings()));
}

export const worklogSkillInstalled = async () => (await native.homeRead(WORKLOG_SKILL)) != null;
export const todoSkillInstalled = async () => (await native.homeRead(TODO_SKILL)) != null;
export const installWorklogSkill = async () => { await native.homeWrite(WORKLOG_SKILL, worklogSkillMarkdown(await native.dataDir())); };
export const installTodoSkill = async () => { await native.homeWrite(TODO_SKILL, todoSkillMarkdown(await native.exePath())); };
export const removeWorklogSkill = () => native.homeRemove(WORKLOG_SKILL);
export const removeTodoSkill = () => native.homeRemove(TODO_SKILL);

export function worklogSkillMarkdown(dataDir: string): string {
  const dir = dataDir.replace(/\\/g, "/");
  return `---
name: worklog
description: 현재 세션에서 한 일을 정리해 ATM 업무 일지에 기록한다. "/worklog", "오늘 한 거 기록해", "업무 일지 남겨", "worklog" 요청 시 사용.
---

현재 세션에서 지금까지 한 일을 정리해 아래 파일 끝에 append 한다.

파일: \`${dir}/worklog/YYYY-MM-DD.md\` (오늘 로컬 날짜. 디렉터리 없으면 만든다)

형식:

## HH:mm · <프로젝트명>
- 한 일 (성과/결과 위주) 3~7개, 각 1~2문장
- 미완료: (있을 때만, 한 줄)

규칙:
- 프로젝트명 = 현재 작업 디렉터리의 마지막 경로 요소.
- 파일이 없으면 첫 줄 \`# YYYY-MM-DD 업무 일지\` 후 빈 줄, 그 다음 섹션.
- 기존 내용은 수정하지 않는다. 끝에 append만. 파일은 UTF-8 로 쓴다.
- \`$ARGUMENTS\`가 있으면 그 범위나 관점을 반영한다 (예: "오전 작업만", "버그 수정 위주").
- 추측하지 않는다. 이 세션에서 실제로 한 일만 쓴다.
- 기록 후 추가한 섹션을 그대로 보여준다.
`;
}

export function todoSkillMarkdown(exe: string): string {
  const q = `"${exe.replace(/\\/g, "/").replace(/"/g, '\\"')}"`;
  return `---
name: atm-todo
description: ATM 위젯 할 일 목록에 할 일을 추가한다. '할 일에 추가해', 'ATM 에 넣어줘', 'todo 추가' 요청 시 사용.
---

ATM 위젯의 할 일 목록에 할 일을 추가한다. 아래 명령을 Bash 로 실행한다 (할 일 하나당 한 번).

\`\`\`
${q} --add-todo --title "<제목>" [--due YYYY-MM-DD] [--tag "<태그 이름>"]... [--memo "<메모>"] [--sub "<하위 할 일>"]...
\`\`\`

순서:
1. 사용자 요청에서 간결한 제목을 만든다 (한국어 가능, 한 줄).
2. 사용자가 날짜나 상대적인 날(내일, 금요일까지, 다음 주 월요일 등)을 말했을 때만 \`--due YYYY-MM-DD\` 를 붙인다. 기준 날짜는 \`date +%F\` 로 오늘을 확인해 계산한다.
3. 사용자가 태그 이름을 직접 말했을 때만 \`--tag\` 를 붙인다 (여러 개면 반복).
4. 제목에 못 담은 세부 내용이나 링크는 \`--memo\` 에 넣는다.
5. 하위 항목으로 나눠 달라고 하면 \`--sub\` 를 여러 번 붙인다 (한 줄씩, 지어내지 않는다).
6. 인자는 쉘에서 안전하게 따옴표로 감싼다 (작은따옴표 등 특수문자 주의).
7. 출력된 한 줄 JSON 결과를 사용자에게 알린다. \`"ok":false\` 면 \`error\` 를 그대로 전달한다.
8. \`unknownTags\` 가 비어 있지 않으면 그 태그는 ATM 에 없어서 붙지 않았다고 알린다.

규칙:
- 마감일과 태그를 지어내지 않는다. 말하지 않았으면 붙이지 않는다.
- 앱이 꺼져 있어도 다음 실행 때 반영된다.
`;
}

// ---- 실행 ----

export class ClaudeError extends Error {}

export async function locateClaude(configured: string): Promise<{ path: string; source: string } | null> {
  const r = await native.which("claude", configured).catch(() => null);
  return r ? { path: r[0], source: r[1] } : null;
}

/** 프롬프트를 stdin 으로 넘겨 결과 텍스트를 받는다. 실패는 사용자에게 보여줄 문장으로 던진다. */
export async function runClaude(prompt: string, o: { configured: string; model: string; cwd: string; timeoutMs?: number }): Promise<string> {
  const exe = await locateClaude(o.configured);
  if (!exe) throw new ClaudeError(CLAUDE_NOT_FOUND);
  const args = ["-p", "--output-format", "text", "--tools", "", "--strict-mcp-config", "--no-session-persistence"];
  if (o.model.trim()) args.push("--model", o.model.trim());
  const r = await native.run(exe.path, args, {
    stdin: prompt,
    cwd: o.cwd,
    envRemove: ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"],
    timeoutMs: o.timeoutMs ?? 180_000,
  });
  if (r.timedOut) throw new ClaudeError("Claude 응답이 너무 오래 걸려 멈췄어요 · 잠시 뒤 다시 생성");
  if (r.code !== 0) {
    const detail = (r.stderr.trim() ? r.stderr : r.stdout).slice(-2000);
    const hint = claudeHint(detail);
    const last = detail.trim().split("\n").pop() ?? "";
    throw new ClaudeError(hint ?? `claude 실패 (exit ${r.code}): ${last}`);
  }
  const out = r.stdout.trim();
  if (!out) throw new ClaudeError("claude 출력이 비어 있음");
  return out;
}
