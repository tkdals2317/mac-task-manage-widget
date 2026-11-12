// Teleport 탭 상태 (Mac TeleportManager). tsh 로그인(가상 콘솔에서 비밀번호·OTP 자동 입력), DB·앱 터널 띄우고 끄기, 자동 유지.
// 비밀번호·OTP 키는 비밀 저장소 한 항목(JSON)에. 터널 프로세스는 Rust 가 들고 있다가 ATM 이 꺼질 때 같이 끈다.
import { log, native, readJSON, writeJSON } from "./native";
import { settings, setSetting } from "./settings.svelte";
import {
  TELEPORT_ACCOUNT, TELEPORT_SERVICE, backoff, decideWatchdog, isAuthFailure, logoutArgs, namesToRestore, otpSecretOf,
  parseConfig, parseSessionExpiry, proxyArgs, serializeConfig, waitText, type TeleportConfig, type TeleportTunnel,
} from "./teleportCore";

export type TunnelState = { kind: "disconnected" } | { kind: "connecting" } | { kind: "connected" } | { kind: "failed"; message: string } | { kind: "portInUse" };
export interface TeleportSecrets { password: string; otpSecret: string }

const FILE = "teleport.json";
export const AUTH_FAILED_MESSAGE = "비밀번호나 OTP 키가 맞지 않아 자동 로그인을 멈췄어요. 설정 > Teleport > 설정 다시 하기에서 다시 입력해 주세요.";
const LOGIN_STUCK_MS = 90_000;

export const tp = $state({
  config: { proxy: "", user: "", tunnels: [] } as TeleportConfig,
  states: {} as Record<string, TunnelState>,
  validUntil: null as Date | null,
  busy: null as string | null,
  message: null as string | null,
  tshPath: null as string | null,
  hasSecrets: false,
  authFailed: false,
  setupRequested: false,
  lastLogin: null as Date | null,
  loaded: false,
});

export const stateOf = (t: TeleportTunnel): TunnelState => tp.states[t.name] ?? { kind: "disconnected" };
export const loggedIn = () => !!tp.validUntil && tp.validUntil.getTime() > Date.now();
export const isConfigured = () => !!tp.config.user && tp.config.tunnels.length > 0 && tp.hasSecrets;

let wanted = new Set<string>();
const failures: Record<string, number> = {};
const retryAt: Record<string, number> = {};
const intentional = new Set<string>();
let loginPromise: Promise<boolean> | null = null;
let loginStarted = 0;
let lastOTPCounter: number | null = null;
let touched = false;
let watchdogBusy = false;

function setState(n: string, s: TunnelState) {
  const old = tp.states[n];
  tp.states = { ...tp.states, [n]: s };
  if (JSON.stringify(old) !== JSON.stringify(s)) {
    if (s.kind === "failed") log(`teleport tunnel ${n} failed: ${s.message}`);
    if (s.kind === "portInUse") log(`teleport tunnel ${n} portInUse`);
  }
}

function saveWanted() { setSetting("teleportWanted", [...wanted].sort().join(",")); }

export async function loadSecrets(): Promise<TeleportSecrets | null> {
  const raw = await native.secretGet(TELEPORT_SERVICE, TELEPORT_ACCOUNT).catch(() => null);
  if (!raw) return null;
  try { const v = JSON.parse(raw); return typeof v.password === "string" && typeof v.otpSecret === "string" ? v : null; } catch { return null; }
}

export async function saveSecrets(s: TeleportSecrets): Promise<void> {
  await native.secretSet(TELEPORT_SERVICE, TELEPORT_ACCOUNT, JSON.stringify(s));
  tp.hasSecrets = true;
}

export async function locateTsh(): Promise<void> {
  tp.tshPath = (await native.which("tsh", settings.tshPath).catch(() => null))?.[0] ?? null;
}

export async function reloadConfig(): Promise<void> {
  tp.config = parseConfig(await readJSON<unknown>(FILE, {}));
  tp.hasSecrets = (await loadSecrets()) != null;
  for (const t of tp.config.tunnels) if (!tp.states[t.name]) setState(t.name, { kind: "disconnected" });
  tp.loaded = true;
}

