import { emit, listen } from "@tauri-apps/api/event";
// 노트 탭 상태 (Mac NotesModel). 잠긴 메모의 평문은 `ns.unlocked` 에만 있고 디스크에는 봉인본만 남는다.
// 열쇠는 이 모듈 변수에만 (메모리 전용). 비밀번호·열쇠·평문은 로그에 남기지 않는다.
import { log, native, readJSON, writeJSON } from "./native";
import { settings, setSetting } from "./settings.svelte";
import * as C from "./noteCrypto";
import { fetchTitle, normalize } from "./linkTitle";
import { ConfluenceError, fetchStarred, UNAUTHORIZED_MESSAGE, validBaseURL, type StarredPage } from "./confluence";
import { isLocked, newId, nowISO, normalizedTitle, orderMemos, parseNotes, preview as memoPreview, type Memo, type NotesData } from "../notes/data";

export class NotesError extends Error {}
const E = {
  tooShort: "비밀번호는 4자 이상이어야 해요",
  mismatch: "두 비밀번호가 달라요",
  wrongPassword: "비밀번호가 맞지 않아요",
  noLock: "잠금 비밀번호가 없어요",
};
/** Windows Hello 를 취소했거나 쓸 수 없어 비밀번호로 넘어가야 할 때 (오류 문구 없이). */
export class HelloFallback extends Error {}

const FILE = "notes.json";
/** 자동으로 다시 잠기기까지 (마지막 열기/편집 뒤) */
export const relockInterval = 5 * 60_000;
const JIRA_SERVICE = "com.lsm0506.TaskWidget.jira";

export const ns = $state({
  data: { memos: [], links: [] } as NotesData,
  loaded: false,
  /** 열어 둔 잠긴 메모의 평문 (메모리 전용). */
  unlocked: {} as Record<string, string>,
  expanded: {} as Record<string, boolean>,
  /** 방금 만든 메모처럼 본문 편집기에 포커스를 줄 메모. */
  focusMemo: null as string | null,
  hasKey: false,
  relockAt: null as number | null,
  now: Date.now(),
  starred: [] as StarredPage[],
  starredError: null as string | null,
  starredUpdatedAt: null as number | null,
  starredLoading: false,
});

let key: CryptoKey | null = null;
let dirty = false;
let saveTimer: ReturnType<typeof setTimeout> | undefined;
let started = false;
/** 패널·설정 창이 각자 이 스토어를 갖는다. 저장하면 notes-changed 로 알려 다른 창이 다시 읽게 한다. */
const source = Math.random().toString(36).slice(2);

// ---- 조회 ----
export const orderedMemos = () => orderMemos(ns.data.memos);
export const hasLock = () => !!ns.data.lock;
export const memoOf = (id: string) => ns.data.memos.find((m) => m.id === id);
export const isReadable = (m: Memo) => !isLocked(m) || ns.unlocked[m.id] !== undefined;
export const textOf = (m: Memo) => (isLocked(m) ? (ns.unlocked[m.id] ?? "") : m.body);
export const previewOf = (m: Memo) => memoPreview(m);

/** Hello 로 열 수 있는가: 설정이 켜져 있고 기기가 지원. */
export async function helloUsable(): Promise<boolean> {
  if (!settings.notesHello) return false;
  try { return await native.helloAvailable(); } catch { return false; }
}

// ---- 시작 / 저장 ----
/** 탭이 처음 보일 때 한 번: 불러오고, 자동 재잠금 감시를 건다. */
export async function startNotes(): Promise<void> {
  if (started) return;
  started = true;
  ns.data = parseNotes(await readJSON<unknown>(FILE, {}));
  ns.loaded = true;
  // 패널이 숨겨지면 즉시 다시 잠근다 (Mac: panelDidHide / 잠자기 / 화면 잠금).
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "hidden") relockAll(); });
  // 패널을 숨기면(✕·Esc·트레이·단축키) Rust/App 이 panel-hidden 을 보낸다. Mac 의 panelDidHide 와 같은 자리.
  listen("panel-hidden", () => relockAll()).catch(() => {});
  window.addEventListener("pagehide", () => flushPending());
  // 설정 창에서 비밀번호를 바꾸거나 Hello 를 켜면 디스크를 다시 읽는다. 열쇠가 바뀌었을 수 있어 먼저 다시 잠근다.
  listen<string>("notes-changed", async (e) => {
    if (e.payload === source) return;
    flushPending();
    relockAll();
    ns.data = parseNotes(await readJSON<unknown>(FILE, {}));
  }).catch(() => {});
  setInterval(() => {
    ns.now = Date.now();
    if (ns.relockAt !== null && ns.now >= ns.relockAt) relockAll();
  }, 15_000);
}

