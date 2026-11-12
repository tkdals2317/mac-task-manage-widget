// 외부 HTTP 는 Rust 쪽 fetch(plugin-http)로 보낸다 (웹뷰 CORS 를 피함).
import { fetch as tauriFetch } from "@tauri-apps/plugin-http";

export class HttpError extends Error {
  constructor(public status: number, public body: string, message: string) {
    super(message);
  }
}

export function basicAuth(user: string, token: string): string {
  const bytes = new TextEncoder().encode(`${user}:${token}`);
  let bin = "";
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return `Basic ${btoa(bin)}`;
}

/** JSON 요청. 2xx 가 아니면 HttpError (본문 앞 300자, 토큰은 넣지 않음). */
export async function requestJSON<T>(
  url: string,
  init: { method?: string; headers?: Record<string, string>; body?: unknown; timeoutMs?: number } = {},
): Promise<T> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), init.timeoutMs ?? 20000);
  try {
    const res = await tauriFetch(url, {
      method: init.method ?? "GET",
      headers: { Accept: "application/json", ...(init.body ? { "Content-Type": "application/json" } : {}), ...init.headers },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
      signal: ctrl.signal,
    });
    const text = await res.text();
    if (!res.ok) throw new HttpError(res.status, text.slice(0, 300), `HTTP ${res.status}`);
    return (text ? JSON.parse(text) : null) as T;
  } finally {
    clearTimeout(timer);
  }
}

/** 문자열 그대로 (링크 제목 가져오기 등). */
export async function requestText(url: string, timeoutMs = 10000): Promise<{ status: number; text: string; contentType: string }> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await tauriFetch(url, { method: "GET", signal: ctrl.signal });
    return { status: res.status, text: await res.text(), contentType: res.headers.get("content-type") ?? "" };
  } finally {
    clearTimeout(timer);
  }
}
