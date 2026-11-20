import { describe, expect, it } from "vitest";
import {
  blocker, detectFailure, execArguments, failureOfMessage, failureMessage, isNewer, missingResultMessage, modelNames, parseAccountStatus, parseConnectedModels, parseModels,
  parseOtherAccounts, parsePlainAccountStatus, parseWindowOpen, runOutcome, sessionIdIn, setupItems, type AsideProbe, type SetupInput,
} from "./asideCore";
import { parseResult } from "./e2eCore";

describe("aside exec 인자", () => {
  it("권한은 늘 guard, 모델은 있을 때만, 지시문은 마지막", () => {
    expect(execArguments("P")).toEqual(["exec", "--permission", "guard", "P"]);
    expect(execArguments("P", " claude-code/sonnet ")).toEqual(["exec", "--permission", "guard", "--model", "claude-code/sonnet", "P"]);
    expect(execArguments("P", "x").join(" ")).not.toContain("full-access");
  });
  it("세션 id 는 created new session 뒤의 한 단어", () => {
    expect(sessionIdIn("[x] created new session: abc-123")).toBe("abc-123");
    expect(sessionIdIn("created new session: a b")).toBeNull();
    expect(sessionIdIn("nothing")).toBeNull();
  });
  it("버전 비교", () => {
    expect(isNewer("1.26.1107.24", "1.26.1107.9")).toBe(true);
    expect(isNewer("1.26", "1.26.0")).toBe(false);
    expect(isNewer("1.2.x", "1.2.0")).toBe(false);
    expect(isNewer("", "1.0")).toBe(false);
  });
});

describe("계정 상태", () => {
  it("로그인은 active + 세션 + cloud 일 때만", () => {
    expect(parseAccountStatus('{"account":{"id":2,"email":"me@x.com","authStatus":"active","hasSession":true,"subscriptionPlan":"pro"}}', 0))
      .toEqual({ kind: "signedIn", email: "me@x.com", accountId: 2, plan: "pro" });
    expect(parseAccountStatus('{"account":{"id":2,"email":"me@x.com","authStatus":"active","mode":"local"}}', 0)).toMatchObject({ kind: "signedOut", reason: { kind: "noSession" } });
    expect(parseAccountStatus('{"account":{"authStatus":"paused","authPausedReason":"token_revoked","name":"n"}}', 0)).toMatchObject({ kind: "signedOut", reason: { kind: "paused", why: "token_revoked" } });
    expect(parseAccountStatus('{"account":{"provider":"anonymous"}}', 0)).toMatchObject({ kind: "signedOut", reason: { kind: "never" } });
    expect(parseAccountStatus("Not signed in. Run aside login", 1)).toMatchObject({ kind: "signedOut", reason: { kind: "never" } });
    expect(parseAccountStatus("boom", 3)).toMatchObject({ kind: "unknown" });
  });
  it("다른 계정 목록", () => {
    const out = parseOtherAccounts('{"currentAccountId":0,"accounts":[{"id":0,"email":"a"},{"id":1,"email":"b@x","authStatus":"active"},{"id":2}]}');
    expect(out).toEqual([{ id: 1, title: "b@x", signedIn: true }, { id: 2, title: "u2", signedIn: false }]);
    expect(parseOtherAccounts("garbage")).toEqual([]);
  });
  it("구버전 일반 출력", () => {
    expect(parsePlainAccountStatus("* u0  me@example.com  signed in  profiles: Profile 0")).toEqual({ kind: "signedIn", email: "me@example.com", accountId: 0, plan: "" });
    expect(parsePlainAccountStatus("  u0  me@example.com  not signed in")).toMatchObject({ kind: "signedOut" });
    expect(parsePlainAccountStatus("???")).toMatchObject({ kind: "unknown" });
  });
  it("창이 열려 있는지", () => {
    expect(parseWindowOpen('{"profiles":[{"connected":false},{"connected":true}]}')).toBe(true);
    expect(parseWindowOpen('{"profiles":[]}')).toBe(false);
    expect(parseWindowOpen("Profile 0  disconnected")).toBe(false);
    expect(parseWindowOpen("Profile 0  connected")).toBe(true);
    expect(parseWindowOpen("No browser profiles")).toBe(false);
    expect(parseWindowOpen("???")).toBeNull();
  });
});

describe("모델 목록", () => {
  const cache = JSON.stringify({ '["models","aside-catalog"]': { value: { models: [{ id: "m1", name: "Model 1", minPlan: "pro" }, { id: "" }] } }, other: { value: { models: [{ id: "c1", name: "Claude" }] } } });
  it("Aside 카탈로그와 연동 provider 모델", () => {
    expect(parseModels(cache)).toEqual([{ id: "m1", name: "Model 1", minPlan: "pro", provider: "aside" }]);
    expect(parseModels("nope")).toEqual([]);
    const names = modelNames(cache);
    expect(names).toMatchObject({ m1: "Model 1", c1: "Claude" });
    const connected = JSON.stringify({ providers: { "claude-code": { accountModelCatalog: { modelIds: ["c1"], scopes: { x: { modelIds: ["c1", "c2"] } } } } } });
    expect(parseConnectedModels(connected, names).map((m) => [m.id, m.name])).toEqual([["claude-code/c1", "Claude · claude-code"], ["claude-code/c2", "c2 · claude-code"]]);
  });
});

