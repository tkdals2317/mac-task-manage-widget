// 메모 잠금용 암호 (Mac NoteCrypto 와 같은 방식). 비밀번호·열쇠·잠긴 메모의 평문은 로그에 남기지 않는다.
// PBKDF2-HMAC-SHA256 32바이트 열쇠, AES-GCM 봉인 = base64(nonce12 + 암호문 + 태그16) (CryptoKit combined 와 같음).
export const defaultIterations = 200_000;
/** Windows Hello 로 열 때 열쇠 원본을 두는 비밀 저장소 항목 (Mac Touch ID 와 같은 이름). */
export const helloService = "com.lsm0506.TaskWidget.notes";
export const helloAccount = "key";
const maxIterations = 10_000_000;
const verifierText = "ATM-notes-v1";

export interface NoteLock {
  salt: string; // base64 16바이트
  iterations: number;
  verifier: string;
}

export class NoteCryptoError extends Error {
  constructor(public code: "wrongPassword" | "corrupt") {
    super(code);
  }
}

const enc = new TextEncoder();
const dec = new TextDecoder("utf-8", { fatal: true });

export function toB64(b: Uint8Array): string {
  let s = "";
  for (const x of b) s += String.fromCharCode(x);
  return btoa(s);
}

/** 잘못된 base64 면 null. */
export function fromB64(s: string): Uint8Array | null {
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(s) || s.length % 4 !== 0) return null;
  try {
    return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
}

const buf = (b: Uint8Array) => b as Uint8Array<ArrayBuffer>;

export async function deriveKey(password: string, salt: Uint8Array, iterations = defaultIterations): Promise<CryptoKey> {
  // 깨진 notes.json 의 반복 횟수나 빈 비밀번호로 죽지 않게 먼저 거른다.
  if (!password) throw new NoteCryptoError("wrongPassword");
  if (!Number.isInteger(iterations) || iterations < 1 || iterations > maxIterations) throw new NoteCryptoError("corrupt");
  const base = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt: buf(salt), iterations }, base, 256);
  return keyFromRaw(new Uint8Array(bits));
}

export function keyFromRaw(raw: Uint8Array): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", buf(raw), "AES-GCM", true, ["encrypt", "decrypt"]);
}

export async function rawKey(key: CryptoKey): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.exportKey("raw", key));
}

export async function makeLock(password: string, iterations = defaultIterations): Promise<{ lock: NoteLock; key: CryptoKey }> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const key = await deriveKey(password, salt, iterations);
  return { lock: { salt: toB64(salt), iterations, verifier: await seal(verifierText, key) }, key };
}

export async function unlock(password: string, lock: NoteLock): Promise<CryptoKey> {
  const salt = fromB64(lock.salt);
  if (!salt) throw new NoteCryptoError("corrupt");
  const key = await deriveKey(password, salt, lock.iterations);
  if ((await open(lock.verifier, key).catch(() => null)) !== verifierText) throw new NoteCryptoError("wrongPassword");
  return key;
}

/** 열쇠가 이 잠금의 것인지 (Hello 저장소의 열쇠가 비밀번호 변경 뒤 낡았는지 확인용). */
export async function verify(key: CryptoKey, lock: NoteLock): Promise<boolean> {
  return (await open(lock.verifier, key).catch(() => null)) === verifierText;
}

export async function seal(text: string, key: CryptoKey): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, enc.encode(text)));
  const out = new Uint8Array(12 + ct.length);
  out.set(iv);
  out.set(ct, 12);
  return toB64(out);
}

export async function open(b64: string, key: CryptoKey): Promise<string> {
  const data = fromB64(b64);
  if (!data || data.length < 28) throw new NoteCryptoError("corrupt");
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: buf(data.slice(0, 12)) }, key, buf(data.slice(12)));
  try {
    return dec.decode(plain);
  } catch {
    throw new NoteCryptoError("corrupt");
  }
}
