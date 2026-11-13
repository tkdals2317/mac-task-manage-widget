import { describe, expect, it } from "vitest";
import {
  backoff, cleanID, decideWatchdog, duplicatePorts, groupOf, logoutArgs, namesToRestore, nextFreePort, otpAccountUser, otpSecretOf,
  parseConfig, parseResources, parseSessionExpiry, proxyArgs, remainingText, serializeConfig, waitText, isAuthFailure,
} from "./teleportCore";
import { hookCommand, hookStatusOf, isOurs, withHook, withoutHook } from "./claude";

describe("teleportCore", () => {
  it("teleport.json 읽기·쓰기 (Mac 과 같은 모양)", () => {
    const c = parseConfig({ proxy: "p", user: "u", tunnels: [{ name: "shop-dv", port: 4306, dbUser: "dev" }, { name: "web", port: 4307, kind: "app" }, { name: "x", port: 1, kind: "oops" }, { bad: 1 }] });
    expect(c.tunnels.map((t) => t.kind)).toEqual(["db", "app", "db"]);
    expect(serializeConfig(c)).toEqual({ proxy: "p", user: "u", tunnels: [
      { name: "shop-dv", port: 4306, dbUser: "dev" }, { name: "web", port: 4307, kind: "app" }, { name: "x", port: 1, dbUser: "developer" }] });
    expect(proxyArgs(c.tunnels[0])).toEqual(["proxy", "db", "--tunnel", "shop-dv", "--db-user", "dev", "--port", "4306"]);
    expect(proxyArgs(c.tunnels[1])).toEqual(["proxy", "app", "web", "--port", "4307"]);
    expect(logoutArgs(c.tunnels[1])).toEqual(["apps", "logout", "web"]);
    expect(groupOf(c.tunnels[0])).toBe("SHOP");
    expect(groupOf({ ...c.tunnels[0], group: "결제" })).toBe("결제");
    expect(parseConfig(null)).toEqual({ proxy: "", user: "", tunnels: [] });
  });

  it("포트", () => {
    expect(nextFreePort(new Set([4306, 4307]))).toBe(4308);
    expect([...duplicatePorts([{ name: "a", port: 1, dbUser: "", kind: "db" }, { name: "b", port: 1, dbUser: "", kind: "db" }])]).toEqual([1]);
  });

  it("tsh 출력 해석", () => {
    const ls = JSON.stringify([{ metadata: { name: "shop-prd" } }, { metadata: { name: "a-dv", labels: { env: "production" } } }, { metadata: { name: "b-dv" } }, { metadata: {} }]);
    expect(parseResources(ls)).toEqual([{ name: "a-dv", isProd: true }, { name: "b-dv", isProd: false }, { name: "shop-prd", isProd: true }]);
    expect(parseResources("nope")).toEqual([]);
    const d = parseSessionExpiry(JSON.stringify({ active: { valid_until: "2026-11-13T12:00:00.123456789+09:00" } }));
    expect(d?.toISOString()).toBe("2026-11-13T03:00:00.123Z");
    expect(remainingText(new Date(Date.now() + 125 * 60000))).toMatch(/^2시간 [45]분 남음$/);
    expect(isAuthFailure("ERROR: invalid username, password or second factor")).toBe(true);
  });

  it("OTP 입력", () => {
    expect(otpSecretOf("jbsw y3dp ehpk 3pxp")).toBe("JBSWY3DPEHPK3PXP");
    expect(otpSecretOf("otpauth://totp/Teleport:kim@host?secret=JBSWY3DPEHPK3PXP&issuer=T")).toBe("JBSWY3DPEHPK3PXP");
    expect(otpSecretOf("otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP")).toBeNull();
    expect(otpSecretOf("1234!")).toBeNull();
    expect(otpAccountUser("otpauth://totp/Teleport:kim@host?secret=X")).toBe("kim");
    expect(cleanID(" ki\u200Bm\n")).toBe("kim");
  });

  it("자동 유지 판단과 백오프", () => {
    const p = decideWatchdog(["a", "b", "c"], new Set(["a", "b"]), new Set(["a"]), { c: Date.now() + 30_000 }, true);
    expect(p).toMatchObject({ relogin: false, restart: ["b"] });
    expect(Object.keys(p.waiting)).toEqual(["c"]);
    expect(decideWatchdog(["a"], new Set(["a"]), new Set(["a"]), {}, false).relogin).toBe(true);
    expect([1, 2, 3, 10].map((n) => backoff(n, 60))).toEqual([60, 120, 240, 300]);
    expect(waitText(5)).toBe("5초 후");
    expect(waitText(61)).toBe("2분 후");
    expect(namesToRestore(["b", "x"], ["a", "b"], true)).toEqual(["b"]);
    expect(namesToRestore(["b"], ["b"], false)).toEqual([]);
  });
});

describe("claude 훅 설정", () => {
  const cmd = hookCommand("C:\\Users\\me\\ATM\\atm.exe");
  it("명령은 슬래시 경로", () => {
    expect(cmd).toBe('"C:/Users/me/ATM/atm.exe" --hook');
    expect(isOurs(cmd)).toBe(true);
    expect(isOurs('"/Applications/ATM.app/Contents/MacOS/TaskWidget" --hook')).toBe(true);
    expect(isOurs("other --hook")).toBe(false);
  });

  it("다른 훅은 보존하고 넣고 뺀다", () => {
    const root = { model: "x", hooks: { Stop: [{ hooks: [{ type: "command", command: "other" }] }] } };
    const a = withHook(root, cmd);
    expect(hookStatusOf(a, cmd)).toBe("installed");
    expect(hookStatusOf(a, '"D:/new/atm.exe" --hook')).toBe("pathMismatch");
    expect((a.hooks as Record<string, unknown[]>).Stop).toHaveLength(2);
    const again = withHook(withHook(a, '"D:/new/atm.exe" --hook'), cmd);
    expect(hookStatusOf(again, cmd)).toBe("installed");
    const b = withoutHook(a);
    expect(b).toEqual(root);
    expect(withoutHook({ hooks: { Stop: [{ hooks: [{ command: cmd }] }] } })).toEqual({});
    expect(hookStatusOf({}, cmd)).toBe("notInstalled");
  });
});