export async function saveConfig(c: TeleportConfig): Promise<void> {
  await writeJSON(FILE, serializeConfig(c));
  tp.config = c;
  tp.authFailed = false;
  tp.setupRequested = false;
  for (const t of c.tunnels) if (!tp.states[t.name]) setState(t.name, { kind: "disconnected" });
  void refreshStatus();
}

export async function refreshStatus(): Promise<void> {
  if (!tp.tshPath) { tp.validUntil = null; return; }
  const r = await native.run(tp.tshPath, ["status", "--format=json"], { timeoutMs: 10_000 }).catch(() => null);
  tp.validUntil = r && r.code === 0 ? parseSessionExpiry(r.stdout) : null;
}

async function appendLoginLog(kind: string, res: { ok: boolean; message: string; transcript: string; exitCode: number; durationMs: number; timedOut: boolean }) {
  const ts = new Date().toISOString();
  const head = `=== ${ts} ${kind} user=${tp.config.user} proxy=${tp.config.proxy} tsh=${tp.tshPath} exit=${res.exitCode} ${res.durationMs}ms${res.timedOut ? " TIMEOUT" : ""} → ${res.ok ? "ok" : res.message}\n`;
  const old = (await native.readText("logs/teleport-login.log").catch(() => null)) ?? "";
  // 너무 길면 뒤 200KB 만
  const next = (old + head + res.transcript + "\n").slice(-200_000);
  await native.writeText("logs/teleport-login.log", next).catch(() => {});
}

/** 비밀번호·OTP 로 tsh login. 화면의 설정 확인(setup)은 다른 TELEPORT_HOME 으로 해서 지금 세션을 건드리지 않는다. */
export async function tshLogin(o: { proxy: string; user: string; secrets: TeleportSecrets; kind: string; teleportHome?: string }): Promise<{ ok: boolean; message: string }> {
  if (!tp.tshPath) return { ok: false, message: "tsh 가 설치되어 있지 않아요" };
  const otp = otpSecretOf(o.secrets.otpSecret);
  if (!otp) return { ok: false, message: "OTP 키를 읽지 못했어요" };
  const env: Record<string, string> = o.teleportHome ? { TELEPORT_HOME: o.teleportHome } : {};
  const run = () => native.tshLogin({
    program: tp.tshPath!, args: ["login", "--proxy", o.proxy, "--user", o.user], env,
    password: o.secrets.password, otpSecret: otp, minCounter: lastOTPCounter, timeoutSecs: 60,
  });
  let res = await run();
  if (res.otpCounter != null) lastOTPCounter = res.otpCounter;
  await appendLoginLog(o.kind, res);
  // 빈 인증서 파일 때문에 바로 죽으면 그 파일만 지우고 한 번 더
  if (!res.ok && res.message.includes("missing PEM encoded block")) {
    const removed = await native.tshRepairEmptyKeys().catch(() => []);
    if (removed.length) {
      log(`teleport: 빈 tsh 인증서 파일 정리 후 재시도: ${removed.join(", ")}`);
      res = await run();
      if (res.otpCounter != null) lastOTPCounter = res.otpCounter;
      await appendLoginLog(o.kind + "+repair", res);
    }
  }
  return { ok: res.ok, message: res.message };
}

async function performLogin(force: boolean, kind: string): Promise<boolean> {
  if (!tp.tshPath) { tp.message = "tsh 가 설치되어 있지 않아요"; return false; }
  if (tp.authFailed && kind !== "manual" && kind !== "setup") { tp.message = AUTH_FAILED_MESSAGE; return false; }
  if (!force) { await refreshStatus(); if (loggedIn()) return true; }
  const sec = await loadSecrets();
  if (!sec || !tp.config.user) { tp.message = "Teleport 설정이 필요해요"; return false; }
  tp.busy = "로그인 중…"; tp.message = null;
  loginStarted = Date.now();
  try {
    const r = await tshLogin({ proxy: tp.config.proxy, user: tp.config.user, secrets: sec, kind });
    if (r.ok) {
      touched = true;
      tp.authFailed = false;
      tp.lastLogin = new Date();
      await refreshStatus();
      return loggedIn();
    }
    if (isAuthFailure(r.message)) {
      tp.authFailed = true;
      tp.message = AUTH_FAILED_MESSAGE;
      log(`teleport: 인증 실패로 자동 로그인 중지 (${kind})`);
    } else tp.message = r.message;
    return false;
  } finally {
    tp.busy = null;
    loginStarted = 0;
  }
}

