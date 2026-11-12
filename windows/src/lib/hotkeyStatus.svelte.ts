// 전역 단축키 등록 결과. 패널(main)이 등록하고, 실패하면 여기 남긴다.
// 설정 창은 다른 웹뷰라 localStorage(같은 출처 공유)와 storage 이벤트로 받는다.
const KEY = "atm.hotkeyError";

export const hotkeyStatus = $state({ error: readStored() });

function readStored(): string {
  try { return localStorage.getItem(KEY) ?? ""; } catch { return ""; }
}

export function setHotkeyError(msg: string): void {
  hotkeyStatus.error = msg;
  try { msg ? localStorage.setItem(KEY, msg) : localStorage.removeItem(KEY); } catch { /* 저장 못 해도 패널 표시는 됨 */ }
}

/** 설정 창에서: 다른 창의 변경을 받는다. */
export function watchHotkeyStatus(): () => void {
  const on = (e: StorageEvent) => { if (e.key === KEY) hotkeyStatus.error = e.newValue ?? ""; };
  window.addEventListener("storage", on);
  return () => window.removeEventListener("storage", on);
}
