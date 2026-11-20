import XCTest
@testable import TaskWidgetCore

/// Aside 준비 점검: CLI 출력 해석과 준비 항목 계산.
final class E2ESetupTests: XCTestCase {
    private let signedIn = AsideAccountStatus.signedIn(email: "me@x.com", accountId: 0, plan: "free")

    private func item(_ items: [E2ESetupItem], _ kind: E2ESetupItem.Kind) -> E2ESetupItem? {
        items.first { $0.kind == kind }
    }

    private func states(_ items: [E2ESetupItem]) -> [E2ESetupItem.State] { items.map(\.state) }

    // MARK: - CLI 출력 해석

    func testParseOtherAccounts() {
        let raw = #"""
        {"currentAccountId":1,"accounts":[
          {"id":0,"email":"a@x.com","mode":"cloud","authStatus":"active","hasSession":true},
          {"id":1,"email":"b@x.com","mode":"cloud","authStatus":"active","hasSession":false},
          {"id":2,"name":"Guest","provider":"anonymous","mode":"local"},
          {"email":"no-id@x.com"}]}
        """#
        XCTAssertEqual(AsideCLI.parseOtherAccounts(raw), [AsideAccount(id: 0, title: "a@x.com", signedIn: true),
                                                         AsideAccount(id: 2, title: "Guest", signedIn: false)])
        XCTAssertEqual(AsideCLI.parseOtherAccounts(#"{"currentAccountId":0,"accounts":[{"id":0,"email":"a@x.com"}]}"#), [])
        XCTAssertEqual(AsideCLI.parseOtherAccounts("Error: Unknown option '--json'"), [])
    }

    func testParseWindowOpen() {
        XCTAssertEqual(AsideCLI.parseWindowOpen(#"{"host":"local","profiles":[{"profileId":"p","label":"Profile 0","connected":false}]}"#), false)
        XCTAssertEqual(AsideCLI.parseWindowOpen(#"{"profiles":[{"connected":false},{"connected":true}]}"#), true)
        XCTAssertEqual(AsideCLI.parseWindowOpen(#"{"host":"local","profiles":[]}"#), false)
        XCTAssertEqual(AsideCLI.parseWindowOpen("PROFILE\tLABEL\tSTATUS\n1982ce5a\tProfile 0\tdisconnected"), false)
        XCTAssertEqual(AsideCLI.parseWindowOpen("PROFILE\tLABEL\tSTATUS\na\tProfile 0\tdisconnected\nb\tProfile 1\tconnected"), true)
        XCTAssertEqual(AsideCLI.parseWindowOpen("No browser profiles are connected or registered for this account on this host."), false)
        XCTAssertNil(AsideCLI.parseWindowOpen("Error: something else"))
        XCTAssertNil(AsideCLI.parseWindowOpen(""))
    }

    func testVersionCompare() throws {
        XCTAssertTrue(AsideCLI.isNewer("1.26.1107.24", than: "1.26.1022.3"))
        XCTAssertTrue(AsideCLI.isNewer("1.27", than: "1.26.1107.24"))
        XCTAssertFalse(AsideCLI.isNewer("1.26.1107.24", than: "1.26.1107.24"))
        XCTAssertFalse(AsideCLI.isNewer("1.26", than: "1.26.0.1"))
        XCTAssertFalse(AsideCLI.isNewer("", than: "1.26"))
        XCTAssertFalse(AsideCLI.isNewer("1.27", than: ""))
        XCTAssertFalse(AsideCLI.isNewer("canary", than: "1.26"))

        let home = FileManager.default.temporaryDirectory.appendingPathComponent("aside-ver-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertEqual(AsideCLI.latestVersion(home: home), "")
        let cli = home.appendingPathComponent(".aside/cli")
        try FileManager.default.createDirectory(at: cli, withIntermediateDirectories: true)
        try Data(#"{"checkedAt":1,"latestVersion":"1.27.1.0"}"#.utf8).write(to: cli.appendingPathComponent("update-check.json"))
        XCTAssertEqual(AsideCLI.latestVersion(home: home), "1.27.1.0")
    }

    /// 가짜 aside 로 한 번에 살펴보기: 지금 CLI 와, 옵션이 없는 구버전.
    func testProbe() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aside-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func fake(_ name: String, _ body: String) throws -> String {
            let exe = dir.appendingPathComponent(name)
            try Data(("#!/bin/sh\n" + body).utf8).write(to: exe)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
            return exe.path
        }

        let current = try fake("aside", #"""
        case "$*" in
          "--version") echo "1.26.1107.24" ;;
          "exec --help") echo "  --permission <MODE>  Session permission: ask/guard" ;;
          "account status --json") echo '{"account":{"id":3,"email":"me@x.com","mode":"cloud","authStatus":"active","hasSession":true,"subscriptionPlan":"pro"}}' ;;
          "account list --json") echo '{"currentAccountId":3,"accounts":[{"id":3,"email":"me@x.com"},{"id":4,"email":"other@x.com","mode":"cloud","authStatus":"active","hasSession":true}]}' ;;
          "host profiles --json") echo '{"host":"local","profiles":[{"profileId":"p","label":"Profile 0","connected":false}]}' ;;
          *) echo "unexpected: $*" >&2; exit 2 ;;
        esac
        """#)
        let p = AsideCLI.probe(executable: current, source: "설정 경로", home: dir)
        XCTAssertEqual(p, AsideProbe(path: current, source: "설정 경로", version: "1.26.1107.24", latestVersion: "", runnable: true,
                                     account: .signedIn(email: "me@x.com", accountId: 3, plan: "pro"),
                                     otherAccounts: [AsideAccount(id: 4, title: "other@x.com", signedIn: true)], windowOpen: false))
        XCTAssertFalse(p.updateAvailable)

        // 구버전: exec 에 --permission 이 없고 --json 을 모른다
        let old = try fake("aside-old", #"""
        for a in "$@"; do [ "$a" = "--json" ] && { echo "error: unknown option '--json'" >&2; exit 1; }; done
        case "$*" in
          "--version") echo "1.20.0" ;;
          "exec --help") echo "Usage: aside exec [options] [prompt...]" ;;
          "account status") echo "* u0  old@x.com  signed in  profiles: Profile 0" ;;
          "host profiles") echo "error: unknown command 'host'" >&2; exit 1 ;;
          *) exit 2 ;;
        esac
        """#)
        let o = AsideCLI.probe(executable: old)
        XCTAssertEqual(o.version, "1.20.0")
        XCTAssertFalse(o.runnable)
        XCTAssertEqual(o.account, .signedIn(email: "old@x.com", accountId: 0, plan: ""))
        XCTAssertEqual(o.otherAccounts, [])
        XCTAssertNil(o.windowOpen)

        XCTAssertNil(AsideCLI.useAccount(executable: try fake("aside-use", #"[ "$*" = "account use u4" ] || exit 1"#), id: 4))
        XCTAssertEqual(AsideCLI.useAccount(executable: try fake("aside-nouse", "echo 'Account not found: u9' >&2; exit 1"), id: 9),
                       "계정을 바꾸지 못했어요 · Account not found: u9")
    }

    // MARK: - 준비 항목

    func testNothingInstalled() {
        let items = E2ESetup.items(E2ESetupInput(browserInstalled: false, probe: nil))
        XCTAssertEqual(items.map(\.kind), [.browser, .cli, .account])
        XCTAssertEqual(states(items), [.todo, .waiting, .waiting])
        XCTAssertEqual(E2ESetup.blocker(items)?.fixes, [.downloadBrowser])
    }

    func testCLIMissingOrOutdated() {
        let missing = E2ESetup.items(E2ESetupInput(browserInstalled: true, browserVersion: "1.0.1", probe: nil))
        XCTAssertEqual(states(missing), [.ok, .todo, .waiting])
        XCTAssertEqual(item(missing, .browser)?.detail, "설치됨 · 1.0.1")
        XCTAssertEqual(E2ESetup.blocker(missing)?.fixes, [.installCLI])

        let old = E2ESetup.items(E2ESetupInput(browserInstalled: true,
                                               probe: AsideProbe(path: "/a", version: "1.20.0", runnable: false, account: signedIn)))
        XCTAssertEqual(E2ESetup.blocker(old)?.kind, .cli)
        XCTAssertEqual(E2ESetup.blocker(old)?.fixes, [.updateCLI])
        XCTAssertTrue(E2ESetup.blocker(old)?.detail.contains("1.20.0") == true)

        // 새 버전이 있어도 돌릴 수 있으면 막지 않고 버튼만 준다
        let update = E2ESetup.items(E2ESetupInput(browserInstalled: true, probe: AsideProbe(
            path: "/a", version: "1.26.1", latestVersion: "1.27.0", account: signedIn, windowOpen: true)))
        XCTAssertNil(E2ESetup.blocker(update))
        XCTAssertFalse(update.contains(where: \.needsAttention))
        XCTAssertEqual(item(update, .cli)?.fixes, [.updateCLI])
        XCTAssertTrue(item(update, .cli)?.detail.contains("1.27.0") == true)

        // 브라우저 앱 위치를 못 찾아도 CLI 가 있으면 막지 않는다
        let moved = E2ESetup.items(E2ESetupInput(browserInstalled: false, probe: AsideProbe(path: "/a", account: signedIn)))
        XCTAssertNil(E2ESetup.blocker(moved))
    }

    func testAccountStates() {
        func account(_ status: AsideAccountStatus, others: [AsideAccount] = []) -> E2ESetupItem? {
            item(E2ESetup.items(E2ESetupInput(browserInstalled: true,
                                              probe: AsideProbe(path: "/a", account: status, otherAccounts: others))), .account)
        }
        let ok = account(signedIn)
        XCTAssertEqual(ok?.state, .ok)
        XCTAssertEqual(ok?.detail, "me@x.com (u0)")
        XCTAssertEqual(ok?.fixes, [])

        // 로그인은 Aside 브라우저에서 한다. 터미널 로그인을 시키지 않는다.
        let never = account(.signedOut(who: "", reason: .never))
        XCTAssertEqual(never?.state, .todo)
        XCTAssertEqual(never?.fixes, [.openAside])
        XCTAssertTrue(never?.steps.contains { $0.contains("설정(⌘,) > 계정") } == true)
        XCTAssertTrue(account(.signedOut(who: "me@x.com", reason: .noSession))?.detail.contains("me@x.com") == true)
        XCTAssertTrue(account(.signedOut(who: "me@x.com", reason: .paused("device_mismatch")))?.detail.contains("기기 정보") == true)

        // 지금 계정은 로그아웃인데 다른 계정이 로그인돼 있으면 알려 주고 바꿀 수 있게 한다
        let others = [AsideAccount(id: 1, title: "work@x.com", signedIn: true), AsideAccount(id: 2, title: "old@x.com", signedIn: false)]
        let mismatch = account(.signedOut(who: "me@x.com", reason: .noSession), others: others)
        XCTAssertEqual(mismatch?.fixes, [.openAside, .switchAccount(id: 1, title: "work@x.com")])
        XCTAssertTrue(mismatch?.note.contains("work@x.com") == true)
        XCTAssertFalse(mismatch?.note.contains("old@x.com") == true)

        // 계정이 여러 개면 어느 계정으로 도는지 알려 준다 (막지는 않는다)
        let many = account(signedIn, others: others)
        XCTAssertEqual(many?.state, .ok)
        XCTAssertTrue(many?.note.contains("3개") == true)
        XCTAssertEqual(many?.fixes, [.switchAccount(id: 1, title: "work@x.com")])

        let unknown = account(.unknown("aside 응답 없음 (15초)"))
        XCTAssertEqual(unknown?.state, .todo)
        XCTAssertEqual(unknown?.fixes, [.openAside, .updateCLI])
    }

    func testWindowAndEnvironment() {
        func items(window: Bool?, url: String = "https://st.example.com", user: String = "", login: E2ELoginHistory = .none)
            -> [E2ESetupItem] {
            E2ESetup.items(E2ESetupInput(browserInstalled: true, probe: AsideProbe(path: "/a", account: signedIn, windowOpen: window),
                                         env: .st, envURL: url, envUser: user, lastLogin: login))
        }
        // 창이 닫혀 있어도 실행할 때 열기 때문에 막지 않는다
        let closed = items(window: false, login: .ok)
        XCTAssertEqual(item(closed, .window)?.state, .warn)
        XCTAssertEqual(item(closed, .window)?.fixes, [.openAside])
        XCTAssertNil(E2ESetup.blocker(closed))
        XCTAssertNil(item(items(window: nil), .window), "확인하지 못했으면 줄을 넣지 않는다")

        let noURL = items(window: true, url: " ")
        XCTAssertEqual(E2ESetup.blocker(noURL)?.kind, .envURL)
        XCTAssertEqual(E2ESetup.blocker(noURL)?.fixes, [.openSettings])
        XCTAssertNil(item(noURL, .envLogin))

        let first = item(items(window: true, user: "qa"), .envLogin)
        XCTAssertEqual(first?.state, .info)
        XCTAssertEqual(first?.title, "ST 로그인")
        XCTAssertTrue(first?.steps.first?.contains("테스트 계정(qa)") == true)
        XCTAssertEqual(first?.fixes, [.openEnvironment])

        let blocked = item(items(window: true, login: .blocked(.vaultLocked)), .envLogin)
        XCTAssertEqual(blocked?.state, .warn)
        XCTAssertEqual(blocked?.steps, E2ELoginBlock.vaultLocked.steps(account: "테스트 계정"))

        let ready = items(window: true, login: .ok)
        XCTAssertFalse(ready.contains(where: \.needsAttention))

        // 환경을 주지 않으면 Aside 항목만
        let asideOnly = E2ESetup.items(E2ESetupInput(browserInstalled: true, probe: AsideProbe(path: "/a", account: signedIn, windowOpen: true)))
        XCTAssertEqual(asideOnly.map(\.kind), [.browser, .cli, .account, .window])
    }

    func testLoginHistoryUsesLatestRunOfSameEnvironment() {
        func entry(_ suffix: String, env: E2EEnv = .st, url: String = "https://st.example.com", block: E2ELoginBlock? = nil,
                   verdict: E2EVerdict = .pass) -> (job: E2EJob, result: E2EResult) {
            (E2EJob(id: "20261110100000-\(suffix)", env: env, baseUrl: url, username: "", issues: [], status: .done),
             E2EResult(loginBlocked: block, issues: [E2EIssueResult(key: "A-1", reportedVerdict: verdict)]))
        }
        let url = "https://st.example.com"
        XCTAssertEqual(E2ELoginHistory.latest(env: .st, baseUrl: url, finished: []), .none)
        XCTAssertEqual(E2ELoginHistory.latest(env: .st, baseUrl: url, finished: [entry("a")]), .ok)
        // 최신순: 가장 최근 것이 막혔으면 막힌 것으로
        XCTAssertEqual(E2ELoginHistory.latest(env: .st, baseUrl: url, finished: [entry("b", block: .noSavedLogin, verdict: .blocked), entry("a")]),
                       .blocked(.noSavedLogin))
        XCTAssertEqual(E2ELoginHistory.latest(env: .st, baseUrl: url, finished: [entry("b"), entry("a", block: .vaultLocked)]), .ok)
        // 다른 환경·다른 주소의 결과는 보지 않는다
        XCTAssertEqual(E2ELoginHistory.latest(env: .st, baseUrl: url, finished: [entry("c", env: .dv), entry("d", url: "https://old.example.com")]), .none)
        // 로그인 문제가 아닌 이유로 전부 BLOCKED 면 알 수 없다
        XCTAssertEqual(E2ELoginHistory.latest(env: .st, baseUrl: url, finished: [entry("e", verdict: .blocked), entry("a")]), .none)
    }

    func testFixLabels() {
        XCTAssertEqual(E2ESetupFix.switchAccount(id: 1, title: "work@x.com").label, "work@x.com 계정으로 바꾸기")
        let all: [E2ESetupFix] = [.downloadBrowser, .installCLI, .updateCLI, .openAside, .openSettings, .openEnvironment]
        XCTAssertEqual(Set(all.map(\.label)).count, all.count)
        XCTAssertFalse(all.contains { $0.icon.isEmpty })
    }
}
