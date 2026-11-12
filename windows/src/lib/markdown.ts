// 줄 단위 간이 Markdown (Mac MarkdownText). `# `, `## `, `- `/`* `(한 단계 들여쓰기) 만 블록, 나머지는 인라인 강조.
// 원문은 먼저 HTML 이스케이프하므로 그대로 {@html} 에 넣어도 안전하다.

const escapeHTML = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/** **굵게**, *기울임*, `코드`, [링크](http..) */
export function inline(text: string): string {
  let s = escapeHTML(text);
  const codes: string[] = [];
  s = s.replace(/`([^`]+)`/g, (_, c) => `\u0000${codes.push(c) - 1}\u0000`);
  s = s.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, (_, t, u) => `<a href="${u}" data-ext>${t}</a>`);
  s = s.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
  s = s.replace(/(^|[^*])\*([^*\s][^*]*)\*/g, "$1<i>$2</i>");
  return s.replace(/\u0000(\d+)\u0000/g, (_, i) => `<code>${codes[Number(i)]}</code>`);
}

export function renderMarkdown(md: string): string {
  return md
    .replace(/\r\n/g, "\n")
    .split("\n")
    .map((line) => {
      if (line.startsWith("# ")) return `<h1>${inline(line.slice(2))}</h1>`;
      if (line.startsWith("## ")) return `<h2>${inline(line.slice(3))}</h2>`;
      if (line.startsWith("### ")) return `<h3>${inline(line.slice(4))}</h3>`;
      if (/^ {2,}[-*] /.test(line)) return `<p class="li li2">${inline(line.replace(/^ +[-*] /, ""))}</p>`;
      if (/^[-*] /.test(line)) return `<p class="li">${inline(line.slice(2))}</p>`;
      if (!line.trim()) return `<div class="gap"></div>`;
      return `<p>${inline(line)}</p>`;
    })
    .join("");
}
