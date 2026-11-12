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
  const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const c = resolveTheme(s.themePreset, s.customBackground, s.customAccent);
  const dark = c ? isDark(c) : s.theme === "dark" || (s.theme === "system" && prefersDark);
  const bg = c?.background ?? (dark ? "#202020" : "#F3F3F3");
  const accent = c?.accent ?? (dark ? "#4CC2FF" : "#0067C0");
  const fg = dark ? "#F2F2F2" : "#1B1B1B";
  const vars: Record<string, string> = {
    "--bg": bg,
    "--fg": fg,
    "--fg2": alpha(fg, 0.62),
    "--fg3": alpha(fg, 0.42),
    "--line": alpha(fg, 0.1),
    "--fill": alpha(fg, 0.06),
    "--fill2": alpha(fg, 0.1),
    "--accent": accent,
    "--accent-soft": alpha(accent, dark ? 0.24 : 0.16),
    "--danger": dark ? "#FF6B6B" : "#C42B1C",
    "--danger-soft": dark ? "rgba(255,107,107,0.2)" : "rgba(196,43,28,0.12)",
    "--warn": dark ? "#FFC857" : "#9D5D00",
    "--warn-soft": dark ? "rgba(255,200,87,0.2)" : "rgba(157,93,0,0.12)",
    "--ok": dark ? "#6CCB5F" : "#0F7B0F",
    "--ok-soft": dark ? "rgba(108,203,95,0.2)" : "rgba(15,123,15,0.12)",
    "--info": dark ? "#99C2FF" : "#3A5FCD",
    "--info-soft": dark ? "rgba(153,194,255,0.2)" : "rgba(58,95,205,0.12)",
    "--scale": String(s.fontScale),
  };
  for (const [k, v] of Object.entries(vars)) root.style.setProperty(k, v);
  root.style.colorScheme = dark ? "dark" : "light";
  root.style.opacity = String(s.opacity);
}
