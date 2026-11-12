import { describe, expect, it } from "vitest";
import { displayAccelerator, recordKey } from "./hotkey";

const ev = (code: string, m: Partial<{ ctrlKey: boolean; altKey: boolean; shiftKey: boolean; metaKey: boolean }> = {}) =>
  recordKey({ code, ctrlKey: false, altKey: false, shiftKey: false, metaKey: false, ...m });

describe("recordKey", () => {
  it("조합을 Tauri 문자열로", () => {
    expect(ev("Space", { ctrlKey: true, altKey: true })).toEqual({ accel: "Ctrl+Alt+Space" });
    expect(ev("KeyK", { metaKey: true, shiftKey: true })).toEqual({ accel: "Shift+Super+K" });
    expect(ev("F5", { altKey: true })).toEqual({ accel: "Alt+F5" });
    expect(ev("Digit1", { ctrlKey: true })).toEqual({ accel: "Ctrl+1" });
  });
  it("Esc 는 취소, 수정 키만이면 계속 기다림", () => {
    expect(ev("Escape", { ctrlKey: true })).toEqual({ cancel: true });
    expect(ev("ControlLeft", { ctrlKey: true })).toBeNull();
  });
  it("Ctrl·Alt·Win 없이는 거부", () => {
    expect(ev("KeyA", { shiftKey: true })).toHaveProperty("error");
    expect(ev("KeyA")).toHaveProperty("error");
  });
  it("지원 안 하는 키는 거부", () => {
    expect(ev("MediaPlayPause", { ctrlKey: true })).toHaveProperty("error");
  });
});

describe("displayAccelerator", () => {
  it("Windows 이름으로", () => {
    expect(displayAccelerator("Ctrl+Alt+Space")).toBe("Ctrl + Alt + Space");
    expect(displayAccelerator("Super+Up")).toBe("Win + ↑");
  });
});
