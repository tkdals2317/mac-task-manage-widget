<script lang="ts">
  // 설정 창 (Mac SettingsView): 왼쪽 목록(아이콘 + 강조색 선택) + 오른쪽 내용. "settings-pane" 이벤트로 이동.
  import { onMount } from "svelte";
  import { listen } from "@tauri-apps/api/event";
  import { native } from "../lib/native";
  import { JIRA_KEYCHAIN_SERVICE } from "../lib/jira";
  import { settings } from "../lib/settings.svelte";
  import { startNotes } from "../lib/notes.svelte";
  import Sym, { type SymName } from "../lib/Sym.svelte";
  import "./settings.css";
  import WindowPane from "./WindowPane.svelte";
  import AppearancePane from "./AppearancePane.svelte";
  import JiraPane from "./JiraPane.svelte";
  import TagsPane from "./TagsPane.svelte";
  import NotesPane from "./NotesPane.svelte";
  import PRPane from "./PRPane.svelte";
  import SummaryPane from "./SummaryPane.svelte";
  import ClaudePane from "./ClaudePane.svelte";
  import TeleportPane from "./TeleportPane.svelte";
  import AboutPane from "./AboutPane.svelte";
  import OnboardingPane from "./OnboardingPane.svelte";

  const PANES: { id: string; title: string; icon: SymName }[] = [
    { id: "appearance", title: "외관", icon: "palette" },
    { id: "window", title: "창 · 일반", icon: "window" },
    { id: "tags", title: "태그", icon: "tag" },
    { id: "jira", title: "Jira", icon: "jira" },
    { id: "notes", title: "노트", icon: "notes" },
    { id: "pr", title: "PR", icon: "branch" },
    { id: "summary", title: "요약", icon: "doc" },
    { id: "claude", title: "Claude 연동", icon: "sparkles" },
    { id: "teleport", title: "Teleport", icon: "globe" },
    { id: "about", title: "정보", icon: "info" },
  ];
  // 예전 id (설정 > 탭) 은 창·일반으로
  const alias: Record<string, string> = { tabs: "window" };
  const known = (s: string) => s === "onboarding" || PANES.some((p) => p.id === s);

  let pane = $state("window");
  let hasToken = $state(false);

  const go = (id: string) => { const p = alias[id] ?? id; if (known(p)) pane = p; };
  const fromHash = () => go((window as unknown as { __ATM_PANE?: string | null }).__ATM_PANE ?? location.hash.slice(1));

  async function refreshToken() {
    const email = settings.jiraEmail.trim();
    hasToken = email ? (await native.secretGet(JIRA_KEYCHAIN_SERVICE, email).catch(() => null)) != null : false;
  }

  onMount(() => {
    fromHash();
    void startNotes();
    void refreshToken();
    window.addEventListener("hashchange", fromHash);
    const un = listen<string>("settings-pane", (e) => go(e.payload));
    return () => { window.removeEventListener("hashchange", fromHash); un.then((f) => f()); };
  });
</script>

<div class="shell">
  <nav class="side" aria-label="설정 목록">
    {#each PANES as p (p.id)}
      <button class="nav" class:on={pane === p.id} aria-current={pane === p.id ? "page" : undefined} onclick={() => (pane = p.id)}>
        <span class="ico"><Sym name={p.icon} size={1.15} weight={1.4} /></span>
        <span>{p.title}</span>
        {#if p.id === "jira"}<span class="dot" class:ok={hasToken} title={hasToken ? "토큰 저장됨" : "토큰 없음"}></span>{/if}
      </button>
    {/each}
  </nav>
  <main class="content">
    <header class="ptitle">{pane === "onboarding" ? "설정 도우미" : PANES.find((p) => p.id === pane)?.title}</header>
    <div class="pscroll scroll">
      {#if pane === "window"}<WindowPane />
      {:else if pane === "appearance"}<AppearancePane />
      {:else if pane === "jira"}<JiraPane bind:hasToken />
      {:else if pane === "tags"}<TagsPane />
      {:else if pane === "notes"}<NotesPane />
      {:else if pane === "pr"}<PRPane />
      {:else if pane === "summary"}<SummaryPane />
      {:else if pane === "claude"}<ClaudePane />
      {:else if pane === "teleport"}<TeleportPane />
      {:else if pane === "onboarding"}<OnboardingPane ondone={() => (pane = "window")} />
      {:else}<AboutPane onopenwizard={() => (pane = "onboarding")} />{/if}
    </div>
  </main>
</div>
