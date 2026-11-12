<script lang="ts">
  // Teleport 첫 설정 (Mac TeleportSetupView): 1/2 계정(프록시·사용자·비밀번호·OTP 키, 실제 로그인으로 확인) → 2/2 DB·앱 고르기.
  import { onMount } from "svelte";
  import jsQR from "jsqr";
  import { native } from "../lib/native";
  import Sym from "../lib/Sym.svelte";
  import PwInput from "../settings/PwInput.svelte";
  import { tp, tshLogin, saveSecrets, saveConfig, ensureLoggedIn, loadSecrets } from "../lib/teleport.svelte";
  import {
    BASE_PORT, cleanID, duplicatePorts, groupForName, nextFreePort, otpAccountUser, otpSecretOf, parseResources,
    type TeleportTunnel, type TunnelKind,
  } from "../lib/teleportCore";

  interface Entry { name: string; isProd: boolean; kind: TunnelKind; checked: boolean; dbUser: string; portText: string }

  let step = $state(1);
  let proxy = $state(tp.config.proxy);
  let user = $state(tp.config.user);
  let password = $state("");
  let otpKey = $state("");
  let busy = $state(false);
  let error = $state<string | null>(null);
  let note = $state<string | null>(null);
  let entries = $state<Entry[]>([]);
  let kept: TeleportTunnel[] = [];
  let code = $state<{ code: string; left: number } | null>(null);
  let fileInput: HTMLInputElement | undefined = $state();

  let otpUser = $derived(otpAccountUser(otpKey));
  let canNext = $derived(!busy && !!cleanID(proxy) && !!cleanID(user) && !!password && !!otpSecretOf(otpKey));
  let checked = $derived(entries.filter((e) => e.checked));
  let dups = $derived(duplicatePorts([...checked.map((e) => ({ name: e.name, port: Number(e.portText) || -1, dbUser: "", kind: e.kind })), ...kept]));
  let canSave = $derived(checked.length > 0 && !dups.size && checked.every((e) => {
    const p = Number(e.portText);
    return Number.isInteger(p) && p >= 1024 && p <= 65535 && (e.kind === "app" || !!e.dbUser.trim());
  }));

  // OTP 키를 넣으면 계정 칸을 채우고, 현재 코드를 보여준다 (휴대폰 앱과 같으면 키가 맞다)
  $effect(() => { if (otpUser && !user.trim()) user = otpUser; });
  $effect(() => {
    const s = otpSecretOf(otpKey);
    if (!s) { code = null; return; }
    const tick = async () => { const r = await native.totpNow(s).catch(() => null); code = r ? { code: r[0], left: r[1] } : null; };
    void tick();
    const t = setInterval(tick, 1000);
    return () => clearInterval(t);
  });

  onMount(() => { if (tp.hasSecrets && tp.config.user) void loadWithSaved(); });

  async function next() {
    if (!canNext) return;
    busy = true; error = null; note = null;
    try {
      // 빈 임시 프로필로 로그인해 비밀번호·OTP 를 실제로 확인한다 (~/.tsh 세션이 있으면 tsh 가 비밀번호를 묻지 않아서)
      const tmp = `${await native.dataDir()}\\tmp\\tsh-verify-${crypto.randomUUID()}`;
      const r = await tshLogin({ proxy: cleanID(proxy), user: cleanID(user), secrets: { password, otpSecret: otpKey.trim() }, kind: "setup", teleportHome: tmp });
      if (!r.ok) { error = r.message; return; }
      await saveSecrets({ password, otpSecret: otpKey.trim() });
      await saveConfig({ ...tp.config, proxy: cleanID(proxy), user: cleanID(user) });
      if (!(await ensureLoggedIn(false, "setup"))) { error = tp.message ?? "로그인 실패"; return; }
      await loadDBs();
    } finally { busy = false; }
  }

  async function loadWithSaved() {
    error = null;
    busy = true;
    try {
      if (!(await ensureLoggedIn(false, "setup"))) { error = "저장된 정보로 로그인하지 못했어요. 비밀번호와 OTP 키를 다시 넣어 주세요."; return; }
      await loadDBs();
    } finally { busy = false; }
  }

  async function loadDBs() {
    if (!tp.tshPath) return;
    busy = true; error = null; note = null; kept = [];
    try {
      const [r, ar] = await Promise.all([
        native.run(tp.tshPath, ["db", "ls", "--format=json"], { timeoutMs: 30_000 }),
        native.run(tp.tshPath, ["apps", "ls", "--format=json"], { timeoutMs: 30_000 }),
      ]);
      const saved = tp.config.tunnels;
      const dbs = r.code === 0 ? parseResources(r.stdout) : [];
      const savedDBs = saved.filter((t) => t.kind === "db"), savedApps = saved.filter((t) => t.kind === "app");
      const dbNames = new Set([...dbs.map((d) => d.name), ...(r.code !== 0 ? savedDBs.map((t) => t.name) : [])]);
      const apps = ar.code === 0 ? parseResources(ar.stdout).filter((a) => !dbNames.has(a.name)) : [];
      if (!dbs.length && !apps.length) {
        error = r.code !== 0 ? `tsh db ls 실패: ${r.stderr.trim().slice(-200)}` : "접근 가능한 DB·앱이 없어요";
        step = 2; entries = []; return;
      }
      const notes: string[] = [];
      if (r.code !== 0) { notes.push(`tsh db ls 실패: ${r.stderr.trim().slice(-200)}` + (savedDBs.length ? " · 저장된 DB 터널은 그대로 둬요" : "")); kept.push(...savedDBs); }
      if (ar.code !== 0 && savedApps.length) { notes.push("앱 목록을 받지 못했어요 · 저장된 앱 터널은 그대로 둬요"); kept.push(...savedApps); }
      note = notes.length ? notes.join("\n") : null;
      const prev = new Map(saved.map((t) => [t.name, t]));
      const entry = (x: { name: string; isProd: boolean }, kind: TunnelKind): Entry => {
        const t = prev.get(x.name);
        return t && t.kind === kind
          ? { name: x.name, isProd: x.isProd, kind, checked: true, dbUser: t.dbUser, portText: String(t.port) }
          : { name: x.name, isProd: x.isProd, kind, checked: false, dbUser: "developer", portText: "" };
      };
      entries = [...dbs.map((d) => entry(d, "db")), ...apps.map((a) => entry(a, "app"))];
      step = 2;
    } finally { busy = false; }
  }

  function setChecked(i: number, on: boolean) {
    const e = entries[i];
    e.checked = on;
    if (on && !e.portText) {
      const used = new Set([...entries.filter((x, j) => x.checked && j !== i).map((x) => Number(x.portText)).filter(Boolean), ...kept.map((t) => t.port)]);
      e.portText = String(nextFreePort(used, BASE_PORT));
    }
  }

  async function save() {
    error = null;
    const prevGroup = new Map(tp.config.tunnels.map((t) => [t.name, t.group]));
    const tunnels: TeleportTunnel[] = checked.map((e) => ({
      name: e.name, port: Number(e.portText), kind: e.kind, dbUser: e.kind === "app" ? "developer" : e.dbUser.trim(), group: prevGroup.get(e.name),
    }));
    const names = new Set(tunnels.map((t) => t.name));
    tunnels.push(...kept.filter((t) => !names.has(t.name)));
    try {
      await saveConfig({ ...tp.config, tunnels });
      password = ""; otpKey = "";
    } catch (e) { error = `저장 실패: ${e}`; }
  }

  async function readQR(f: File | undefined) {
    if (!f) return;
    try {
      const bmp = await createImageBitmap(f);
      const c = new OffscreenCanvas(bmp.width, bmp.height);
      const ctx = c.getContext("2d")!;
      ctx.drawImage(bmp, 0, 0);
      const img = ctx.getImageData(0, 0, bmp.width, bmp.height);
      const r = jsQR(img.data, img.width, img.height);
      if (r?.data && otpSecretOf(r.data)) { otpKey = r.data; error = null; }
      else error = "이미지에서 OTP QR 코드를 찾지 못했어요";
    } catch { error = "이미지를 읽지 못했어요"; }
    if (fileInput) fileInput.value = "";
  }

  const groups = $derived.by(() => {
    const m = new Map<string, number[]>();
    entries.forEach((e, i) => {
      const g = tp.config.tunnels.find((t) => t.name === e.name)?.group ?? groupForName(e.name);
      m.set(g, [...(m.get(g) ?? []), i]);
    });
    return [...m.entries()];
  });
