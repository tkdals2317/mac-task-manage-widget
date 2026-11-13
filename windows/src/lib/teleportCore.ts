// Teleport 설정·판단 (Mac TeleportConfig·TeleportTsh 파싱·TeleportWatchdogPolicy·TeleportAutoConnect·TOTP 입력 해석).

export type TunnelKind = "db" | "app";
export interface TeleportTunnel { name: string; dbUser: string; port: number; group?: string; kind: TunnelKind }
export interface TeleportConfig { proxy: string; user: string; tunnels: TeleportTunnel[] }
export interface TeleportDB { name: string; isProd: boolean }

export const BASE_PORT = 4306;
export const TELEPORT_SERVICE = "com.lsm0506.TaskWidget.teleport";
export const TELEPORT_ACCOUNT = "credentials";

/** 붙여넣을 때 섞이는 공백·줄바꿈·폭 없는 공백 제거. */
export const cleanID = (s: string) => s.replace(/[\s​-‏⁠﻿\p{Cc}\p{Cf}]/gu, "");

/* eslint-disable @typescript-eslint/no-explicit-any */
export function parseConfig(raw: unknown): TeleportConfig {
  const o = (raw && typeof raw === "object" ? raw : {}) as any;
  const tunnels: TeleportTunnel[] = Array.isArray(o.tunnels)
    ? o.tunnels
        .filter((t: any) => t && typeof t.name === "string" && Number.isInteger(t.port))
        .map((t: any) => ({
          name: t.name, port: t.port,
          dbUser: typeof t.dbUser === "string" ? t.dbUser : "developer",
          group: typeof t.group === "string" ? t.group : undefined,
          // 손으로 고친 오타·모르는 값은 db 로 읽는다
          kind: t.kind === "app" ? "app" : "db",
        }))
    : [];
  return { proxy: typeof o.proxy === "string" ? o.proxy : "", user: typeof o.user === "string" ? o.user : "", tunnels };
}

/** db 는 kind 를 적지 않고(예전 모양), app 은 dbUser 를 적지 않는다. */
export function serializeConfig(c: TeleportConfig): unknown {
  return {
    proxy: c.proxy, user: c.user,
    tunnels: c.tunnels.map((t) => {
      const o: Record<string, unknown> = { name: t.name, port: t.port };
      if (t.group?.trim()) o.group = t.group;
      if (t.kind === "app") o.kind = "app"; else o.dbUser = t.dbUser;
      return o;
    }),
  };
}

export const proxyArgs = (t: TeleportTunnel) =>
  t.kind === "app" ? ["proxy", "app", t.name, "--port", String(t.port)] : ["proxy", "db", "--tunnel", t.name, "--db-user", t.dbUser, "--port", String(t.port)];
export const logoutArgs = (t: TeleportTunnel) => (t.kind === "app" ? ["apps", "logout", t.name] : ["db", "logout", t.name]);
export const groupForName = (name: string) => (name.split("-")[0] || name).toUpperCase();
export const groupOf = (t: TeleportTunnel) => (t.group?.trim() ? t.group.trim() : groupForName(t.name));

export function nextFreePort(used: Set<number>, start = BASE_PORT): number {
  let p = start;
  while (used.has(p)) p++;
  return p;
}

export function duplicatePorts(tunnels: TeleportTunnel[]): Set<number> {
  const seen = new Set<number>(), dup = new Set<number>();
  for (const t of tunnels) (seen.has(t.port) ? dup : seen).add(t.port);
  return dup;
}

/** `tsh db ls --format=json` / `tsh apps ls --format=json`. 운영 = 이름에 prd/prod 또는 env 라벨. */
export function parseResources(json: string): TeleportDB[] {
  let arr: any;
  try { arr = JSON.parse(json); } catch { return []; }
  if (!Array.isArray(arr)) return [];
  const seen = new Set<string>(), out: TeleportDB[] = [];
  for (const item of arr) {
    const name = item?.metadata?.name;
    if (typeof name !== "string" || !name || seen.has(name)) continue;
    seen.add(name);
    const env = String(item?.metadata?.labels?.env ?? "").toLowerCase();
    const lower = name.toLowerCase();
    out.push({ name, isProd: lower.includes("prd") || lower.includes("prod") || ["prd", "prod", "production"].includes(env) });
  }
  return out.sort((a, b) => (a.name < b.name ? -1 : 1));
}