function persist(): void {
  clearTimeout(saveTimer);
  dirty = false;
  writeJSON(FILE, $state.snapshot(ns.data))
    .then(() => emit("notes-changed", source))
    .catch((e) => log(`notes save failed: ${e}`));
}

/** 글자를 칠 때마다 디스크에 쓰지 않고 잠깐 모아서 쓴다. 메모리는 즉시 최신. */
function persistSoon(): void {
  dirty = true;
  clearTimeout(saveTimer);
  saveTimer = setTimeout(flushPending, 500);
}

/** 아직 안 쓴 변경이 있으면 지금 쓴다 (재잠금·종료 직전). */
export function flushPending(): void { if (dirty) persist(); }

/** 열린 잠긴 메모가 있으면 자동 재잠금 시각을 뒤로 민다. */
function touch(): void {
  ns.hasKey = key !== null;
  ns.now = Date.now();
  ns.relockAt = key === null && Object.keys(ns.unlocked).length === 0 ? null : ns.now + relockInterval;
}

function update(id: string, change: (m: Memo) => void): void {
  const m = memoOf(id);
  if (!m) return;
  change(m);
  persist();
}

// ---- 메모 ----
export function addMemo(title: string): string | null {
  const t = normalizedTitle(title);
  if (!t) return null;
  const now = nowISO();
  const m: Memo = { id: newId(), title: t, body: "", pinned: false, createdAt: now, updatedAt: now };
  ns.data.memos.push(m);
  persist();
  ns.expanded[m.id] = true;
  ns.focusMemo = m.id;
  return m.id;
}

export function rename(id: string, title: string): void {
  const t = normalizedTitle(title);
  if (!t || memoOf(id)?.title === t) return;
  update(id, (m) => (m.title = t));
}

export const togglePin = (id: string) => update(id, (m) => (m.pinned = !m.pinned));

export function deleteMemo(id: string): void {
  ns.data.memos = ns.data.memos.filter((m) => m.id !== id);
  delete ns.unlocked[id];
  delete ns.expanded[id];
  persist();
  touch();
}

export function toggleExpanded(id: string): void {
  if (ns.expanded[id]) delete ns.expanded[id];
  else ns.expanded[id] = true;
}

/** 본문 저장. 잠긴 메모는 열려 있을 때만, 평문은 메모리에 두고 봉인본을 디스크에 쓴다. */
export async function setBody(id: string, text: string): Promise<void> {
  const m = memoOf(id);
  if (!m || text === textOf(m)) return;
  if (isLocked(m)) {
    if (ns.unlocked[id] === undefined || !key) return;
    const sealed = await C.seal(text, key).catch(() => null);
    if (!sealed || !key) return;
    ns.unlocked[id] = text;
    m.sealed = sealed;
    m.updatedAt = nowISO();
    touch();
  } else {
    m.body = text;
    m.updatedAt = nowISO();
  }
  persistSoon();
}

// ---- 잠금 ----
/** 처음 비밀번호를 만든다. 끝나면 열쇠가 메모리에 있다. */
export async function createPassword(pw: string, confirm: string): Promise<void> {
  if ([...pw].length < 4) throw new NotesError(E.tooShort);
  if (pw !== confirm) throw new NotesError(E.mismatch);
  const made = await C.makeLock(pw);
  ns.data.lock = made.lock;
  key = made.key;
  persist();
  touch();
}

async function derive(pw: string): Promise<CryptoKey> {
  const lock = ns.data.lock;
  if (!lock) throw new NotesError(E.noLock);
  if (!pw) throw new NotesError(E.wrongPassword);
  try {
    return await C.unlock(pw, $state.snapshot(lock));
  } catch (e) {
    if (e instanceof C.NoteCryptoError && e.code === "wrongPassword") throw new NotesError(E.wrongPassword);
    throw new NotesError("잠금 정보가 손상됐어요");
  }
}