</script>

<div class="setup">
  <div class="head">
    <b>Teleport 설정 · {step}/2 {step === 1 ? "계정" : "DB 선택"}</b>
    <span class="grow"></span>
    {#if tp.config.user && tp.config.tunnels.length && tp.hasSecrets}<button class="chip plain" onclick={() => (tp.setupRequested = false)}>취소</button>{/if}
  </div>
  <div class="body scroll">
    {#if !tp.tshPath}
      <div class="warnbox">
        tsh 를 찾지 못했어요. Teleport 클라이언트(tsh)를 설치하고 PATH 에 넣거나, 설정 &gt; Teleport 에서 tsh 경로를 지정해 주세요.
      </div>
    {/if}
    {#if step === 1}
      <label class="f"><span>프록시</span><input class="field" placeholder="teleport.example.com" bind:value={proxy} /></label>
      <label class="f"><span>사용자 ID</span><input class="field" placeholder="Teleport 계정 (DB 사용자 developer 아님)" bind:value={user} /></label>
      {#if otpUser && cleanID(user) && otpUser !== cleanID(user)}<div class="hint warn">OTP 키의 계정은 {otpUser} 이에요</div>{/if}
      <div class="f"><span>비밀번호</span><PwInput label="Teleport 비밀번호" bind:value={password} /></div>
      <div class="f"><span>OTP 키</span><PwInput label="base32 키 또는 otpauth://totp/… 주소" bind:value={otpKey} /></div>
      <div class="row">
        <input type="file" accept="image/*" hidden bind:this={fileInput} onchange={(e) => readQR(e.currentTarget.files?.[0])} />
        <button class="chip soft" onclick={() => fileInput?.click()}><Sym name="qr" />QR 이미지로 읽기</button>
        {#if code}<span class="code tnum">현재 코드 {code.code.slice(0, 3)} {code.code.slice(3)} <span class="faint">· {code.left}초</span></span>{/if}
      </div>
      <div class="hint">비밀번호와 OTP 키는 설정에서 고른 저장 위치(자격 증명 관리자 또는 secrets.json)에만 저장돼요. 다음을 누르면 실제로 로그인해 확인합니다.</div>
      {#if tp.hasSecrets}<button class="chip soft" disabled={busy} onclick={loadWithSaved}>저장된 정보로 DB 목록 받기</button>{/if}
    {:else}
      <div class="hint">DB 접속 툴: localhost, 이 포트, DB 사용자, 비밀번호 없음 · HTTP 앱: http://localhost:포트, 인증 자동</div>
      <div class="row"><button class="chip soft" disabled={busy} onclick={loadDBs}><Sym name="refresh" />다시 불러오기</button></div>
      {#each groups as [g, idxs] (g)}
        <div class="group">{g}</div>
        {#each idxs as i (entries[i].name)}
          {@const e = entries[i]}
          <div class="entry">
            <input type="checkbox" checked={e.checked} onchange={(ev) => setChecked(i, ev.currentTarget.checked)} />
            <span class="name">{e.name}</span>
            {#if e.kind === "app"}<span class="tag">HTTP</span>{/if}
            {#if e.isProd}<span class="tag prod">운영</span>{/if}
            <span class="grow"></span>
            {#if e.checked}
              {#if e.kind === "db"}<input class="field small" bind:value={e.dbUser} aria-label="DB 사용자" />{/if}
              <input class="field port tnum" class:bad={dups.has(Number(e.portText))} bind:value={e.portText} aria-label="포트" />
            {/if}
          </div>
          {#if e.checked && e.isProd}<div class="hint warn indent">운영 DB 예요. 조심해서 써 주세요.</div>{/if}
        {/each}
      {/each}
    {/if}
    {#if note}<div class="hint warn pre">{note}</div>{/if}
    {#if error}<div class="hint err">{error} <button class="chip" onclick={() => native.openDataPath("logs/teleport-login.log", true)}>로그</button></div>{/if}
  </div>
  <div class="foot">
    {#if busy}<span class="faint"><span class="spin"><Sym name="refresh" /></span> {step === 1 ? "로그인 확인 중…" : "불러오는 중…"}</span>{/if}
    <span class="grow"></span>
    {#if step === 2}<button class="chip plain" onclick={() => { step = 1; error = null; }}>이전</button>{/if}
    {#if step === 1}
      <button class="chip solid lg" disabled={!canNext || !tp.tshPath} onclick={next}>다음</button>
    {:else}
      <button class="chip solid lg" disabled={!canSave} onclick={save}>{checked.length}개 저장</button>
    {/if}
  </div>
</div>

<style>
  .setup { display: flex; flex-direction: column; height: 100%; min-height: 0; }
  .head, .foot { display: flex; align-items: center; gap: 6px; padding: 8px 12px; flex: none; }
  .head { border-bottom: 0.5px solid var(--line2); }
  .foot { border-top: 0.5px solid var(--line2); }
  .grow { flex: 1; }
  .body { flex: 1; min-height: 0; padding: 10px 12px; display: flex; flex-direction: column; gap: 8px; }
  .f { display: flex; flex-direction: column; gap: 3px; }
  .f > span { font-size: 0.85em; color: var(--fg2); }
  .row { display: flex; align-items: center; gap: 8px; }
  .code { font-size: 0.9em; }
  .hint { font-size: 0.82em; color: var(--fg2); line-height: 1.45; }
  .hint.warn { color: var(--warn); }
  .hint.err { color: var(--danger); }
  .pre { white-space: pre-wrap; }
  .indent { margin-left: 24px; }
  .warnbox { padding: 8px 10px; border-radius: 8px; background: var(--warn-soft); color: var(--warn); font-size: 0.88em; }
  .group { margin-top: 6px; font-size: 0.82em; font-weight: 600; color: var(--fg2); }
  .entry { display: flex; align-items: center; gap: 6px; }
  .name { font-weight: 500; }
  .tag { font-size: 0.75em; font-weight: 700; padding: 0 5px; border-radius: 4px; background: var(--fill2); color: var(--fg2); }
  .tag.prod { background: var(--danger-soft); color: var(--danger); }
  .small { width: 96px; padding: 2px 6px; }
  .port { width: 64px; padding: 2px 6px; }
  .port.bad { border-color: var(--danger); color: var(--danger); }
</style>