/** `tsh status --format=json` → 활성 프로필 만료 시각. */
export function parseSessionExpiry(json: string): Date | null {
  try {
    const s = JSON.parse(json)?.active?.valid_until;
    if (typeof s !== "string") return null;
    const d = new Date(s.replace(/\.(\d{3})\d+/, ".$1"));
    return isNaN(d.getTime()) ? null : d;
  } catch { return null; }
}
/* eslint-enable @typescript-eslint/no-explicit-any */

export function remainingText(until: Date, now = new Date()): string {
  const m = Math.floor((until.getTime() - now.getTime()) / 60000);
  if (m <= 0) return "만료됨";
  return m >= 60 ? `${Math.floor(m / 60)}시간 ${m % 60}분 남음` : `${m}분 남음`;
}

export function isAuthFailure(message: string): boolean {
  const m = message.toLowerCase();
  return m.includes("invalid credentials") || m.includes("invalid username, password or second factor") || m.includes("access denied");
}

// ---- OTP 입력 ----

const B32 = /^[A-Z2-7]+$/;
/** base32 키 또는 otpauth://totp/...?secret= → 정리된 base32. 못 읽으면 null. */
export function otpSecretOf(input: string): string | null {
  let raw = input.trim();
  if (raw.toLowerCase().startsWith("otpauth://")) {
    try {
      const u = new URL(raw);
      if (u.hostname.toLowerCase() !== "totp") return null;
      raw = [...u.searchParams.entries()].find(([k]) => k.toLowerCase() === "secret")?.[1] ?? "";
    } catch { return null; }
  }
  const s = raw.replace(/[\s=-]/g, "").toUpperCase();
  return s && B32.test(s) && s.length >= 8 ? s : null;
}

/** `otpauth://totp/Teleport:lsm0506@host?...` 의 계정 이름. */
export function otpAccountUser(input: string): string | null {
  const t = input.trim();
  if (!t.toLowerCase().startsWith("otpauth://")) return null;
  try {
    const u = new URL(t);
    let label = decodeURIComponent(u.pathname.replace(/^\/+/, ""));
    if (label.includes(":")) label = label.slice(label.indexOf(":") + 1);
    const user = label.split("@")[0].trim();
    return user || null;
  } catch { return null; }
}

// ---- 자동 유지 ----

export const MAX_BACKOFF = 300;
export const backoff = (failures: number, interval: number) => (failures <= 0 ? 0 : Math.min(interval * 2 ** (Math.min(failures, 20) - 1), MAX_BACKOFF));
export const waitText = (sec: number) => (sec < 60 ? `${Math.max(1, Math.ceil(sec))}초 후` : `${Math.ceil(sec / 60)}분 후`);

export interface WatchdogPlan { relogin: boolean; restart: string[]; waiting: Record<string, number> }
export function decideWatchdog(wanted: string[], running: Set<string>, healthy: Set<string>, retryAt: Record<string, number>, loggedIn: boolean, now = Date.now()): WatchdogPlan {
  const p: WatchdogPlan = { relogin: false, restart: [], waiting: {} };
  for (const n of wanted) {
    if (loggedIn && running.has(n) && healthy.has(n)) continue;
    const at = retryAt[n];
    if (at && at > now) { p.waiting[n] = (at - now) / 1000; continue; }
    p.restart.push(n);
  }
  p.relogin = !loggedIn && p.restart.length > 0;
  return p;
}

export const namesToRestore = (persisted: string[], configured: string[], enabled: boolean) =>
  enabled ? configured.filter((n) => persisted.includes(n)) : [];
