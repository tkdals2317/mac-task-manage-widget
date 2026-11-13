// 테마. Mac 판 ThemePalette 와 같은 프리셋·색. 패널 루트에 CSS 변수로 입힌다.
import type { Settings } from "./settings.svelte";

export interface ThemeColors { background: string; accent: string }
export interface ThemePreset { id: string; name: string; colors: ThemeColors | null }

export const MIN_CONTRAST = 0.18;
export const CUSTOM_ID = "custom";

const p = (id: string, name: string, background: string, accent: string): ThemePreset => ({ id, name, colors: { background, accent } });

export const PRESETS: ThemePreset[] = [
  { id: "default", name: "기본", colors: null },
  p("midnight", "미드나잇", "#161B2E", "#7C9CFF"),
  p("ocean", "오션", "#0F2A3A", "#3CC8E0"),
  p("forest", "포레스트", "#16271F", "#4CC38A"),
  p("mocha", "모카", "#2E2620", "#E0A066"),
  p("rose", "로즈", "#33212A", "#F07BA6"),
  p("graphite", "그라파이트", "#1A1A1C", "#BFBFC4"),
  p("lavender", "라벤더", "#ECE8F7", "#7F5AD6"),
  p("peach", "피치", "#FBEDE6", "#E2683C"),
  p("mint", "민트", "#E6F4EE", "#1E9C74"),
  p("sky", "스카이", "#E7F0FA", "#2F7DD3"),
  p("sand", "샌드", "#F6F1EA", "#B5832F"),
  p("paper", "페이퍼", "#FFFFFF", "#0A84FF"),
];

export const LIGHT_BACKGROUNDS = ["#FFFFFF", "#F2F2F4", "#F6F1EA", "#EEF2F7", "#ECE8F7", "#E6F4EE", "#FBEDE6", "#FFF6D9", "#FCE9EF", "#E7F0FA"];
export const DARK_BACKGROUNDS = ["#2B2D31", "#1A1A1C", "#161B2E", "#0F2A3A", "#16271F", "#2E2620", "#2A1F33", "#33212A", "#2C2A1A", "#1E2B2B"];
export const ACCENTS = ["#0A84FF", "#7F77DD", "#D4537E", "#E8833A", "#1D9E75", "#14A3B8", "#C9A227", "#8E8E93"];

export function rgb(hex: string): { r: number; g: number; b: number } | null {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
  if (!m) return null;
  const n = parseInt(m[1], 16);
  return { r: ((n >> 16) & 255) / 255, g: ((n >> 8) & 255) / 255, b: (n & 255) / 255 };
}

/** 감각 밝기 0..1. 잘못된 hex 는 0. */
export function luminance(hex: string): number {
  const c = rgb(hex);
  return c ? 0.299 * c.r + 0.587 * c.g + 0.114 * c.b : 0;
}

export function resolveTheme(id: string, customBackground: string, customAccent: string): ThemeColors | null {
  if (id === CUSTOM_ID) return { background: customBackground, accent: customAccent };
  return PRESETS.find((x) => x.id === id)?.colors ?? null;
}

export const isDark = (c: ThemeColors) => luminance(c.background) < 0.5;
export const lowContrast = (c: ThemeColors) => Math.abs(luminance(c.background) - luminance(c.accent)) < MIN_CONTRAST;

function alpha(hex: string, a: number): string {
  const c = rgb(hex);
  if (!c) return hex;
  return `rgba(${Math.round(c.r * 255)}, ${Math.round(c.g * 255)}, ${Math.round(c.b * 255)}, ${a})`;
}

/** 설정 → 루트 CSS 변수. 기본 테마는 시스템(또는 고른) 밝기를 따른다. */
export function applyTheme(s: Settings, root: HTMLElement = document.documentElement): void {
  for (const [k, v] of Object.entries(themeVars(s))) root.style.setProperty(k, v);
  const dark = root.style.getPropertyValue("--dark") === "1";
  root.style.colorScheme = dark ? "dark" : "light";
  root.dataset.themed = resolveTheme(s.themePreset, s.customBackground, s.customAccent) ? "1" : "0";
  // 창이 투명이라 Mac 처럼 뒤가 비쳐 보인다 (NSPanel.alphaValue)
  root.style.opacity = String(s.opacity);
}

