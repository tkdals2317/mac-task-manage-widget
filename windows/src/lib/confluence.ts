// Confluence 별표 문서 (Mac ConfluenceClient). Jira 와 같은 이메일+API 토큰을 쓴다.
import { basicAuth, HttpError, requestJSON } from "./http";

export interface StarredPage {
  id: string;
  title: string;
  spaceKey: string;
  url: string;
  updated: Date | null;
}

export class ConfluenceError extends Error {
  constructor(public kind: "unauthorized" | "http" | "network" | "decode", public detail = "") {
    super(kind);
  }
  get userMessage(): string {
    switch (this.kind) {
      case "unauthorized": return "토큰 확인 필요 (401/403)";
      case "http": return `HTTP ${this.detail}`;
      case "network": return `네트워크: ${this.detail}`;
      default: return "응답을 읽지 못함";
    }
  }
}

export const UNAUTHORIZED_MESSAGE = new ConfluenceError("unauthorized").userMessage;
export const cql = "favourite = currentUser() order by lastmodified desc";

/** 내가 별표한 문서. */
export async function fetchStarred(baseURL: string, email: string, token: string): Promise<StarredPage[]> {
  const q = `cql=${encodeURIComponent(cql)}&limit=50&expand=${encodeURIComponent("space,version")}`;
  const url = `${baseURL.replace(/\/+$/, "")}/wiki/rest/api/content/search?${q}`;
  let json: unknown;
  try {
    json = await requestJSON<unknown>(url, { headers: { Authorization: basicAuth(email, token) }, timeoutMs: 20000 });
  } catch (e) {
    if (e instanceof HttpError) {
      if (e.status === 401 || e.status === 403) throw new ConfluenceError("unauthorized");
      throw new ConfluenceError("http", String(e.status));
    }
    if (e instanceof SyntaxError) throw new ConfluenceError("decode");
    throw new ConfluenceError("network", e instanceof Error ? e.message : String(e));
  }
  return decode(json, baseURL);
}

interface Raw {
  results?: {
    id?: unknown; title?: unknown;
    space?: { key?: string } | null; version?: { when?: string } | null; _links?: { webui?: string } | null;
  }[];
  _links?: { base?: string } | null;
}

/** `_links.base`(응답 최상위, 보통 …/wiki) + 결과의 `_links.webui`. base 가 없으면 `{base}/wiki`. */
export function decode(json: unknown, base: string): StarredPage[] {
  const r = json as Raw | null;
  if (!r || !Array.isArray(r.results)) throw new ConfluenceError("decode");
  const root = r._links?.base ?? base.replace(/\/+$/, "") + "/wiki";
  const out: StarredPage[] = [];
  for (const it of r.results) {
    if (typeof it.id !== "string" || typeof it.title !== "string") throw new ConfluenceError("decode");
    const webui = it._links?.webui;
    if (!webui) continue;
    const url = root + webui;
    try {
      new URL(url);
    } catch {
      continue;
    }
    const when = it.version?.when ? new Date(it.version.when) : null;
    out.push({ id: it.id, title: it.title, spaceKey: it.space?.key ?? "", url, updated: when && !isNaN(+when) ? when : null });
  }
  return out;
}

/** Mac AppState.confluenceURL: https 이고 호스트에 점이 있어야 한다. */
export function validBaseURL(raw: string): string | null {
  const t = raw.trim();
  try {
    const u = new URL(t);
    return u.protocol === "https:" && u.hostname.includes(".") ? t : null;
  } catch {
    return null;
  }
}
