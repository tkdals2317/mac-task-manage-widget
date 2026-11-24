<script lang="ts" module>
  import type { IssueResult, Job } from "../lib/e2eCore";
  export interface CommentTarget { job: Job; issue: IssueResult; shots: number }
</script>

<script lang="ts">
  // Jira 댓글로 남기기 전 확인. 결과 폴더에 스크린샷이 있으면 같이 첨부할지도 고른다. (Mac e2eCommentConfirm)
  import { postComment } from "../lib/e2e.svelte";
  let { target = $bindable() }: { target: CommentTarget | null } = $props();

  const go = (withShots: boolean) => { const t = target; target = null; if (t) void postComment(t.job.id, t.issue.key, withShots); };
  function key(e: KeyboardEvent) { if (target && e.key === "Escape") { e.stopPropagation(); target = null; } }
</script>

<svelte:window onkeydown={key} />

{#if target}
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
  <div class="modal-back" onclick={() => (target = null)}>
    <div class="modal" role="dialog" tabindex="-1" aria-modal="true" onclick={(e) => e.stopPropagation()}>
      <div class="title">{target.issue.key} 이슈에 검증 결과를 댓글로 남길까요?</div>
      <div class="msg">
        Jira 에 내 이름으로 댓글이 달리고, 이슈를 보는 사람에게 알림이 갈 수 있어요. 판정·시나리오·기대·실제 결과와 환경 주소가 들어가요.
        {#if target.shots > 0}<br />스크린샷은 이슈에 첨부되고 댓글 안 시나리오 아래에 이미지로 보여요.{/if}
        {#if target.job.jiraComments[target.issue.key]}<br />이 결과는 이미 한 번 남겼어요.{/if}
      </div>
      <div class="col">
        {#if target.shots > 0}<button class="btn primary" onclick={() => go(true)}>댓글 + 스크린샷 {target.shots}장</button>{/if}
        <button class="btn" class:primary={target.shots === 0} onclick={() => go(false)}>{target.shots > 0 ? "댓글만 (스크린샷 없이)" : "댓글 남기기"}</button>
        <button class="btn" onclick={() => (target = null)}>취소</button>
      </div>
    </div>
  </div>
{/if}

<style>
  .col { display: flex; flex-direction: column; gap: 6px; margin-top: 4px; }
</style>
