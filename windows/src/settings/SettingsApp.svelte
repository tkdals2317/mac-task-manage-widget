<script lang="ts">
  // 설정 창 (Mac SettingsView). 왼쪽 창 목록 + 오른쪽 내용. `settings.html#jira` 로 열거나 "settings-pane" 이벤트로 이동.
  import { onMount } from "svelte";
  import { listen } from "@tauri-apps/api/event";
  import { native } from "../lib/native";
  import { JIRA_KEYCHAIN_SERVICE } from "../lib/jira";
  import { settings } from "../lib/settings.svelte";
  import { startNotes } from "../lib/notes.svelte";
  import "./settings.css";
  import WindowPane from "./WindowPane.svelte";
  import AppearancePane from "./AppearancePane.svelte";
  import TabsPane from "./TabsPane.svelte";
  import JiraPane from "./JiraPane.svelte";
  import TagsPane from "./TagsPane.svelte";
  import NotesPane from "./NotesPane.svelte";
  import AboutPane from "./AboutPane.svelte";

  const PANES = [
    { id: "window", title: "창", icon: "▢" },
    { id: "appearance", title: "모양", icon: "◐" },
    { id: "tabs", title: "탭", icon: "▤" },
    { id: "jira", title: "Jira", icon: "◈" },
    { id: "tags", title: "태그", icon: "#" },
    { id: "notes", title: "노트", icon: "✎" },
    { id: "about", title: "정보", icon: "ⓘ" },
  ] as const;
  type PaneId = (typeof PANES)[number]["id"];
  const known = (s: string): s is PaneId => PANES.some((p) => p.id === s);

  let pane = $state<PaneId>("window");
  let hasToken = $state(false);

  const fromHash = () => { const h = location.hash.slice(1); if (known(h)) pane = h; };

  async function refreshToken() {
    const email = settings.jiraEmail.trim();
    hasToken = email ? (await native.secretGet(JIRA_KEYCHAIN_SERVICE, email).catch(() => null)) != null : false;
  }

  onMount(() => {
    fromHash();
    void startNotes();
    void refreshToken();
    window.addEventListener("hashchange", fromHash);
    const un = listen<string>("settings-pane", (e) => { if (known(e.payload)) pane = e.payload; });
    return () => { window.removeEventListener("hashchange", fromHash); un.then((f) => f()); };
  });
</script>

<div class="shell">
  <nav class="side" aria-label="설정 목록">
    {#each PANES as p (p.id)}
      <button class="nav" class:on={pane === p.id} aria-current={pane === p.id ? "page" : undefined} onclick={() => (pane = p.id)}>
        <span class="ico">{p.icon}</span>
        <span>{p.title}</span>
        {#if p.id === "jira"}<span class="dot" class:ok={hasToken} title={hasToken ? "토큰 저장됨" : "토큰 없음"}></span>{/if}
      </button>
    {/each}
  </nav>
  <main class="content scroll">
    {#if pane === "window"}<WindowPane />
    {:else if pane === "appearance"}<AppearancePane />
    {:else if pane === "tabs"}<TabsPane />
    {:else if pane === "jira"}<JiraPane bind:hasToken />
    {:else if pane === "tags"}<TagsPane />
    {:else if pane === "notes"}<NotesPane />
    {:else}<AboutPane />{/if}
  </main>
</div>
