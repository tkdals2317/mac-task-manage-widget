<script lang="ts">
  import { openUrl } from "@tauri-apps/plugin-opener";
  import { issueURL, normalizeBase, versionTag, type JiraIssue } from "../lib/jira";
  import { settings } from "../lib/settings.svelte";
  import { jira } from "./jiraState.svelte";
  import Icon from "./Icon.svelte";
  import Menu from "./Menu.svelte";
  import TransitionPopover from "./TransitionPopover.svelte";
  import { statusColor } from "./statusColor";
  import { truncTitle } from "./truncTitle";

  let { issue, prefix = "", trailing = "none" }: { issue: JiraIssue; prefix?: string; trailing?: "none" | "version" } = $props();
  let showTransitions = $state(false);
  let pillBtn: HTMLElement | undefined = $state();
  let menu = $state<{ x: number; y: number } | null>(null);

  const tint = $derived(statusColor(issue.statusCategory));
  const prio = $derived(["Highest", "High"].includes(issue.priority ?? "") ? "var(--danger)" : issue.priority === "Medium" ? "var(--warn)" : "var(--fg3)");
  const tag = $derived(trailing === "version" ? versionTag(issue, prefix) : null);
  const busy = $derived(jira.busy.includes(issue.id));

  function open() {
    const base = normalizeBase(settings.jiraBaseURL);
    if (base) void openUrl(issueURL(base, issue.id));
  }
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="jrow" oncontextmenu={(e) => { e.preventDefault(); menu = { x: e.clientX, y: e.clientY }; }}>
  <button class="link" onclick={open}>
    <span class="prio" style="background:{prio}"></span>
    <span class="key mono">{issue.id}</span>
    <span class="sum" use:truncTitle={{ full: issue.summary }}>{issue.summary}</span>
    {#if tag}<span class="ver mono">{tag}</span>{/if}
  </button>
  {#if busy}
    <span class="spin" aria-label="변경 중"></span>
  {:else}
    <button bind:this={pillBtn} class="status" style="--t:{tint}" title="상태 변경" onclick={() => (showTransitions = !showTransitions)}>
      <span class="sname">{issue.status}</span><Icon name="chevron-down" size={0.7} />
    </button>
  {/if}
</div>

{#if showTransitions && pillBtn}
  <TransitionPopover {issue} anchor={pillBtn} onclose={() => (showTransitions = false)} />
{/if}
{#if menu}
  <Menu items={[{ label: "상태 변경…", onselect: () => (showTransitions = true) }]} anchor={menu} onclose={() => (menu = null)} />
{/if}

<style>
  .jrow { display: flex; align-items: center; gap: 6px; border-bottom: 1px solid var(--line); }
  .link { flex: 1; min-width: 0; display: flex; align-items: center; gap: 6px; padding: 5px 0; border: none; background: transparent; cursor: pointer; text-align: left; }
  .prio { width: 6px; height: 6px; border-radius: 50%; flex: none; }
  .key { font-size: 0.92em; color: var(--accent); flex: none; }
  .sum { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .ver { font-size: 0.85em; padding: 1px 5px; border-radius: 999px; background: var(--fill2); color: color-mix(in srgb, var(--fg) 78%, transparent); flex: none; }
  .status {
    display: inline-flex; align-items: center; gap: 3px; padding: 2px 7px; border-radius: 999px; flex: none; max-width: 40%;
    font-size: 0.88em; font-weight: 500; cursor: pointer; color: var(--t);
    background: color-mix(in srgb, var(--t) 16%, transparent); border: 1px solid color-mix(in srgb, var(--t) 25%, transparent);
  }
  .status:hover { background: color-mix(in srgb, var(--t) 26%, transparent); }
  .sname { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .spin { width: 0.9em; height: 0.9em; border-radius: 50%; border: 2px solid var(--line); border-top-color: var(--accent); animation: spin 0.8s linear infinite; flex: none; }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>
