// 업데이트 확인: GitHub Releases 의 windows-v* 태그 중 최신과 설치된 버전을 비교한다.
// 설치는 사용자가 릴리스 페이지에서 받은 설치 파일로 한다 (1단계).
import { getVersion } from "@tauri-apps/api/app";
import { requestJSON } from "./http";

export const REPO = "tkdals2317/mac-task-manage-widget";

export interface UpdateInfo { current: string; latest: string; url: string; notes: string }

interface Release { tag_name: string; html_url: string; body: string | null; draft: boolean; prerelease: boolean }

/** "1.2.10" > "1.2.9". 숫자가 아닌 부분은 0. */
export function compareVersions(a: string, b: string): number {
  const pa = a.split(".").map((x) => parseInt(x, 10) || 0);
  const pb = b.split(".").map((x) => parseInt(x, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d) return Math.sign(d);
  }
  return 0;
}

/** 새 버전이 있으면 정보, 없으면 null. 네트워크 실패는 throw. */
export async function checkUpdate(): Promise<UpdateInfo | null> {
  const current = await getVersion();
  const releases = await requestJSON<Release[]>(`https://api.github.com/repos/${REPO}/releases?per_page=30`, {
    headers: { Accept: "application/vnd.github+json" },
  });
  const win = releases
    .filter((r) => !r.draft && !r.prerelease && r.tag_name.startsWith("windows-v"))
    .map((r) => ({ ...r, v: r.tag_name.slice("windows-v".length) }))
    .sort((x, y) => compareVersions(y.v, x.v))[0];
  if (!win || compareVersions(win.v, current) <= 0) return null;
  return { current, latest: win.v, url: win.html_url, notes: win.body ?? "" };
}
