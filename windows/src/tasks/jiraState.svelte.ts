import { listen } from "@tauri-apps/api/event";
// Jira 상태 (Mac AppState 의 Jira 부분). 토큰은 자격 증명 관리자에서 읽는다 (service = Mac 키체인과 같은 문자열).
import { log, native } from "../lib/native";
import { settings } from "../lib/settings.svelte";
import {
  JIRA_KEYCHAIN_SERVICE, JiraError, REPORTER_JQL, doTransition, effectiveJQL, fetchMyOpenIssues, fetchTransitions, normalizeBase,
  sortedForDisplay, type JiraCreds, type JiraIssue, type JiraTransition,
} from "../lib/jira";

export const jira = $state({
  issues: [] as JiraIssue[],
  error: null as string | null,
  updatedAt: null as Date | null,
  loading: false,
  configured: false,
  truncated: false,
  busy: [] as string[], // 상태 변경 중인 이슈 키
});

/** E2E 탭 "보고" 목록 (내가 보고한 미완료 이슈). 할 일 탭 목록(jira)과 따로 가져온다. */
export const reporter = $state({
  issues: [] as JiraIssue[],
  error: null as string | null,
  updatedAt: null as Date | null,
  loading: false,
  truncated: false,
});

let cachedToken: { account: string; token: string } | null = null;

// 설정 창에서 토큰을 저장하면 캐시를 버리고 바로 다시 불러온다.
listen("jira-token-saved", () => {
  cachedToken = null;
  refreshJira().catch(() => {});
}).catch(() => {});

async function token(account: string): Promise<string | null> {
  if (cachedToken?.account === account) return cachedToken.token;
  const t = await native.secretGet(JIRA_KEYCHAIN_SERVICE, account).catch(() => null);
  if (t) cachedToken = { account, token: t };
  return t;
}

const msg = (e: unknown) => (e instanceof JiraError ? e.userMessage : e instanceof Error ? e.message : String(e));

export async function creds(): Promise<JiraCreds | null> {
  const email = settings.jiraEmail;
  const t = email ? await token(email) : null;
  const baseURL = normalizeBase(settings.jiraBaseURL);
  return t && baseURL ? { baseURL, email, token: t } : null;
}

export async function refreshJira(): Promise<void> {
  const email = settings.jiraEmail;
  const t = email ? await token(email) : null;
  jira.configured = t != null;
  if (!t) return;
  const baseURL = normalizeBase(settings.jiraBaseURL);
  if (!baseURL) { jira.error = "설정 > Jira 에서 Jira 주소를 입력하세요"; return; }
  if (jira.loading) return;
  jira.loading = true;
  try {
    const page = await fetchMyOpenIssues({ baseURL, email, token: t }, effectiveJQL(settings.jiraJQL));
    jira.issues = sortedForDisplay(page.issues);
    jira.truncated = page.truncated;
    jira.updatedAt = new Date();
    jira.error = null;
  } catch (e) {
    if (e instanceof JiraError && e.kind === "unauthorized") cachedToken = null;
    jira.error = msg(e);
    log(`jira refresh error: ${msg(e)}`);
  } finally {
    jira.loading = false;
  }
}

export async function refreshReporter(): Promise<void> {
  if (reporter.loading) return;
  const c = await creds();
  if (!c) { reporter.error = "설정 > Jira 에서 주소·이메일·토큰을 입력하세요"; return; }
  reporter.loading = true;
  try {
    const page = await fetchMyOpenIssues(c, REPORTER_JQL);
    reporter.issues = sortedForDisplay(page.issues);
    reporter.truncated = page.truncated;
    reporter.updatedAt = new Date();
    reporter.error = null;
  } catch (e) {
    if (e instanceof JiraError && e.kind === "unauthorized") cachedToken = null;
    reporter.error = msg(e);
    log(`jira reporter refresh error: ${msg(e)}`);
  } finally {
    reporter.loading = false;
  }
}

/** 가능한 전환 목록. 실패하면 메시지를 담은 JiraError (팝오버에서 인라인 표시). */
export async function loadTransitions(key: string): Promise<JiraTransition[]> {
  const c = await creds();
  if (!c) throw new JiraError("message", "Jira 설정 필요");
  try { return await fetchTransitions(c, key); } catch (e) { log(`jira transitions error ${key}: ${msg(e)}`); throw e; }
}

export async function transitionJira(key: string, t: JiraTransition): Promise<void> {
  const c = await creds();
  if (!c || jira.busy.includes(key)) return;
  jira.busy.push(key);
  try {
    await doTransition(c, key, t.id);
    log(`jira transition ${key} -> ${t.toName}`);
    jira.error = null;
  } catch (e) {
    jira.error = `${key}: ${msg(e)}`;
    log(`jira transition error ${key}: ${msg(e)}`);
    return;
  } finally {
    jira.busy = jira.busy.filter((k) => k !== key);
  }
  jira.loading = false; // 진행 중 갱신이 있어도 바뀐 상태를 바로 다시 읽는다
  await refreshJira();
}
