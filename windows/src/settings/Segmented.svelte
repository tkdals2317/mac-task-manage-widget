<script lang="ts" generics="T extends string | number">
  let { options, value, onpick, disabled = false }: {
    options: { value: T; label: string }[];
    value: T;
    onpick: (v: T) => void;
    disabled?: boolean;
  } = $props();
</script>

<div class="seg" role="group">
  {#each options as o (o.value)}
    <button type="button" class:on={value === o.value} {disabled} aria-pressed={value === o.value} onclick={() => onpick(o.value)}>{o.label}</button>
  {/each}
</div>