/** 열쇠가 있어야 한다 (없으면 verify/Hello 를 먼저). */
export async function lockMemo(id: string): Promise<void> {
  const m = memoOf(id);
  if (!key || !m || isLocked(m)) return;
  const sealed = await C.seal(m.body, key).catch(() => null);
  if (!sealed) return;
  update(id, (x) => { x.sealed = sealed; x.body = ""; });
  delete ns.unlocked[id];
  touch();
}

export async function verify(password: string): Promise<void> {
  key = await derive(password);
  touch();
}

/** 열쇠가 이미 메모리에 있으면 바로 열고 true. */
export async function openIfKeyed(id: string): Promise<boolean> {
  const m = memoOf(id);
  if (!key || !m?.sealed) return false;
  const plain = await C.open(m.sealed, key).catch(() => null);
  if (plain === null) return false;
  ns.unlocked[id] = plain;
  touch();
  return true;
}

export async function unlockMemo(id: string, password: string): Promise<void> {
  await verify(password);
  if (!(await openIfKeyed(id))) throw new NotesError("메모를 열지 못했어요");
}

export async function unlockWithHello(id: string): Promise<void> {
  const lock = ns.data.lock;
  if (!lock) throw new NotesError(E.noLock);
  let ok: boolean;
  try { ok = await native.helloVerify("잠긴 메모 열기"); } catch (e) { throw new NotesError(`Windows Hello 실패: ${e}`); }
  if (!ok) throw new HelloFallback(); // 취소 → 비밀번호 팝오버
  const raw = await native.secretGet(C.helloService, C.helloAccount).catch(() => null);
  const bytes = raw ? C.fromB64(raw) : null;
  const k = bytes && bytes.length === 32 ? await C.keyFromRaw(bytes) : null;
  if (!k || !(await C.verify(k, $state.snapshot(lock)))) {
    // 저장된 열쇠가 낡았다 (비밀번호 변경 등). 지우고 비밀번호로 열게 한다.
    await disableHello();
    throw new NotesError("Windows Hello 열쇠가 낡았어요. 비밀번호로 여세요");
  }
  key = k;
  touch();
  if (!(await openIfKeyed(id))) throw new NotesError("메모를 열지 못했어요");
}

/** 지금 잠그기: 열쇠와 평문을 메모리에서 지운다. */
export function relockAll(): void {
  if (key === null && Object.keys(ns.unlocked).length === 0) return;
  flushPending();
  ns.unlocked = {};
  key = null;
  ns.hasKey = false;
  ns.relockAt = null;
}

/** 잠금 풀기(영구): 평문을 다시 본문에 쓰고 봉인을 없앤다. */
export function unlockPermanently(id: string): void {
  const m = memoOf(id);
  const plain = ns.unlocked[id];
  if (!m || !isLocked(m) || plain === undefined) return;
  update(id, (x) => { x.body = plain; x.sealed = undefined; });
  delete ns.unlocked[id];
  touch();
}

/** 설정 > 노트에서 쓴다 (설정 창은 다른 웹뷰라 패널의 메모리와 따로다: 호출 뒤 패널을 새로 읽어야 한다). */
export async function changePassword(oldPw: string, newPw: string, confirm: string): Promise<void> {
  if ([...newPw].length < 4) throw new NotesError(E.tooShort);
  if (newPw !== confirm) throw new NotesError(E.mismatch);
  const oldKey = await derive(oldPw);
  const sealedMemos = ns.data.memos.filter(isLocked).map((m) => ({ id: m.id, sealed: m.sealed ?? "" }));
  // 전부 새 열쇠로 다시 봉인하는 데 성공해야만 바꾼다 (중간 실패로 일부만 바뀌지 않게).
  const made = await C.makeLock(newPw);
  const resealed = new Map<string, string>();
  for (const m of sealedMemos) resealed.set(m.id, await C.seal(await C.open(m.sealed, oldKey), made.key));
  for (const m of ns.data.memos) { const s = resealed.get(m.id); if (s) m.sealed = s; }
  ns.data.lock = made.lock;
  if (key) { key = made.key; touch(); } // 열쇠가 없었으면 메모리에 올리지 않는다
  persist();
  if (settings.notesHello) {
    const ok = await native.secretSet(C.helloService, C.helloAccount, C.toB64(await C.rawKey(made.key))).then(() => true, () => false);
    if (!ok) await disableHello();
  }
}