/** 이미 유효하면 아무것도 안 한다. 여러 DB 를 동시에 켜도 로그인은 한 번. */
export async function ensureLoggedIn(force = false, kind = "connect"): Promise<boolean> {
  if (loginPromise) return loginPromise;
  loginPromise = performLogin(force, kind);
  try { return await loginPromise; } finally { loginPromise = null; }
}

const portListening = (p: number) => native.portListening(p).catch(() => false);
const running = async (n: string) => (await native.tunnelExit(n).catch(() => -1)) === null;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** ATM 이 강제 종료돼 남은 같은 터널(tsh 가 그 포트를 듣는 중)은 정리한다. 다른 프로그램은 건드리지 않는다. */
async function reclaimLeftover(t: TeleportTunnel) {
  if (!(await portListening(t.port)) || (await running(t.name))) return;
  const owner = await native.portOwner(t.port).catch(() => null);
  if (!owner || !/^tsh(\.exe)?$/i.test(owner[1])) return;
  await native.killPid(owner[0]).catch(() => {});
  for (let i = 0; i < 20 && (await portListening(t.port)); i++) await sleep(100);
}

async function open(t: TeleportTunnel): Promise<void> {
  if (await running(t.name)) return;
  await reclaimLeftover(t);
  if (await portListening(t.port)) { setState(t.name, { kind: "portInUse" }); return; }
  setState(t.name, { kind: "connecting" });
  if (!(await ensureLoggedIn()) || !tp.tshPath) { setState(t.name, { kind: "failed", message: tp.message ?? "로그인 필요" }); return; }
  if (await running(t.name)) return;
  if (await portListening(t.port)) { setState(t.name, { kind: "portInUse" }); return; }
  try {
    await native.tunnelSpawn(t.name, tp.tshPath, proxyArgs(t), `logs/teleport-${t.name}.log`);
  } catch (e) {
    setState(t.name, { kind: "failed", message: `실행 실패: ${e}` }); return;
  }
  touched = true;
  for (let i = 0; i < 40; i++) {
    await sleep(250);
    const code = await native.tunnelExit(t.name).catch(() => -1);
    if (code !== null) { exited(t.name, code); return; }
    if (await portListening(t.port)) { setState(t.name, { kind: "connected" }); return; }
  }
  setState(t.name, { kind: "failed", message: "10초 안에 열리지 않았어요 (로그 확인)" });
  await stop(t.name);
}

function exited(n: string, code: number) {
  if (intentional.delete(n)) { setState(n, { kind: "disconnected" }); return; }
  setState(n, code === 0 ? { kind: "disconnected" } : { kind: "failed", message: `tsh 종료 (exit ${code}) · 로그 확인` });
}

async function stop(n: string) {
  intentional.add(n);
  await native.tunnelStop(n).catch(() => {});
  intentional.delete(n);
  setState(n, { kind: "disconnected" });
}

export async function connect(t: TeleportTunnel) {
  wanted.add(t.name); saveWanted();
  failures[t.name] = 0; delete retryAt[t.name];
  await open(t);
}

export async function disconnect(t: TeleportTunnel) {
  wanted.delete(t.name); saveWanted();
  await stop(t.name);
}

export async function connectAll() {
  if (!(await ensureLoggedIn())) return;
  await Promise.all(tp.config.tunnels.filter((t) => stateOf(t).kind !== "connected").map(connect));
}

/** 터널 종료 + 리소스별 logout + tsh logout. */
export async function disconnectAll() {
  wanted.clear(); saveWanted();
  for (const t of tp.config.tunnels) await stop(t.name);
  if (!tp.tshPath) return;
  tp.busy = "끊는 중…";
  await Promise.all(tp.config.tunnels.map((t) => native.run(tp.tshPath!, logoutArgs(t), { timeoutMs: 10_000 }).catch(() => null)));
  await native.run(tp.tshPath, ["logout"], { timeoutMs: 10_000 }).catch(() => null);
  tp.busy = null;
  tp.validUntil = null;
}

