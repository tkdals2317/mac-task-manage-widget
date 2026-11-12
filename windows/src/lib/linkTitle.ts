// 링크 주소 정규화와 페이지 제목 가져오기 (Mac LinkTitle).
import { requestText } from "./http";

/** "example.com/x" → https 주소. 스킴 없으면 https:// 를 붙이고, http/https 가 아니거나 호스트가 없으면 null. */
export function normalize(input: string): string | null {
  const t = input.trim();
  if (!t || /\s/.test(t)) return null;
  const s = t.includes("://") ? t : "https://" + t;
  let u: URL;
  try {
    u = new URL(s);
  } catch {
    return null;
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") return null;
  if (!(u.hostname.includes(".") || u.hostname === "localhost")) return null;
  return s;
}

/** `<title>` 내용. 대소문자 무시, HTML 엔티티 해독, 공백 정리. 없거나 비면 null. */
export function parse(html: string): string | null {
  const open = /<title[^>]*>/i.exec(html);
  if (!open) return null;
  const from = open.index + open[0].length;
  const close = html.slice(from).search(/<\/title>/i);
  if (close < 0) return null;
  const raw = decodeEntities(html.slice(from, from + close));
  const t = raw.split(/\s+/).filter(Boolean).join(" ");
  return t || null;
}

export function decodeEntities(s: string): string {
  let out = s;
  // &amp; 는 마지막에: 먼저 풀면 "&amp;lt;" 가 "<" 로 두 번 풀린다.
  for (const [k, v] of [["&lt;", "<"], ["&gt;", ">"], ["&quot;", '"'], ["&#39;", "'"], ["&apos;", "'"]]) out = out.split(k).join(v);
  out = out.replace(/&#(\d+);/g, (m, n: string) => {
    const code = Number(n);
    if (code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) return m;
    return String.fromCodePoint(code);
  });
  return out.split("&amp;").join("&");
}

/** 최대 512KB 까지만 읽고 제목을 뽑는다. 실패하면 null. */
export async function fetchTitle(url: string): Promise<string | null> {
  try {
    const r = await requestText(url, 5000);
    if (r.status < 200 || r.status > 299) return null;
    return parse(r.text.slice(0, 512 * 1024));
  } catch {
    return null;
  }
}
