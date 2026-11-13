// Rust 명령 얇은 래퍼. 파일 이름은 데이터 폴더(%APPDATA%\TaskWidget) 기준 상대 경로.
import { invoke } from "@tauri-apps/api/core";

/** credman: Windows 자격 증명 관리자 (기본) | file: 데이터 폴더의 secrets.json (암호화 없음, 내 계정만 읽기). settings 가 정한다. */
let secretMode = "credman";
export function setSecretMode(m: string): void { secretMode = m === "file" ? "file" : "credman"; }
type SecretFile = Record<string, Record<string, string>>;
const SECRETS = "secrets.json";
async function fileSecrets(): Promise<SecretFile> {
  const raw = await invoke<string | null>("read_text", { name: SECRETS });
  try { return raw ? (JSON.parse(raw) as SecretFile) : {}; } catch { return {}; }
}
let secretChain: Promise<unknown> = Promise.resolve();
function editFileSecrets(f: (s: SecretFile) => void): Promise<void> {
  const run = secretChain.then(async () => {
    const s = await fileSecrets();
    f(s);
    await invoke("write_text", { name: SECRETS, content: JSON.stringify(s, null, 2) });
  });
  secretChain = run.catch(() => {});
  return run;
}

export const native = {
  dataDir: () => invoke<string>("data_dir_path"),
  readText: (name: string) => invoke<string | null>("read_text", { name }),
  writeText: (name: string, content: string) => invoke<void>("write_text", { name, content }),
  moveAside: (name: string, to: string) => invoke<void>("move_aside", { name, to }),
  // 비밀값: 설정 > 창 > 비밀 정보 저장 에 따라 자격 증명 관리자 또는 secrets.json (Mac SecretStore)
  secretGet: (service: string, account: string) =>
    secretMode === "file" ? fileSecrets().then((s) => s[service]?.[account] ?? null) : invoke<string | null>("secret_get", { service, account }),
  secretSet: (service: string, account: string, value: string) =>
    secretMode === "file"
      ? editFileSecrets((s) => { (s[service] ??= {})[account] = value; })
      : invoke<void>("secret_set", { service, account, value }),
  secretDelete: (service: string, account: string) =>
    secretMode === "file"
      ? editFileSecrets((s) => { if (s[service]) delete s[service][account]; })
      : invoke<void>("secret_delete", { service, account }),
  credmanGet: (service: string, account: string) => invoke<string | null>("secret_get", { service, account }),
  credmanSet: (service: string, account: string, value: string) => invoke<void>("secret_set", { service, account, value }),
  credmanDelete: (service: string, account: string) => invoke<void>("secret_delete", { service, account }),
  helloAvailable: () => invoke<boolean>("hello_available"),
  helloVerify: (reason: string) => invoke<boolean>("hello_verify", { reason }),
  openSettings: (pane?: string) => invoke<void>("open_settings", { pane: pane ?? null }),
  settingsReady: () => invoke<void>("settings_ready"),
  togglePanel: () => invoke<void>("toggle_panel"),
  minimizePanel: () => invoke<void>("minimize_panel"),
  setTrayTooltip: (text: string) => invoke<void>("set_tray_tooltip", { text }),
  quit: () => invoke<void>("quit_app"),
  // 외부 프로그램
  run: (program: string, args: string[], opts: RunOptions = {}) => invoke<ProcResult>("run_process", { program, args, opts }),
  which: (name: string, configured?: string) =>
    invoke<[string, string] | null>("which_program", { name, configured: configured ?? null }),
  portListening: (port: number) => invoke<boolean>("port_listening", { port }),
  portOwner: (port: number) => invoke<[number, string] | null>("port_owner", { port }),
  killPid: (pid: number) => invoke<void>("kill_pid", { pid }),
  tunnelSpawn: (key: string, program: string, args: string[], log: string) =>
    invoke<number>("tunnel_spawn", { key, program, args, log }),
  /** 돌고 있으면 null, 끝났으면 종료 코드 (모르는 이름은 -1). */
  tunnelExit: (key: string) => invoke<number | null>("tunnel_exit", { key }),
  tunnelStop: (key: string) => invoke<void>("tunnel_stop", { key }),
  tshLogin: (a: { program: string; args: string[]; env: Record<string, string>; password: string; otpSecret: string; minCounter: number | null; timeoutSecs: number }) =>
    invoke<LoginResult>("tsh_login", a),
  totpNow: (secret: string) => invoke<[string, number] | null>("totp_now", { secret }),
  tshRepairEmptyKeys: () => invoke<string[]>("tsh_repair_empty_keys"),
  // 홈 폴더 (~/.claude 등)
  homeDir: () => invoke<string>("home_dir_path"),
  homeRead: (rel: string) => invoke<string | null>("home_read", { rel }),
  homeWrite: (rel: string, content: string, backup = false) => invoke<string | null>("home_write", { rel, content, backup }),
  homeRemove: (rel: string) => invoke<void>("home_remove", { rel }),
  listSubdirs: (path: string) => invoke<string[]>("list_subdirs", { path }),
  pathExists: (path: string) => invoke<boolean>("path_exists", { path }),
  // 데이터 폴더
  fileMtime: (name: string) => invoke<number | null>("file_mtime", { name }),
  setFileMtime: (name: string, ms: number) => invoke<void>("set_file_mtime", { name, ms }),
  deleteFile: (name: string) => invoke<void>("delete_file", { name }),
  listDir: (name: string) => invoke<string[]>("list_dir", { name }),
  exePath: () => invoke<string>("exe_path"),
  openDataPath: (name: string, createFile = false) => invoke<void>("open_data_path", { name, createFile }),
  revealPath: (path: string) => invoke<void>("reveal_path", { path }),
  exportDiagnostics: (report: string) => invoke<string>("export_diagnostics", { report }),
};