/** 테마 → CSS 변수. 기본 테마는 macOS 기본 창 색(밝은 회색 / 어두운 회색)과 시스템 파랑. */
export function themeVars(s: Pick<Settings, "theme" | "themePreset" | "customBackground" | "customAccent" | "fontScale">): Record<string, string> {
  const prefersDark = typeof window !== "undefined" && window.matchMedia?.("(prefers-color-scheme: dark)").matches;
  const c = resolveTheme(s.themePreset, s.customBackground, s.customAccent);
  const dark = c ? isDark(c) : s.theme === "dark" || (s.theme === "system" && !!prefersDark);
  const bg = c?.background ?? (dark ? "#2B2B2D" : "#EFEFF1");
  const accent = c?.accent ?? (dark ? "#0A84FF" : "#007AFF");
  const fg = dark ? "#F2F2F4" : "#1D1D1F";
  // 밝은 강조색(민트·샌드 등) 위 글자는 어둡게
  const onAccent = luminance(accent) > 0.72 ? "#1D1D1F" : "#FFFFFF";
  return {
    "--dark": dark ? "1" : "0",
    "--bg": bg,
    "--fg": fg,
    "--fg2": alpha(fg, dark ? 0.62 : 0.6),
    "--fg3": alpha(fg, dark ? 0.4 : 0.36),
    "--line": alpha(fg, dark ? 0.12 : 0.1),
    "--line2": alpha(fg, dark ? 0.18 : 0.16),
    "--fill": alpha(fg, dark ? 0.06 : 0.05),
    "--fill2": alpha(fg, dark ? 0.1 : 0.08),
    "--pop": c ? mix(bg, dark ? "#FFFFFF" : "#FFFFFF", dark ? 0.06 : 0.55) : dark ? "#333336" : "#F8F8FA",
    "--btn": dark ? alpha("#FFFFFF", 0.12) : "#FFFFFF",
    "--switch-off": dark ? alpha("#FFFFFF", 0.18) : alpha("#000000", 0.12),
    // 기본 테마: macOS segmented (흰 알약), 테마: 옅은 강조
    "--seg-on": c ? alpha(accent, dark ? 0.32 : 0.2) : dark ? alpha("#FFFFFF", 0.22) : "#FFFFFF",
    "--seg-on-text": c ? (dark ? "#FFFFFF" : accent) : fg,
    "--accent": accent,
    "--accent-text": dark && c ? mix(accent, "#FFFFFF", 0.2) : accent,
    "--accent-soft": alpha(accent, dark ? 0.26 : 0.16),
    "--accent-soft2": alpha(accent, dark ? 0.36 : 0.26),
    "--on-accent": onAccent,
    "--danger": dark ? "#FF6961" : "#E5342B",
    "--danger-soft": dark ? "rgba(255,105,97,0.2)" : "rgba(229,52,43,0.12)",
    "--warn": dark ? "#FFB340" : "#D9820B",
    "--warn-soft": dark ? "rgba(255,179,64,0.2)" : "rgba(255,149,0,0.14)",
    "--ok": dark ? "#32D74B" : "#1E9E3E",
    "--ok-soft": dark ? "rgba(50,215,75,0.18)" : "rgba(52,199,89,0.14)",
    "--info": dark ? "#64D2FF" : "#0A7AD6",
    "--info-soft": dark ? "rgba(100,210,255,0.18)" : "rgba(10,132,255,0.12)",
    "--scale": String(s.fontScale),
  };
}

/** 두 색을 t(0..1) 만큼 섞는다. */
function mix(a: string, b: string, t: number): string {
  const x = rgb(a), y = rgb(b);
  if (!x || !y) return a;
  const h = (v: number) => Math.round(v * 255).toString(16).padStart(2, "0");
  return "#" + h(x.r + (y.r - x.r) * t) + h(x.g + (y.g - x.g) * t) + h(x.b + (y.b - x.b) * t);
}
