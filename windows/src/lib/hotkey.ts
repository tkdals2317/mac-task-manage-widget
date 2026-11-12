// 전역 단축키 녹화용: 키 이벤트 → Tauri 단축키 문자열("Ctrl+Alt+Space"), 화면 표시용 변환.
// Mac HotKeySpec 규칙: Ctrl·Alt·Win 중 하나는 필수 (Shift 만으로는 일반 타이핑과 충돌), Esc 불가.

export type Recorded = { accel: string } | { error: string } | { cancel: true } | null;

const NAMED: Record<string, string> = {
  Space: "Space", Enter: "Enter", NumpadEnter: "Enter", Tab: "Tab", Backspace: "Backspace",
  ArrowUp: "Up", ArrowDown: "Down", ArrowLeft: "Left", ArrowRight: "Right",
  Minus: "Minus", Equal: "Equal", BracketLeft: "BracketLeft", BracketRight: "BracketRight",
  Backslash: "Backslash", Semicolon: "Semicolon", Quote: "Quote", Comma: "Comma",
  Period: "Period", Slash: "Slash", Backquote: "Backquote",
};

/** KeyboardEvent.code → 단축키 키 이름. 지원하지 않는 키는 null. */
export function keyName(code: string): string | null {
  let m = /^Key([A-Z])$/.exec(code) ?? /^Digit([0-9])$/.exec(code);
  if (m) return m[1];
  m = /^F([1-9]|1[0-9]|2[0-4])$/.exec(code);
  if (m) return code;
  return NAMED[code] ?? null;
}

const MODIFIER_CODES = /^(Control|Alt|Shift|Meta|OS)(Left|Right)?$/;

/** 키를 눌렀을 때 결과. 수정 키만 눌린 상태면 null (계속 기다림). */
export function recordKey(e: Pick<KeyboardEvent, "code" | "ctrlKey" | "altKey" | "shiftKey" | "metaKey">): Recorded {
  if (e.code === "Escape") return { cancel: true };
  if (MODIFIER_CODES.test(e.code)) return null;
  if (!(e.ctrlKey || e.altKey || e.metaKey)) return { error: "Ctrl·Alt·Win 중 하나를 함께 눌러주세요" };
  const key = keyName(e.code);
  if (!key) return { error: "이 키는 쓸 수 없어요" };
  const parts = [e.ctrlKey && "Ctrl", e.altKey && "Alt", e.shiftKey && "Shift", e.metaKey && "Super"].filter(Boolean);
  return { accel: [...parts, key].join("+") };
}

const SHOWN: Record<string, string> = {
  Super: "Win", Meta: "Win", Cmd: "Win", Command: "Win", Control: "Ctrl", CommandOrControl: "Ctrl", CmdOrCtrl: "Ctrl",
  Up: "↑", Down: "↓", Left: "←", Right: "→",
  Minus: "-", Equal: "=", BracketLeft: "[", BracketRight: "]", Backslash: "\\", Semicolon: ";",
  Quote: "'", Comma: ",", Period: ".", Slash: "/", Backquote: "`",
};

/** "Ctrl+Alt+Space" → "Ctrl + Alt + Space" */
export const displayAccelerator = (accel: string): string =>
  accel.split("+").map((p) => SHOWN[p] ?? p).join(" + ");
