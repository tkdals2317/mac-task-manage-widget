// 설정. Mac 판 UserDefaults 키 이름 그대로, 데이터 폴더의 settings.json 에 저장한다.
// 패널과 설정 창이 같은 값을 보도록 저장할 때 "settings-changed" 이벤트로 알린다.
import { emit, listen } from "@tauri-apps/api/event";
import { readJSON, writeJSON } from "./native";

export const DEFAULTS = {
  opacity: 1.0,
  hoverOpaque: true,
  theme: "system", // system | light | dark
  themePreset: "default",
  customBackground: "#2B2D31",
  customAccent: "#0A84FF",
  fontScale: 1.0,
  alwaysOnTop: true,
  launchAtLogin: true,
  globalHotKeyEnabled: true,
  // Tauri 단축키 문자열. Ctrl+Alt+Space 는 Claude 데스크톱 앱 빠른 입력과 겹쳐서 Ctrl+Alt+Q.
  globalHotKey: "Ctrl+Alt+Q",
  jiraBaseURL: "",
  jiraEmail: "",
  jiraRefreshMinutes: 5,
  jiraJQL: "",
  confluenceBaseURL: "",
  lastTab: "tasks",
  enabledTabs: "tasks,notes",
  todoSectionCollapsed: false,
  jiraSectionCollapsed: false,
  jiraVersionFilter: "",
  jiraGroupByVersion: false,
  sortTodosByTag: true,
  notesMemoCollapsed: false,
  notesLinkCollapsed: false,
  notesLinkFilter: "all",
  notesHello: false, // Mac 판 notesTouchID 자리 (Windows Hello)
  onboardingDone: false,
};

export type Settings = typeof DEFAULTS;
export type SettingsKey = keyof Settings;

const FILE = "settings.json";
const source = Math.random().toString(36).slice(2);

export const settings: Settings = $state({ ...DEFAULTS });
let loaded = false;
let saveTimer: ReturnType<typeof setTimeout> | undefined;

/** 앱 시작 때 한 번. 다른 창의 변경도 받아 온다. */
export async function loadSettings(): Promise<void> {
  const saved = await readJSON<Partial<Settings>>(FILE, {});
  apply(saved);
  loaded = true;
  await listen<{ source: string; values: Partial<Settings> }>("settings-changed", (e) => {
    if (e.payload.source !== source) apply(e.payload.values);
  });
}

function apply(values: Partial<Settings>): void {
  for (const k of Object.keys(DEFAULTS) as SettingsKey[]) {
    if (k in values && typeof values[k] === typeof DEFAULTS[k]) {
      (settings as Record<string, unknown>)[k] = values[k];
    }
  }
}

/** 값 바꾸고 저장 (0.3초 모아서 한 번). */
export function setSetting<K extends SettingsKey>(key: K, value: Settings[K]): void {
  settings[key] = value;
  if (!loaded) return;
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    const snapshot = { ...settings };
    // 기본값과 다른 것만 파일에 남긴다 (나중에 기본값을 바꾸면 안 건드린 사용자에게 적용되게)
    const changed = Object.fromEntries(
      Object.entries(snapshot).filter(([k, v]) => v !== DEFAULTS[k as SettingsKey]),
    );
    writeJSON(FILE, changed).catch(() => {});
    emit("settings-changed", { source, values: snapshot }).catch(() => {});
  }, 300);
}

/** 켜진 탭 id (Mac TabConfig.enabled 와 같은 규칙: all 순서, 모르는 id 무시, 비면 첫 탭). */
export function enabledTabs(raw: string, all: string[]): string[] {
  const wanted = new Set(raw.split(",").map((s) => s.trim()));
  const r = all.filter((id) => wanted.has(id));
  return r.length ? r : all.slice(0, 1);
}

/** 탭 토글. 마지막 하나는 끌 수 없다. */
export function toggledTabs(id: string, raw: string, all: string[]): string {
  const cur = enabledTabs(raw, all);
  if (!all.includes(id)) return raw;
  const next = new Set(cur);
  if (next.has(id)) {
    if (cur.length === 1) return raw;
    next.delete(id);
  } else next.add(id);
  return all.filter((x) => next.has(x)).join(",");
}
