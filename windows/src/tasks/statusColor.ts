/** 상태 종류(new / indeterminate / done)별 색. 상태 알약과 팝오버 점이 같은 색을 쓴다. */
export const statusColor = (category: string): string =>
  category === "indeterminate" ? "var(--accent)" : category === "done" ? "var(--ok)" : "var(--fg2)";
