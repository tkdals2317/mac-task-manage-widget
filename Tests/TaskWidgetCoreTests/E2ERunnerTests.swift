import XCTest
@testable import TaskWidgetCore

/// 가짜 aside(Fixtures/fake-aside.sh)로 실행 관리 로직을 확인한다.
final class E2ERunnerTests: XCTestCase {
    var root: URL!
    var store: E2EJobStore!
    var runner: E2ERunner!
    let secret = "s3cr\"et!"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-run-\(UUID().uuidString)/jobs")
        store = E2EJobStore(root: root)
        runner = E2ERunner(store: store)
    }
    override func tearDownWithError() throws {
        runner.shutdown(timeout: 5)
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private var script: String {
        Bundle.module.url(forResource: "fake-aside", withExtension: "sh", subdirectory: "Fixtures")!.path
    }

    private func makeJob(_ suffix: String) throws -> E2EJob {
        let j = E2EJob(id: "20261109100000-\(suffix)", env: .st, baseUrl: "https://st.example.com", username: "qa",
                       issues: [E2EIssueRef(key: "ABC-1", url: "https://j/browse/ABC-1", title: "t")])
        try store.create(j)
        return j
    }

    private func options(_ mode: String, timeout: TimeInterval = 20, extra: [String: String] = [:],
                         stopSession: ((String) -> Void)? = nil) -> E2ERunOptions {
        var env = ProcessInfo.processInfo.environment
        env["FAKE_ASIDE_MODE"] = mode
        for (k, v) in extra { env[k] = v }
        return E2ERunOptions(executable: "/bin/bash", arguments: [script] + AsideCLI.execArguments(prompt: "PROMPT-BODY-7731"),
                             environment: env, timeout: timeout, password: secret, killGrace: 1, stopSession: stopSession)
    }

    private func run(_ suffix: String, _ o: E2ERunOptions) throws -> E2EJob {
        let j = try makeJob(suffix)
        runner.enqueue(j, options: o)
        XCTAssertTrue(runner.waitUntilIdle(timeout: 30), "끝나지 않음")
        return try XCTUnwrap(store.load(j.id))
    }

    private func assertNoSecretOnDisk(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: store.jobFile(id))) as? [String: Any]
        XCTAssertNil(obj?["password"], "job.json 에 password 가 남음", file: file, line: line)
        let perm = try FileManager.default.attributesOfItem(atPath: store.jobFile(id).path)[.posixPermissions] as? Int
        XCTAssertEqual(perm, 0o600, file: file, line: line)
        for name in try FileManager.default.contentsOfDirectory(atPath: store.dir(id).path) {
            let text = (try? String(contentsOf: store.dir(id).appendingPathComponent(name), encoding: .utf8)) ?? ""
            XCTAssertFalse(text.contains("s3cr"), "\(name) 에 비밀번호가 남음", file: file, line: line)
        }
    }

    private func waitUntil(_ timeout: TimeInterval, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return cond()
    }

    private func saw(_ id: String) -> String? {
        try? String(contentsOf: store.dir(id).appendingPathComponent("saw-password.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testSuccessWritesDoneAndRemovesPassword() throws {
        var updates: [E2EJobStatus] = []
        let lock = NSLock()
        runner.onUpdate = { j in lock.lock(); updates.append(j.status); lock.unlock() }
        let j = try run("succ", options("success"))
        XCTAssertEqual(j.status, .done)
        XCTAssertNil(j.error)
        XCTAssertEqual(j.sessionId, "fake-20261109100000-succ")
        XCTAssertNotNil(j.finishedAt)
        XCTAssertEqual(saw(j.id), "present", "실행 중에는 job.json 에 비밀번호가 있어야 함")
        guard case .ok(let r) = store.result(j.id) else { return XCTFail("결과 없음") }
        XCTAssertEqual(r.issues.first?.verdict, .pass)
        XCTAssertNotNil(store.screenshotURL(j.id, name: "ABC-1-1.png"))
        let log = try String(contentsOf: store.logFile(j.id), encoding: .utf8)
        XCTAssertTrue(log.contains("ABC-1 PASS"))
        XCTAssertTrue(log.contains("[err] created new session: fake-20261109100000-succ"))
        XCTAssertFalse(log.contains("PROMPT-BODY-7731"), "지시문 본문은 로그에 넣지 않는다")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.pidFile(j.id).path))
        try assertNoSecretOnDisk(j.id)
        lock.lock(); XCTAssertEqual(updates, [.running, .done]); lock.unlock()
    }

    func testPasswordPrintedByAsideIsMaskedInLog() throws {
        let j = try run("leak", options("leak"))
        XCTAssertEqual(j.status, .done)
        let log = try String(contentsOf: store.logFile(j.id), encoding: .utf8)
        XCTAssertTrue(log.contains("\"password\""))
        XCTAssertTrue(log.contains("****"))
        try assertNoSecretOnDisk(j.id)
    }

    func testNoPasswordWhenAccountEmpty() throws {
        var o = options("success")
        o.password = nil
        let j = try run("nopw", o)
        XCTAssertEqual(j.status, .done)
        XCTAssertEqual(saw(j.id), "absent")
    }

    func testFailureWithoutResultShowsHint() throws {
        let j = try run("fail", options("fail-login"))
        XCTAssertEqual(j.status, .failed)
        XCTAssertEqual(j.error, E2EFailureHint.hint(for: "not signed in"))
        try assertNoSecretOnDisk(j.id)
    }

    func testInvalidAndEmptyResultFail() throws {
        let a = try run("inva", options("invalid"))
        XCTAssertEqual(a.status, .failed)
        XCTAssertEqual(a.error, "result.json 을 읽지 못했어요 (JSON 형식이 아님)")
        try assertNoSecretOnDisk(a.id)
        let b = try run("empt", options("empty"))
        XCTAssertEqual(b.status, .failed)
        XCTAssertEqual(b.error, "result.json 에 이슈 결과가 없어요")
    }

    func testTimeoutKillsProcessTree() throws {
        let start = Date()
        let j = try run("hang", options("hang", timeout: 1))
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        XCTAssertEqual(j.status, .failed)
        XCTAssertEqual(j.error, "제한 시간 1분을 넘겨 멈췄어요")
        try assertNoSecretOnDisk(j.id)
        // bash 가 SIGTERM 으로 죽어도 손자 sleep 이 남지 않아야 한다
        let left = ProcessRunner.run(executable: "/usr/bin/pgrep", arguments: ["-f", "sleep 6123"], timeout: 5)
        XCTAssertEqual(left.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    func testStubbornProcessGetsKilledAndSessionStopped() throws {
        var stopped: [String] = []
        let lock = NSLock()
        let j = try run("stub", options("stubborn", timeout: 1, stopSession: { id in lock.lock(); stopped.append(id); lock.unlock() }))
        XCTAssertEqual(j.status, .failed)
        XCTAssertTrue(waitUntil(5) { lock.lock(); defer { lock.unlock() }; return !stopped.isEmpty })
        lock.lock(); XCTAssertEqual(stopped, ["fake-20261109100000-stub"]); lock.unlock()
        XCTAssertTrue(try String(contentsOf: store.logFile(j.id), encoding: .utf8).contains("SIGKILL"))
        try assertNoSecretOnDisk(j.id)
    }

    func testCancelRunningAndQueued() throws {
        let a = try makeJob("cana"), b = try makeJob("canb")
        runner.enqueue(a, options: options("hang"))
        runner.enqueue(b, options: options("success"))
        XCTAssertTrue(waitUntil(5) { self.runner.state.running == a.id })
        XCTAssertEqual(runner.state.queued, [b.id])
        runner.cancel(jobId: b.id)
        runner.cancel(jobId: a.id)
        XCTAssertTrue(runner.waitUntilIdle(timeout: 15))
        XCTAssertEqual(store.load(a.id)?.status, .cancelled)
        XCTAssertNil(store.load(a.id)?.error)
        XCTAssertEqual(store.load(b.id)?.status, .cancelled)
        XCTAssertNil(saw(b.id), "취소된 대기 job 은 실행되지 않는다")
        try assertNoSecretOnDisk(a.id)
        try assertNoSecretOnDisk(b.id)
    }

    func testQueueRunsOneAtATimeInOrder() throws {
        let order = root.deletingLastPathComponent().appendingPathComponent("order.txt")
        let a = try makeJob("quea"), b = try makeJob("queb")
        let extra = ["FAKE_ORDER_FILE": order.path, "FAKE_DELAY": "0.5"]
        runner.enqueue(a, options: options("success", extra: extra))
        runner.enqueue(b, options: options("success", extra: extra))
        XCTAssertTrue(runner.waitUntilIdle(timeout: 30))
        let lines = try String(contentsOf: order, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines, ["start \(a.id)", "end \(a.id)", "start \(b.id)", "end \(b.id)"])
        XCTAssertEqual(store.load(a.id)?.status, .done)
        XCTAssertEqual(store.load(b.id)?.status, .done)
    }

    func testShutdownStopsEverythingAndScrubs() throws {
        let a = try makeJob("shua"), b = try makeJob("shub")
        runner.enqueue(a, options: options("hang"))
        runner.enqueue(b, options: options("success"))
        XCTAssertTrue(waitUntil(5) { self.runner.state.running == a.id })
        runner.shutdown(timeout: 5)
        XCTAssertEqual(store.load(a.id)?.status, .cancelled)
        XCTAssertEqual(store.load(a.id)?.error, "ATM 을 종료해서 멈췄어요")
        XCTAssertEqual(store.load(b.id)?.status, .cancelled)
        try assertNoSecretOnDisk(a.id)
        try assertNoSecretOnDisk(b.id)
    }

    func testMissingExecutableFails() throws {
        var o = options("success")
        o.executable = "/nonexistent/aside"
        let j = try run("miss", o)
        XCTAssertEqual(j.status, .failed)
        XCTAssertTrue(j.error?.hasPrefix("aside 를 실행하지 못했어요") == true, j.error ?? "")
        try assertNoSecretOnDisk(j.id)
    }

    func testOutcomeRules() {
        let ok = E2EResultLoad.ok(E2EResult(issues: [E2EIssueResult(key: "A-1", reportedVerdict: .pass)]))
        XCTAssertEqual(E2ERunner.outcome(cancelled: true, cancelReason: nil, timedOut: false, timeout: 60, result: ok, exitCode: 0, output: "").0, .cancelled)
        XCTAssertEqual(E2ERunner.outcome(cancelled: false, cancelReason: nil, timedOut: true, timeout: 600, result: ok, exitCode: 15, output: "").0, .done)
        let t = E2ERunner.outcome(cancelled: false, cancelReason: nil, timedOut: true, timeout: 600, result: .invalid("x"), exitCode: 15, output: "")
        XCTAssertEqual(t.1, "제한 시간 10분을 넘겨 멈췄어요")
        let m = E2ERunner.outcome(cancelled: false, cancelReason: nil, timedOut: false, timeout: 60, result: .missing, exitCode: 0,
                                  output: "I couldn't write\n마지막 줄\n\n")
        XCTAssertEqual(m.0, .failed)
        XCTAssertEqual(m.1, "결과 파일(result.json)이 없어요 (exit 0) · 마지막 줄")
    }

    func testAsideHelpers() {
        XCTAssertEqual(AsideCLI.sessionId(in: "created new session: pltnf6d7zRGoVm6U"), "pltnf6d7zRGoVm6U")
        XCTAssertNil(AsideCLI.sessionId(in: "Error This operation was aborted"))
        XCTAssertEqual(AsideCLI.execArguments(prompt: "p"), ["exec", "--permission", "full-access", "p"])
        XCTAssertEqual(AsideCLI.execArguments(prompt: "p", model: " claude-sonnet-5 "),
                       ["exec", "--permission", "full-access", "--model", "claude-sonnet-5", "p"])
        XCTAssertEqual(E2EFailureHint.hint(for: "Error Requested model claude-code/x is not available for this account."),
                       "고른 모델을 이 Aside 계정에서 쓸 수 없어요 · E2E 탭 실행 버튼 옆에서 다른 모델을 고르세요")
        let env = AsideCLI.environment(executable: "/x/bin/aside", base: ["PATH": "/usr/bin"], home: "/h")
        XCTAssertEqual(env["PATH"], "/x/bin:/h/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin")
        XCTAssertEqual(env["CI"], "1")

        let signedIn = #"{"account":{"id":1,"email":"me@x.com","authStatus":"active","hasSession":true,"subscriptionPlan":"free"}}"#
        XCTAssertEqual(AsideCLI.parseAccountStatus(stdout: signedIn, exitCode: 0), .signedIn(email: "me@x.com", accountId: 1, plan: "free"))
        let noPlan = #"{"account":{"name":"Me","authStatus":"active"}}"#
        XCTAssertEqual(AsideCLI.parseAccountStatus(stdout: noPlan, exitCode: 0), .signedIn(email: "Me", accountId: 0, plan: ""))
        let expired = #"{"account":{"email":"me@x.com","authStatus":"expired","hasSession":false}}"#
        XCTAssertEqual(AsideCLI.parseAccountStatus(stdout: expired, exitCode: 0), .signedOut)
        XCTAssertEqual(AsideCLI.parseAccountStatus(stdout: #"{"account":null}"#, exitCode: 0), .signedOut)
        XCTAssertEqual(AsideCLI.parseAccountStatus(stdout: "Not signed in. Run aside login", exitCode: 1), .signedOut)
        if case .unknown = AsideCLI.parseAccountStatus(stdout: "boom", exitCode: 2) {} else { XCTFail("unknown 이어야 함") }

        XCTAssertFalse(AsideCLI.isAsideProcess(getpid()))
        XCTAssertFalse(AsideCLI.isAsideProcess(0))
    }

    func testParseModelCatalog() throws {
        let raw = #"""
        {"[\"models\",\"provider-catalog\",\"openai\"]": {"value": {"models": [{"id": "gpt-4"}]}},
         "[\"models\",\"aside-catalog\"]": {"value": {"etag": "x", "models": [
            {"id": "claude-sonnet-5", "name": "Claude Sonnet 5.5", "minPlan": "free", "extra": 1},
            {"id": "claude-opus-5-5", "name": "Claude Opus 5.5", "minPlan": "pro"},
            {"id": "bare"}, {"id": ""}]}, "updatedAt": 1}}
        """#
        let models = AsideCLI.parseModels(Data(raw.utf8))
        XCTAssertEqual(models.map(\.id), ["claude-sonnet-5", "claude-opus-5-5", "bare"])
        XCTAssertEqual(models.map(\.needsPaidPlan), [false, true, false])
        XCTAssertEqual(models.last?.name, "bare")
        XCTAssertEqual(AsideCLI.parseModels(Data("{}".utf8)), [])
        XCTAssertEqual(AsideCLI.parseModels(Data("nope".utf8)), [])

        let home = root.deletingLastPathComponent()
        let file = AsideCLI.modelsFile(accountId: 2, home: home)
        XCTAssertTrue(file.path.hasSuffix(".aside/u/2/cache/models.json"))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(raw.utf8).write(to: file)
        XCTAssertEqual(AsideCLI.models(accountId: 2, home: home).count, 3)
        XCTAssertEqual(AsideCLI.models(accountId: 9, home: home), [])
    }

    func testParseConnectedProviderModels() throws {
        let raw = #"""
        {"providers": {
          "openai-codex": {"accountModelCatalog": {"credentialFingerprint": "x", "modelIds": ["gpt-6-luna", "gpt-6-luna", ""]}},
          "claude-code": {"accountModelCatalog": {"scopes": {"h1": {"modelIds": ["claude-sonnet-5-5", "claude-opus-5-5"]}}}},
          "empty": {}
        }}
        """#
        let models = AsideCLI.parseConnectedModels(Data(raw.utf8), names: ["claude-sonnet-5-5": "Claude Sonnet 5.5"])
        XCTAssertEqual(models.map(\.id), ["claude-code/claude-sonnet-5-5", "claude-code/claude-opus-5-5", "openai-codex/gpt-6-luna"])
        XCTAssertEqual(models.map(\.provider), ["claude-code", "claude-code", "openai-codex"])
        XCTAssertEqual(models.first?.name, "Claude Sonnet 5.5 · claude-code")
        XCTAssertEqual(models[1].name, "claude-opus-5-5 · claude-code", "이름을 모르면 id")
        XCTAssertFalse(models.contains { $0.needsPaidPlan })
        XCTAssertEqual(AsideCLI.parseConnectedModels(Data("{}".utf8)), [])
        XCTAssertEqual(AsideCLI.parseConnectedModels(Data("nope".utf8)), [])

        // models() 는 Aside 제공 + 연동 모델을 합친다
        let home = root.deletingLastPathComponent()
        let u = home.appendingPathComponent(".aside/u/3")
        try FileManager.default.createDirectory(at: u.appendingPathComponent("cache"), withIntermediateDirectories: true)
        try Data(raw.utf8).write(to: u.appendingPathComponent("models.json"))
        try Data(#"{"[\"models\",\"aside-catalog\"]": {"value": {"models": [{"id": "gpt-6.1-sol", "name": "GPT-6.1 Sol", "minPlan": "free"}]}}}"#.utf8)
            .write(to: u.appendingPathComponent("cache/models.json"))
        let all = AsideCLI.models(accountId: 3, home: home)
        XCTAssertEqual(all.first?.provider, "aside")
        XCTAssertEqual(all.count, 4)
    }

    func testLocateAside() throws {
        let home = root.deletingLastPathComponent()
        let bin = home.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let exe = bin.appendingPathComponent("aside")
        try "#!/bin/sh\n".write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        XCTAssertEqual(AsideCLI.locateWithSource(configured: "", home: home, shellLookup: { nil })?.source, "기본 위치")
        XCTAssertEqual(AsideCLI.locateWithSource(configured: exe.path, home: home, shellLookup: { nil })?.source, "설정 경로")
        XCTAssertEqual(AsideCLI.locateWithSource(configured: "", home: home, shellLookup: { "/bin/sh" })?.path, "/bin/sh")
        XCTAssertNil(AsideCLI.locateWithSource(configured: "/nope", home: home.appendingPathComponent("x"), shellLookup: { "relative" }))
    }

    func testPromptHasJobDirAndSchema() {
        let p = E2EPrompt.render(jobDir: URL(fileURLWithPath: "/tmp/a b/jobs/1", isDirectory: true))
        XCTAssertTrue(p.contains("/tmp/a b/jobs/1/job.json"))
        XCTAssertTrue(p.contains("/tmp/a b/jobs/1/result.json"))
        XCTAssertTrue(p.contains("\"verdict\": \"PASS|FAIL|BLOCKED|SKIPPED\""))
        XCTAssertFalse(p.contains("{JOB_DIR}"))
        XCTAssertFalse(p.contains("{SCHEMA}"))
    }
}