export interface RunOptions {
  stdin?: string;
  cwd?: string;
  env?: Record<string, string>;
  envRemove?: string[];
  timeoutMs?: number;
}
export interface ProcResult { code: number; stdout: string; stderr: string; timedOut: boolean }
export interface LoginResult { ok: boolean; message: string; transcript: string; exitCode: number; timedOut: boolean; durationMs: number; otpCounter: number | null }

/** 탭이 다른 창(설정)에서 바뀌는 등 Tauri 밖(테스트)에서 부르면 실패하는 것을 감싼다. */
export const isTauri = () => typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

/** logs/app.log 에 한 줄. 비밀값·메모 본문은 넘기지 말 것. */
export function log(msg: string): void {
  const ts = new Date().toISOString().replace(/\.\d+Z$/, "Z");
  invoke("log_line", { line: `${ts} ${msg}` }).catch(() => {});
}

/** JSON 파일 읽기. 없으면 fallback, 깨졌으면 <base>.corrupt-<ts>.json 으로 치우고 fallback. */
export async function readJSON<T>(name: string, fallback: T): Promise<T> {
  const raw = await native.readText(name);
  if (raw == null) return fallback;
  try {
    return JSON.parse(raw) as T;
  } catch {
    const stamp = Math.floor(Date.now() / 1000);
    const base = name.replace(/\.json$/, "");
    await native.moveAside(name, `${base}.corrupt-${stamp}.json`).catch(() => {});
    log(`${name} 파싱 실패 → ${base}.corrupt-${stamp}.json 로 옮김`);
    return fallback;
  }
}

/** Mac 판과 같은 모양(2칸 들여쓰기, 키 정렬)으로 저장. */
export function writeJSON(name: string, value: unknown): Promise<void> {
  return native.writeText(name, JSON.stringify(sortKeys(value), null, 2));
}

function sortKeys(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(sortKeys);
  if (v && typeof v === "object") {
    const o = v as Record<string, unknown>;
    return Object.fromEntries(Object.keys(o).sort().filter((k) => o[k] !== undefined).map((k) => [k, sortKeys(o[k])]));
  }
  return v;
}
