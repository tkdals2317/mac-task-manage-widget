// 직무별 기본값과 JQL 매핑, 설정 도우미 단계 계산 (Mac RolePreset.swift 와 같은 규칙).
import { DEFAULT_JQL, REPORTER_JQL } from "./jira";

export type UserRole = "developer" | "planner" | "custom";
export type JiraScope = "assignee" | "reporter" | "both" | "keep";
export type E2EScope = "assignee" | "reporter";
export type SetupStep = "role" | "jira" | "notes" | "summary" | "pr" | "e2e" | "teleport" | "finish";

export interface RolePlan { tabs: string[]; jira: JiraScope; e2eScope: E2EScope }

export const ROLES: { id: UserRole; title: string; short: string; desc: string }[] = [
  { id: "developer", title: "개발자", short: "개발자", desc: "내 이슈 처리 · PR 리뷰 · DB 접속" },
  { id: "planner", title: "기획자", short: "기획자", desc: "내가 올린 이슈 추적 · 동작 검증 · 문서" },
  { id: "custom", title: "직접 고를게요", short: "직접", desc: "아무것도 미리 정하지 않고 하나씩 골라요" },
];

/** 앱 탭 순서 (settings.svelte.ts 의 ALL_TABS 와 같다). */
export const TAB_ORDER = ["tasks", "summary", "notes", "pr", "e2e", "teleport"];

export const BOTH_JQL = "(assignee = currentUser() OR reporter = currentUser()) AND statusCategory != Done ORDER BY updated DESC";

export function preset(role: UserRole): RolePlan {
  switch (role) {
    case "developer": return { tabs: ["tasks", "summary", "notes", "pr", "teleport"], jira: "assignee", e2eScope: "assignee" };
    case "planner": return { tabs: ["tasks", "notes", "e2e"], jira: "reporter", e2eScope: "reporter" };
    default: return { tabs: [], jira: "assignee", e2eScope: "assignee" };
  }
}

/** 범위 → 저장할 JQL (담당 = 빈 값 = 기본). keep 은 null (건드리지 않음). */
export function jqlFor(scope: JiraScope): string | null {
  switch (scope) {
    case "assignee": return "";
    case "reporter": return REPORTER_JQL;
    case "both": return BOTH_JQL;
    default: return null;
  }
}

/** 저장된 JQL → 범위. 아무것도 아니면(직접 쓴 JQL) keep. */
export function scopeForJQL(raw: string): JiraScope {
  const t = raw.trim();
  if (!t || t === DEFAULT_JQL) return "assignee";
  if (t === REPORTER_JQL) return "reporter";
  if (t === BOTH_JQL) return "both";
  return "keep";
}

/** 탭 → enabledTabs 저장 문자열 (앱 탭 순서, 모르는 id 무시). */
export const tabsString = (tabs: Iterable<string>): string => {
  const s = new Set(tabs);
  return TAB_ORDER.filter((t) => s.has(t)).join(",");
};

export const isValid = (tabs: Iterable<string>): boolean => tabsString(tabs) !== "";

/** Atlassian(Jira·Confluence) 계정이 필요한지: 할 일 · E2E · 노트. */
export const needsAtlassian = (tabs: Set<string>): boolean => tabs.has("tasks") || tabs.has("e2e") || tabs.has("notes");

export const STEP_TITLE: Record<SetupStep, string> = {
  role: "직무", jira: "Atlassian", notes: "노트", summary: "요약", pr: "PR", e2e: "E2E", teleport: "Teleport", finish: "마무리",
};

/** 선택한 탭에 해당하는 단계 (role 로 시작, finish 로 끝). */
export function steps(tabs: Set<string>): SetupStep[] {
  const s: SetupStep[] = ["role"];
  if (needsAtlassian(tabs)) s.push("jira");
  if (tabs.has("notes")) s.push("notes");
  if (tabs.has("summary")) s.push("summary");
  if (tabs.has("pr")) s.push("pr");
  if (tabs.has("e2e")) s.push("e2e");
  if (tabs.has("teleport")) s.push("teleport");
  s.push("finish");
  return s;
}

/** "다음: Atlassian → 노트 → … → 마무리". 4개를 넘으면 가운데를 줄인다. */
export function previewLine(list: SetupStep[]): string {
  const rest = list.slice(1).map((s) => STEP_TITLE[s]);
  const shown = rest.length > 4 ? [...rest.slice(0, 2), "…", rest[rest.length - 1]] : rest;
  return "다음: " + shown.join(" → ");
}
