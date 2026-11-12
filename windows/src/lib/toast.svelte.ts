// "복사됨" 같은 짧은 알림 (Mac CopyToast). 패널 아래쪽에 1.4초.
export const toast = $state({ text: "", id: 0 });

export function showToast(text: string): void {
  toast.text = text;
  const id = ++toast.id;
  setTimeout(() => {
    if (toast.id === id) toast.text = "";
  }, 1400);
}

export async function copyText(text: string, label = "복사됨"): Promise<void> {
  await navigator.clipboard.writeText(text);
  showToast(label);
}
