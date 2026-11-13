// 할 일 저장소 (Mac AppState 의 todo 부분). todos.json 은 이 창이 유일한 쓰기 주체.
import { SvelteSet } from "svelte/reactivity";
import { invoke } from "@tauri-apps/api/core";
import { log, native, readJSON, writeJSON } from "./native";
import { defaultTagConfig, loadTagConfig, normalized, sortTodos, toggled, type TagConfig } from "./tags";
import {
  decodeTodos, newId, newTodo, normalizedTitle, toggleDone, todoFromInbox, type Subtask, type Todo,
} from "../tasks/model";

const FILE = "todos.json";
const INBOX = "inbox";

export const store = $state({ todos: [] as Todo[], tagConfig: defaultTagConfig() as TagConfig, loaded: false });
export const expanded = new SvelteSet<string>();

let saveChain: Promise<void> = Promise.resolve();
/** 저장은 순서대로 한 줄로 (연속 편집이 뒤섞여 옛 값이 덮어쓰지 않게). */
function persist(): void {
  // 불러오기 전에 저장하면 todos.json 을 빈 목록으로 덮어쓴다
  if (!store.loaded) { log("todos 저장 건너뜀: 아직 불러오기 전"); return; }
  const snapshot = $state.snapshot(store.todos);
  saveChain = saveChain.then(() => writeJSON(FILE, snapshot)).catch((e) => log(`todos 저장 실패: ${e}`));
}

export function openTodos(byTag: boolean): Todo[] {
  return sortTodos(store.todos.filter((t) => !t.done), store.tagConfig, byTag);
}
export const doneTodos = (): Todo[] =>
  store.todos.filter((t) => t.done).sort((a, b) => Date.parse(b.completedAt ?? "") - Date.parse(a.completedAt ?? "") || 0);

function update(id: string, change: (t: Todo) => void): void {
  const t = store.todos.find((x) => x.id === id);
  if (!t) return;
  change(t);
  persist();
}
const updateSub = (todoId: string, subId: string, change: (s: Subtask) => void) =>
  update(todoId, (t) => { const s = t.subtasks.find((x) => x.id === subId); if (s) change(s); });

export function addTodo(raw: string, memo = ""): void {
  const title = normalizedTitle(raw);
  if (!title) return;
  store.todos.push(newTodo(title, { memo }));
  persist();
}
export const toggle = (id: string) => update(id, (t) => toggleDone(t));
export const rename = (id: string, raw: string) => {
  const title = normalizedTitle(raw);
  if (title) update(id, (t) => { if (t.title !== title) t.title = title; });
};
export const setMemo = (id: string, memo: string) => {
  const t = store.todos.find((x) => x.id === id);
  if (t && t.memo !== memo) update(id, (x) => { x.memo = memo; });
};
export const setDue = (id: string, key: string | null) => update(id, (t) => { t.dueDate = key ?? undefined; });
export function remove(id: string): void {
  store.todos = store.todos.filter((t) => t.id !== id);
  expanded.delete(id);
  persist();
}
export function clearDone(): void {
  store.todos = store.todos.filter((t) => !t.done);
  persist();
}
export const toggleExpanded = (id: string) => { if (!expanded.delete(id)) expanded.add(id); };

export function addSubtask(todoId: string, raw: string): void {
  const title = normalizedTitle(raw);
  if (title) update(todoId, (t) => { t.subtasks.push({ id: newId(), title, done: false }); });
}
export const toggleSubtask = (todoId: string, subId: string) => updateSub(todoId, subId, (s) => { s.done = !s.done; });
export const setSubtaskDue = (todoId: string, subId: string, key: string | null) => updateSub(todoId, subId, (s) => { s.dueDate = key ?? undefined; });
export const renameSubtask = (todoId: string, subId: string, raw: string) => {
  const title = normalizedTitle(raw);
  if (title) updateSub(todoId, subId, (s) => { s.title = title; });
};
export const deleteSubtask = (todoId: string, subId: string) => update(todoId, (t) => { t.subtasks = t.subtasks.filter((s) => s.id !== subId); });
export const toggleTag = (todoId: string, tagId: string) => update(todoId, (t) => { t.tagIds = toggled(store.tagConfig, tagId, t.tagIds); });

// ---- 불러오기 / inbox ----
async function loadTodos(): Promise<Todo[]> {
  const raw = await readJSON<unknown>(FILE, []);
  const todos = decodeTodos(raw);
  if (todos) return todos;
  // Mac 과 같이: 읽을 수 없는 파일은 옆으로 치우고 빈 목록으로 시작
  const stamp = Math.floor(Date.now() / 1000);
  await native.moveAside(FILE, `todos.corrupt-${stamp}.json`).catch(() => {});
  log(`todos.json 해독 실패 → todos.corrupt-${stamp}.json 로 옮김`);
  return [];
}

/** inbox/*.json 을 읽어 할 일로 옮긴다. 저장까지 끝난 파일만 inbox/done/ 으로 치우고, 못 읽는 파일은 inbox/bad/ 로.
 *  폴더 목록은 Rust 쪽 `list_dir` 명령이 필요하다 (없으면 조용히 건너뜀). */
async function importInbox(): Promise<void> {
  let names: string[];
  try { names = await invoke<string[]>("list_dir", { name: INBOX }); } catch { return; }
  const files = names.filter((n) => n.toLowerCase().endsWith(".json")).sort();
  const good: { file: string; todo: Todo }[] = [];
  for (const file of files) {
    const text = await native.readText(`${INBOX}/${file}`).catch(() => null);
    const todo = text == null ? null : todoFromInbox(file, text, store.tagConfig);
    if (todo) good.push({ file, todo });
    else if (text != null) await native.moveAside(`${INBOX}/${file}`, `${INBOX}/bad/${file}`).catch(() => {});
  }
  if (!good.length) return;
  const known = new Set(store.todos.map((t) => t.id));
  store.todos.push(...good.map((g) => g.todo).filter((t) => !known.has(t.id)));
  persist();
  await saveChain;
  for (const g of good) await native.moveAside(`${INBOX}/${g.file}`, `${INBOX}/done/${g.file}`).catch(() => {});
}

async function reloadTags(): Promise<void> {
  const c = await loadTagConfig();
  if (JSON.stringify(c) === JSON.stringify(store.tagConfig)) return;
  store.tagConfig = c;
  // 지운 태그·하나만 그룹 위반 정리 (Mac pruneTodoTags / normalizeTodoTags)
  let changed = false;
  for (const t of store.todos) {
    const fixed = normalized(c, t.tagIds);
    if (fixed.join() !== t.tagIds.join()) { t.tagIds = fixed; changed = true; }
  }
  if (changed) persist();
}

/** 탭이 뜰 때 한 번. 5초마다 inbox 와 tags.json 을 다시 본다. 돌려주는 함수로 멈춘다. */
export function startTasks(): () => void {
  let stopped = false;
  const tick = () => { if (!stopped) { void importInbox(); void reloadTags(); } };
  (async () => {
    // inbox 의 id 와 겹치지 않게 불러오기를 먼저 끝낸다
    store.tagConfig = await loadTagConfig();
    store.todos = await loadTodos();
    store.loaded = true;
    tick();
  })();
  const timer = setInterval(tick, 5000);
  return () => { stopped = true; clearInterval(timer); };
}
