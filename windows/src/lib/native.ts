// Rust 명령 얇은 래퍼. 파일 이름은 데이터 폴더(%APPDATA%\TaskWidget) 기준 상대 경로.
import { invoke } from "@tauri-apps/api/core";

export const native = {
  dataDir: () => invoke<string>("data_dir_path"),
  readText: (name: string) => invoke<string | null>("read_text", { name }),
  writeText: (name: string, content: string) => invoke<void>("write_text", { name, content }),
  moveAside: (name: string, to: string) => invoke<void>("move_aside", { name, to }),
  secretGet: (service: string, account: string) => invoke<string | null>("secret_get", { service, account }),
  secretSet: (service: string, account: string, value: string) =>
    invoke<void>("secret_set", { service, account, value }),
  secretDelete: (service: string, account: string) => invoke<void>("secret_delete", { service, account }),
  helloAvailable: () => invoke<boolean>("hello_available"),
  helloVerify: (reason: string) => invoke<boolean>("hello_verify", { reason }),
  openSettings: (pane?: string) => invoke<void>("open_settings", { pane: pane ?? null }),
  togglePanel: () => invoke<void>("toggle_panel"),
};

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