describe("실패 원인", () => {
  it("출력에서 알아본다", () => {
    expect(detectFailure("error: Unknown option --permission")).toBe("cliOutdated");
    expect(detectFailure("No procedure found on path x")).toBe("versionMismatch");
    expect(detectFailure("model x is not available for this account")).toBe("modelUnavailable");
    expect(detectFailure("Please run aside login")).toBe("signedOut");
    expect(detectFailure("EPERM: operation not permitted")).toBe("folderBlocked");
    expect(detectFailure("browser is not connected to the daemon")).toBe("windowClosed");
    expect(detectFailure("ECONNREFUSED 127.0.0.1")).toBe("asideDown");
    expect(detectFailure("fine")).toBeNull();
  });
  it("저장된 문장에서 다시 찾는다", () => {
    expect(failureOfMessage(failureMessage("windowClosed"))).toBe("windowClosed");
    expect(failureOfMessage("딴 문장")).toBeNull();
  });
  it("result.json 이 없을 때의 한 줄", () => {
    expect(missingResultMessage(0, "x\nERR daemon down\n")).toBe(failureMessage("asideDown"));
    expect(missingResultMessage(2, "a\n\nlast line\n")).toBe("결과 파일(result.json)이 없어요 (exit 2) · last line");
    expect(missingResultMessage(0, "")).toBe("결과 파일(result.json)이 없어요 (exit 0)");
  });
  it("실행 결과 판정: 취소 > 결과 > 시간 초과 > 읽기 실패 > 없음", () => {
    const good = parseResult('{"issues":[{"key":"A-1","verdict":"PASS"}]}');
    const empty = parseResult('{"issues":[]}');
    const base = { cancelled: false, cancelReason: null, timedOut: false, timeoutMs: 20 * 60_000, exitCode: 0, output: "" };
    expect(runOutcome({ ...base, cancelled: true, cancelReason: "r", result: good })).toEqual({ status: "cancelled", error: "r" });
    expect(runOutcome({ ...base, result: good, timedOut: true })).toEqual({ status: "done", error: null });
    expect(runOutcome({ ...base, result: empty }).status).toBe("failed");
    expect(runOutcome({ ...base, result: { kind: "missing" }, timedOut: true }).error).toContain("제한 시간 20분");
    expect(runOutcome({ ...base, result: { kind: "invalid", message: "JSON 형식이 아님" } }).error).toBe("result.json 을 읽지 못했어요 (JSON 형식이 아님)");
    expect(runOutcome({ ...base, result: { kind: "missing" }, exitCode: 1 }).error).toContain("exit 1");
  });
});

describe("준비 점검", () => {
  const probe = (p: Partial<AsideProbe> = {}): AsideProbe => ({
    path: "C:\\aside.exe", source: "PATH", version: "1.26.1", latestVersion: "", runnable: true, otherAccounts: [], windowOpen: true,
    account: { kind: "signedIn", email: "me@x.com", accountId: 0, plan: "" }, ...p,
  });
  const input = (p: Partial<SetupInput> = {}): SetupInput => ({ browserInstalled: true, browserVersion: "", probe: probe(), env: null, envURL: "", envUser: "", lastLogin: { kind: "none" }, ...p });
  const state = (i: SetupInput, kind: string) => setupItems(i).find((x) => x.kind === kind)?.state;

  it("다 되면 막는 항목이 없다", () => {
    expect(blocker(setupItems(input()))).toBeUndefined();
    expect(setupItems(input()).map((i) => i.state)).toEqual(["ok", "ok", "ok", "ok"]);
  });
  it("브라우저·CLI 가 없으면 다운로드, CLI 를 보고 나서야 나머지를 확인한다", () => {
    const none = setupItems(input({ browserInstalled: false, probe: null }));
    expect(none.map((i) => i.state)).toEqual(["todo", "waiting", "waiting"]);
    expect(none[0].fixes).toEqual([{ kind: "downloadBrowser" }]);
    const noCli = setupItems(input({ probe: null }));
    expect(noCli[1]).toMatchObject({ state: "todo", fixes: [{ kind: "installCLI" }] });
  });
  it("CLI 가 오래됐으면 막고, 새 버전이 있으면 알린다", () => {
    expect(state(input({ probe: probe({ runnable: false }) }), "cli")).toBe("todo");
    const upd = setupItems(input({ probe: probe({ latestVersion: "1.27" }) }))[1];
    expect(upd.state).toBe("ok");
    expect(upd.fixes).toEqual([{ kind: "updateCLI" }]);
  });
  it("로그아웃이면 막고 다른 로그인 계정으로 바꾸는 버튼을 준다", () => {
    const out = probe({ account: { kind: "signedOut", who: "me", reason: { kind: "noSession" } }, otherAccounts: [{ id: 1, title: "b@x", signedIn: true }] });
    const it = setupItems(input({ probe: out })).find((x) => x.kind === "account")!;
    expect(it.state).toBe("todo");
    expect(it.fixes.map((f) => f.kind)).toEqual(["openAside", "loginCLI", "switchAccount"]);
  });
  it("창이 닫혀 있어도 막지는 않는다", () => {
    expect(state(input({ probe: probe({ windowOpen: false }) }), "window")).toBe("warn");
    expect(state(input({ probe: probe({ windowOpen: null }) }), "window")).toBeUndefined();
  });
  it("환경: 주소 없음은 막고, 로그인은 지난 검증으로 안내", () => {
    expect(state(input({ env: "ST" }), "envURL")).toBe("todo");
    const withURL = (lastLogin: SetupInput["lastLogin"]) => setupItems(input({ env: "ST", envURL: "https://st", lastLogin })).find((x) => x.kind === "envLogin")!;
    expect(withURL({ kind: "none" }).state).toBe("info");
    expect(withURL({ kind: "ok" }).state).toBe("ok");
    const blocked = withURL({ kind: "blocked", block: "VAULT_LOCKED" });
    expect(blocked.state).toBe("warn");
    expect(blocked.detail).toContain("잠겨");
  });
});
