// Mac truncationHelp: 한 줄이 "…" 로 잘렸을 때만 전체 문자열을 툴팁으로, 아니면 hint 만.
export function truncTitle(node: HTMLElement, p: { full: string; hint?: string }) {
  let cur = p;
  const set = () => {
    const truncated = node.scrollWidth > node.clientWidth;
    const t = truncated ? (cur.hint ? `${cur.full}\n\n${cur.hint}` : cur.full) : (cur.hint ?? "");
    if (t) node.title = t; else node.removeAttribute("title");
  };
  node.addEventListener("mouseenter", set);
  return {
    update(next: { full: string; hint?: string }) { cur = next; },
    destroy() { node.removeEventListener("mouseenter", set); },
  };
}

/** 입력칸이 뜨면 바로 포커스 (+ 전체 선택). */
export function focusOnMount(node: HTMLInputElement | HTMLTextAreaElement, select = false) {
  node.focus();
  if (select) node.select();
}
