// 오른쪽 클릭 메뉴 하나 (NotesTab 이 그린다).
export interface MenuItem { label?: string; onclick?: () => void; danger?: boolean; disabled?: boolean; sep?: boolean }
export const menu = $state({ open: false, x: 0, y: 0, items: [] as MenuItem[] });

export function openMenu(e: MouseEvent, items: MenuItem[]): void {
  e.preventDefault();
  e.stopPropagation();
  menu.items = items;
  menu.x = e.clientX;
  menu.y = e.clientY;
  menu.open = true;
}
export const closeMenu = () => { menu.open = false; };