/** 비밀번호 초기화: 잠긴 메모는 되살릴 수 없으므로 통째로 지운다. */
export async function resetPassword(): Promise<void> {
  const ids = new Set(ns.data.memos.filter(isLocked).map((m) => m.id));
  ns.data.memos = ns.data.memos.filter((m) => !ids.has(m.id));
  ns.data.lock = undefined;
  ns.unlocked = {};
  key = null;
  ns.hasKey = false;
  ns.relockAt = null;
  for (const id of ids) delete ns.expanded[id];
  persist();
  await disableHello();
}

// ---- Windows Hello ----
/** 켜려면 비밀번호를 한 번 확인한다. 열쇠 원본을 앱 비밀 저장소에 둔다. */
export async function enableHello(password: string): Promise<void> {
  const k = await derive(password);
  try { await native.secretSet(C.helloService, C.helloAccount, C.toB64(await C.rawKey(k))); }
  catch { throw new NotesError("열쇠를 저장하지 못했어요"); }
  setSetting("notesHello", true);
}

export async function disableHello(): Promise<void> {
  setSetting("notesHello", false);
  await native.secretDelete(C.helloService, C.helloAccount).catch(() => {});
}

// ---- 링크 ----
const hostOf = (u: string) => { try { return new URL(u).hostname; } catch { return ""; } };

/** 정규화해서 바로 넣고, 제목은 나중에 받아 온다. 주소로 볼 수 없으면 false. */
export function addLink(input: string): boolean {
  const url = normalize(input);
  if (!url) return false;
  const placeholder = hostOf(url) || url;
  const link = { id: newId(), title: placeholder, url, createdAt: nowISO() };
  ns.data.links.push(link);
  persist();
  void fillTitle(link.id, url, placeholder);
  return true;
}

/** 페이지 제목을 받아 이름이 아직 placeholder 면 바꾼다 (그 사이 사용자가 이름을 바꿨으면 건드리지 않는다). */
async function fillTitle(id: string, url: string, placeholder: string): Promise<void> {
  const title = await fetchTitle(url);
  const cur = ns.data.links.find((l) => l.id === id);
  if (title && cur && cur.title === placeholder) renameLink(id, title);
}

/** 수정: 이름과 주소를 함께 바꾼다. 이름을 비우면 새 주소의 페이지 제목을 받아 온다. */
export function updateLink(id: string, title: string, input: string): boolean {
  const url = normalize(input);
  const l = ns.data.links.find((x) => x.id === id);
  if (!url || !l) return false;
  l.url = url;
  const t = normalizedTitle(title);
  if (t) {
    l.title = t;
    persist();
  } else {
    const placeholder = hostOf(url) || url;
    l.title = placeholder;
    persist();
    void fillTitle(id, url, placeholder);
  }
  return true;
}

export function renameLink(id: string, title: string): void {
  const t = normalizedTitle(title);
  const l = ns.data.links.find((x) => x.id === id);
  if (!t || !l || l.title === t) return;
  l.title = t;
  persist();
}

export function deleteLink(id: string): void {
  ns.data.links = ns.data.links.filter((l) => l.id !== id);
  persist();
}

// ---- Confluence ----
let cachedToken: { account: string; token: string } | null = null;

/** Jira 와 같은 이메일·토큰을 쓴다. 주소가 비어 있으면 아무것도 하지 않는다. */
export async function refreshConfluence(): Promise<void> {
  if (ns.starredLoading || !settings.confluenceBaseURL.trim()) return;
  const base = validBaseURL(settings.confluenceBaseURL);
  if (!base) { ns.starredError = "Confluence 주소는 https:// 로 시작해야 해요"; return; }
  const email = settings.jiraEmail;
  let token = cachedToken?.account === email ? cachedToken.token : null;
  if (!token && email) {
    token = await native.secretGet(JIRA_SERVICE, email).catch(() => null);
    if (token) cachedToken = { account: email, token };
  }
  if (!email || !token) { ns.starredError = "Jira 토큰이 필요해요"; return; }
  ns.starredLoading = true;
  try {
    ns.starred = await fetchStarred(base, email, token);
    ns.starredError = null;
    ns.starredUpdatedAt = Date.now();
  } catch (e) {
    ns.starredError = e instanceof ConfluenceError ? e.userMessage : String(e);
    if (ns.starredError === UNAUTHORIZED_MESSAGE) cachedToken = null;
  } finally {
    ns.starredLoading = false;
  }
}
