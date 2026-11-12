<script lang="ts">
  // Jira 헤더의 버전 필터/묶기 메뉴 pill.
  import {
    commonPrefix, displayVersion, parseVersionFilter, sameFilter, versionCounts, versionFilterStorage, type VersionFilter,
  } from "../lib/jira";
  import { setSetting, settings } from "../lib/settings.svelte";
  import { jira } from "./jiraState.svelte";
  import Icon from "./Icon.svelte";
  import Menu, { type MenuItem } from "./Menu.svelte";

  let open = $state(false);
  let btn: HTMLElement | undefined = $state();

  const filter = $derived(parseVersionFilter(settings.jiraVersionFilter));
  const counts = $derived(versionCounts(jira.issues));
  const prefix = $derived(commonPrefix(counts.versions.map((v) => v.name)));
  const selected = $derived(filter.kind !== "all");
  const label = $derived(
    filter.kind === "all" ? (settings.jiraGroupByVersion ? "버전별" : "버전 전체")
      : filter.kind === "none" ? "버전 없음"
      : displayVersion(filter.name, commonPrefix(jira.issues.flatMap((i) => i.fixVersions))),
  );

  const pick = (f: VersionFilter) => setSetting("jiraVersionFilter", versionFilterStorage(f));
  const item = (title: string, f: VersionFilter): MenuItem => ({ label: title, checked: sameFilter(filter, f), onselect: () => pick(f) });
  const items = $derived<MenuItem[]>([
    item(`전체 (${jira.issues.length})`, { kind: "all" }),
    ...counts.versions.map((v) => item(`${displayVersion(v.name, prefix)} (${v.count})`, { kind: "named", name: v.name })),
    item(`버전 없음 (${counts.noneCount})`, { kind: "none" }),
    { separator: true },
    { label: "버전별로 묶기", checked: settings.jiraGroupByVersion, onselect: () => setSetting("jiraGroupByVersion", !settings.jiraGroupByVersion) },
  ]);
</script>

{#if jira.configured}
  <span class="wrap">
    <button bind:this={btn} class="pill" class:selected onclick={() => (open = !open)}>
      {#if filter.kind === "all" && settings.jiraGroupByVersion}<Icon name="split" size={0.85} />{/if}
      {label}
      {#if !selected}<Icon name="chevron-down" size={0.7} />{/if}
    </button>
    {#if selected}
      <button class="icon-x" title="필터 해제" aria-label="필터 해제" onclick={() => pick(parseVersionFilter(""))}><Icon name="x" size={0.8} /></button>
    {/if}
  </span>
  {#if open && btn}
    <Menu {items} anchor={btn} align="end" onclose={() => (open = false)} />
  {/if}
{/if}

<style>
  .wrap { display: inline-flex; align-items: center; gap: 3px; }
  .pill {
    display: inline-flex; align-items: center; gap: 3px; padding: 1px 7px; border-radius: 999px; cursor: pointer;
    font-size: 0.92em; color: var(--fg2); background: transparent; border: 1px solid var(--line);
  }
  .pill.selected { color: var(--fg); background: var(--fill2); border-color: transparent; }
  .icon-x { border: none; background: transparent; padding: 0; cursor: pointer; color: var(--fg2); display: inline-flex; }
</style>