export async function relogin() {
  tp.authFailed = false;
  await ensureLoggedIn(true, "manual");
}

function fail(n: string) {
  failures[n] = (failures[n] ?? 0) + 1;
  const wait = backoff(failures[n], settings.teleportCheckSeconds);
  retryAt[n] = Date.now() + wait * 1000;
  log(`teleport watchdog: ${n} failure #${failures[n]}, next try in ${Math.round(wait)}s`);
}

/** 켜 둔 터널이 살아 있는지(프로세스 + 포트) 보고, 아니면 (필요하면 재로그인 후) 다시 띄운다. 포기 없이 간격만 늘린다. */
async function watchdog() {
  if (loginPromise && loginStarted && Date.now() - loginStarted > LOGIN_STUCK_MS) {
    log(`teleport watchdog: login stuck ${Math.round((Date.now() - loginStarted) / 1000)}s`);
    return;
  }
  if (!isConfigured() || !tp.tshPath || !wanted.size || watchdogBusy || loginPromise) return;
  watchdogBusy = true;
  try {
    const names = tp.config.tunnels.map((t) => t.name).filter((n) => wanted.has(n) && tp.states[n]?.kind !== "connecting");
    const run = new Set<string>(), healthy = new Set<string>();
    for (const n of names) {
      const code = await native.tunnelExit(n).catch(() => -1);
      if (code === null) run.add(n);
      else if (tp.states[n]?.kind === "connected") exited(n, code);
    }
    for (const t of tp.config.tunnels) if (run.has(t.name) && (await portListening(t.port))) healthy.add(t.name);
    for (const n of healthy) { failures[n] = 0; delete retryAt[n]; }
    const p = decideWatchdog(names, run, healthy, retryAt, loggedIn());
    for (const [n, left] of Object.entries(p.waiting)) setState(n, { kind: "failed", message: `재연결 대기 · ${waitText(left)}` });
    if (p.relogin) {
      log(`teleport watchdog: relogin (wanted=${p.restart.join(",")})`);
      if (!(await ensureLoggedIn(true, "watchdog"))) { p.restart.forEach(fail); return; }
    }
    for (const n of p.restart) {
      const t = tp.config.tunnels.find((x) => x.name === n);
      if (!wanted.has(n) || !t) continue;
      if (await running(n)) await stop(n);
      await open(t);
      if (tp.states[n]?.kind === "connected") { failures[n] = 0; delete retryAt[n]; } else fail(n);
    }
  } finally {
    watchdogBusy = false;
  }
}

/** 앱 시작 때 한 번 (패널 창). 설정 주기마다 상태·자동 유지, 마지막에 켜 둔 터널 복원. */
export function startTeleport(tabEnabled: () => boolean): () => void {
  let timer: ReturnType<typeof setInterval> | undefined;
  let secs = 0;
  let lastTick = Date.now();
  const arm = () => {
    clearInterval(timer);
    secs = settings.teleportCheckSeconds;
    timer = setInterval(async () => {
      // 잠자기에서 깨면(틱 간격이 크게 벌어짐) 백오프를 건너뛰고 바로 확인
      if (Date.now() - lastTick > secs * 3000 && wanted.size) { for (const k of Object.keys(retryAt)) delete retryAt[k]; log("teleport wake: check now"); }
      lastTick = Date.now();
      if (secs !== settings.teleportCheckSeconds) arm();
      if (!tp.tshPath || !tp.config.user) return;
      await refreshStatus();
      await watchdog();
    }, secs * 1000);
  };
  (async () => {
    await locateTsh();
    await reloadConfig();
    await refreshStatus();
    arm();
    const saved = settings.teleportWanted.split(",").filter(Boolean);
    if (tabEnabled() && isConfigured() && tp.tshPath) {
      const names = namesToRestore(saved, tp.config.tunnels.map((t) => t.name), settings.teleportAutoConnect);
      await Promise.all(tp.config.tunnels.filter((t) => names.includes(t.name)).map(connect));
    }
  })();
  return () => clearInterval(timer);
}

export const wasTouched = () => touched;
export const tunnelLog = (t: TeleportTunnel) => (tp.states[t.name]?.kind === "failed" && tp.message ? "logs/teleport-login.log" : `logs/teleport-${t.name}.log`);
