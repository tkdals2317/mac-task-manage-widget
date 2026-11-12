// 설정 > Jira / 노트 의 "연결 확인". 문구는 Mac AppState.testJira / testConfluence 와 같다.
import { basicAuth, HttpError, requestJSON } from "../lib/http";
import { errorMessage, normalizeBase } from "../lib/jira";
import { ConfluenceError, fetchStarred, validBaseURL } from "../lib/confluence";

export const BAD_URL = "https:// 로 시작하는 주소를 입력하세요";

function failure(e: unknown): string {
  if (e instanceof HttpError) {
    if (e.status === 401 || e.status === 403) return "토큰 확인 필요 (401/403)";
    if (e.status === 400) return `JQL 오류: ${errorMessage(e.body)}`;
    return `HTTP ${e.status}`;
  }
  return `네트워크: ${e instanceof Error ? e.message : String(e)}`;
}

/** 성공하면 { ok: true, text: "OK: 이름" }. 실패 문구는 그대로 화면에 보여줘도 된다. */
export async function testJira(baseURL: string, email: string, token: string): Promise<{ ok: boolean; text: string }> {
  const base = normalizeBase(baseURL);
  if (!base) return { ok: false, text: BAD_URL };
  try {
    const me = await requestJSON<{ displayName: string }>(`${base}/rest/api/3/myself`, {
      headers: { Authorization: basicAuth(email, token) },
    });
    return { ok: true, text: `OK: ${me.displayName}` };
  } catch (e) {
    return { ok: false, text: failure(e) };
  }
}

export async function testConfluence(baseURL: string, email: string, token: string | null): Promise<{ ok: boolean; text: string }> {
  const base = validBaseURL(baseURL);
  if (!base) return { ok: false, text: BAD_URL };
  if (!email || !token) return { ok: false, text: "Jira 이메일·토큰을 먼저 저장하세요" };
  try {
    return { ok: true, text: `OK: ${(await fetchStarred(base, email, token)).length}개` };
  } catch (e) {
    return { ok: false, text: e instanceof ConfluenceError ? e.userMessage : e instanceof Error ? e.message : String(e) };
  }
}
