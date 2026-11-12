/** 노드 밖을 누르면 fn. */
export function clickOutside(node: HTMLElement, fn: () => void) {
  let cb = fn;
  const h = (e: PointerEvent) => { if (!node.contains(e.target as Node)) cb(); };
  document.addEventListener("pointerdown", h, true);
  return { update: (f: () => void) => (cb = f), destroy: () => document.removeEventListener("pointerdown", h, true) };
}
