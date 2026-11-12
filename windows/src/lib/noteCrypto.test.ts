import { describe, expect, it } from "vitest";
import * as C from "./noteCrypto";

const hex = (b: Uint8Array) => [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
const IT = 1000;

describe("noteCrypto", () => {
  it("PBKDF2 알려진 값 (RFC 7914)", async () => {
    const k = await C.deriveKey("passwd", new TextEncoder().encode("salt"), 1);
    expect(hex(await C.rawKey(k))).toBe("55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc");
  });

  // Mac(CryptoKit/CommonCrypto)이 만든 값: salt=01..10, "pw1234한글", 1000회
  it("Mac 이 만든 열쇠·봉인을 그대로 연다", async () => {
    const salt = Uint8Array.from({ length: 16 }, (_, i) => i + 1);
    const key = await C.deriveKey("pw1234한글", salt, IT);
    expect(hex(await C.rawKey(key))).toBe("3e2670808ffa8cc54f21a532a20e3bd32493e682c955d44af20ce3c845efb539");
    expect(await C.open("5k7phsuqqiYawjIGFjkEZi8tCftYlrpi71IfVNhvCuy932lGM6PTjg==", key)).toBe("ATM-notes-v1");
    expect(await C.open("1LiuEkB3QmEjuHSn9z5GxNVgnqAhW8kUruRVtrXS5uPOPzwWZAKOkvDBXGMQvtUG", key)).toBe("비밀 메모\n둘째");
    const lock = { salt: C.toB64(salt), iterations: IT, verifier: "5k7phsuqqiYawjIGFjkEZi8tCftYlrpi71IfVNhvCuy932lGM6PTjg==" };
    expect(await C.verify(await C.unlock("pw1234한글", lock), lock)).toBe(true);
  });

  it("seal/open 왕복, 평문이 새지 않음", async () => {
    const { key } = await C.makeLock("pw1234", IT);
    const s = await C.seal("비밀 메모\n두 번째 줄", key);
    expect(s).not.toContain("비밀");
    expect(await C.open(s, key)).toBe("비밀 메모\n두 번째 줄");
  });

  it("다른 열쇠로는 못 연다", async () => {
    const a = (await C.makeLock("aaaa", IT)).key;
    const b = (await C.makeLock("bbbb", IT)).key;
    await expect(C.open(await C.seal("x", a), b)).rejects.toThrow();
  });

  it("makeLock → unlock, 틀린 비밀번호", async () => {
    const { lock, key } = await C.makeLock("pw1234", IT);
    const again = await C.unlock("pw1234", lock);
    expect(hex(await C.rawKey(key))).toBe(hex(await C.rawKey(again)));
    await expect(C.unlock("nope", lock)).rejects.toMatchObject({ code: "wrongPassword" });
  });

  it("raw 열쇠 왕복", async () => {
    const { key } = await C.makeLock("pw1234", IT);
    const raw = await C.rawKey(key);
    expect(hex(await C.rawKey(await C.keyFromRaw(raw)))).toBe(hex(raw));
  });

  it("빈 비밀번호·잘못된 반복 횟수·깨진 salt 는 거른다", async () => {
    const salt = new Uint8Array(16).fill(1);
    await expect(C.deriveKey("", salt, IT)).rejects.toMatchObject({ code: "wrongPassword" });
    for (const n of [0, -5, 10_000_001, Number.MAX_SAFE_INTEGER, 1.5]) {
      await expect(C.deriveKey("x", salt, n)).rejects.toMatchObject({ code: "corrupt" });
    }
    const { lock } = await C.makeLock("pw1234", IT);
    await expect(C.unlock("pw1234", { ...lock, iterations: 0 })).rejects.toMatchObject({ code: "corrupt" });
    await expect(C.unlock("pw1234", { ...lock, salt: "!!" })).rejects.toMatchObject({ code: "corrupt" });
    await expect(C.unlock("", lock)).rejects.toMatchObject({ code: "wrongPassword" });
  });
});
