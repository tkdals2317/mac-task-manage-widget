import { openUrl } from "@tauri-apps/plugin-opener";
import { copyText } from "../lib/toast.svelte";
import { log } from "../lib/native";

/** http/https 만 연다. */
export function openLink(url: string): void {
  if (!/^https?:\/\//i.test(url)) return;
  openUrl(url).catch((e) => log(`openUrl failed: ${e}`));
}

export const copyLink = (url: string) => copyText(url, "링크를 복사했어요").catch(() => {});
