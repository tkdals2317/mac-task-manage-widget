<script lang="ts">
  // 할 일 탭 (Mac TasksView): 내 할 일 + 완료 + Jira.
  import { filterByVersion, parseVersionFilter } from "../lib/jira";
  import { setSetting, settings } from "../lib/settings.svelte";
  import { addTodo, clearDone, doneTodos, openTodos } from "../lib/todos.svelte";
  import Icon from "../tasks/Icon.svelte";
  import JiraSection from "../tasks/JiraSection.svelte";
  import JiraVersionMenu from "../tasks/JiraVersionMenu.svelte";
  import SectionHeader from "../tasks/SectionHeader.svelte";
  import TodoRow from "../tasks/TodoRow.svelte";
  import { jira, refreshJira } from "../tasks/jiraState.svelte";

  let newTitle = $state("");
  let doneExpanded = $state(false);

  // 할 일 저장소는 main.svelte.ts 가 앱 시작 때 한 번 띄운다 (다른 탭의 "할 일로" 가 불러오기 전 목록을 저장하지 않게)

  const open = $derived(openTodos(settings.sortTodosByTag));
  const done = $derived(doneTodos());
  const jiraCount = $derived(filterByVersion(jira.issues, parseVersionFilter(settings.jiraVersionFilter)).length);

  function submit() {
    addTodo(newTitle);
    newTitle = "";
  }
</script>

<div class="scroll tasks">
  <SectionHeader title="내 할 일" count={open.length} 
    bind:collapsed={() => settings.todoSectionCollapsed, (v) => setSetting("todoSectionCollapsed", v)} />
  {#if !settings.todoSectionCollapsed}
    <input class="field add" placeholder="할 일 추가…" bind:value={newTitle}
      onkeydown={(e) => { if (e.key === "Enter" && !e.isComposing) submit(); }} />

    {#each open as todo (todo.id)}<TodoRow {todo} />{/each}
    {#if open.length === 0}<div class="faint none">할 일 없음</div>{/if}

    {#if done.length > 0}
      <div class="done-head muted">
        <button class="toggle" onclick={() => (doneExpanded = !doneExpanded)}>
          <Icon name={doneExpanded ? "chevron-down" : "chevron-right"} size={0.7} />
          <span>완료 {done.length}</span>
        </button>
        <span class="grow"></span>
        <button class="chip clear" title="완료한 할 일을 모두 지워요" onclick={clearDone}><Icon name="trash" size={0.9} />비우기</button>
      </div>
      {#if doneExpanded}
        {#each done as todo (todo.id)}<TodoRow {todo} />{/each}
      {/if}
    {/if}
  {/if}

  <SectionHeader title="Jira" count={jiraCount} 
    bind:collapsed={() => settings.jiraSectionCollapsed, (v) => setSetting("jiraSectionCollapsed", v)}>
    {#snippet trailing()}
      <JiraVersionMenu />
      <button class="refresh" title="새로고침" aria-label="새로고침" onclick={() => refreshJira()}><Icon name="refresh" size={0.9} /></button>
    {/snippet}
  </SectionHeader>
  {#if !settings.jiraSectionCollapsed}<JiraSection />{/if}
</div>

<style>
  .tasks { flex: 1; min-height: 0; padding: 0 10px 8px; }
  .add { margin: 4px 0; padding: 4px 7px; font-size: 1.04em; user-select: text; }
  .none { padding: 8px 0; }
  .done-head { display: flex; align-items: center; padding: 8px 0 2px; font-size: 0.92em; }
  .toggle { display: inline-flex; align-items: center; gap: 4px; border: none; background: transparent; padding: 0; cursor: pointer; color: inherit; }
  .grow { flex: 1; }
  .clear { gap: 3px; }
  .clear:hover { background: var(--fill2); color: var(--fg); }
  .refresh { border: none; background: transparent; padding: 0; cursor: pointer; color: var(--fg2); display: inline-flex; }
  .refresh:hover { color: var(--fg); }
</style>
