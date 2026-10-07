import XCTest
@testable import TaskWidgetCore

final class ClaudeRunnerTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".local/bin"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func makeExecutable(_ url: URL, script: String) throws {
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func testLocatePrefersConfiguredPath() throws {
        let custom = dir.appendingPathComponent("my-claude")
        try makeExecutable(custom, script: "#!/bin/sh\necho x\n")
        let other = dir.appendingPathComponent(".local/bin/claude")
        try makeExecutable(other, script: "#!/bin/sh\n")
        XCTAssertEqual(ClaudeRunner.locate(configured: custom.path, home: dir, shellLookup: { other.path }), custom.path)
    }

    func testLocateFallsBackToHomeLocalBin() throws {
        let local = dir.appendingPathComponent(".local/bin/claude")
        try makeExecutable(local, script: "#!/bin/sh\necho x\n")
        XCTAssertEqual(ClaudeRunner.locate(configured: "/nonexistent/claude", home: dir, shellLookup: { nil }), local.path)
    }

    func testLocateSkipsNonExecutable() throws {
        let local = dir.appendingPathComponent(".local/bin/claude")
        try "not exec".write(to: local, atomically: true, encoding: .utf8)
        XCTAssertNotEqual(ClaudeRunner.locate(configured: "", home: dir, shellLookup: { nil }), local.path)
    }

    func testRunPassesPromptOnStdinAndReturnsStdout() throws {
        let fake = dir.appendingPathComponent("claude")
        try makeExecutable(fake, script: "#!/bin/sh\n# 인자 확인 후 stdin 을 그대로 출력\ncase \"$*\" in *'-p --output-format text --tools  --strict-mcp-config --no-session-persistence'*) ;; *) echo bad-args 1>&2; exit 9;; esac\ncat\n")
        let out = try ClaudeRunner(configuredPath: fake.path).run(prompt: "hello prompt", workingDirectory: dir)
        XCTAssertEqual(out, "hello prompt")
    }

    func testRunAddsModelFlag() throws {
        let fake = dir.appendingPathComponent("claude")
        try makeExecutable(fake, script: "#!/bin/sh\necho \"$*\"\n")
        let out = try ClaudeRunner(configuredPath: fake.path, model: "claude-sonnet-5-5").run(prompt: "x", workingDirectory: dir)
        XCTAssertEqual(out, "-p --output-format text --tools  --strict-mcp-config --no-session-persistence --model claude-sonnet-5-5")
    }

    func testRunRemovesNestingEnv() throws {
        let fake = dir.appendingPathComponent("claude")
        try makeExecutable(fake, script: "#!/bin/sh\necho \"CLAUDECODE=${CLAUDECODE:-unset} ENTRY=${CLAUDE_CODE_ENTRYPOINT:-unset}\"\n")
        let runner = ClaudeRunner(configuredPath: fake.path,
                                  baseEnvironment: ["CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli", "PATH": "/usr/bin:/bin"])
        let out = try runner.run(prompt: "x", workingDirectory: dir)
        XCTAssertEqual(out, "CLAUDECODE=unset ENTRY=unset")
    }

    func testRunFailures() throws {
        let fake = dir.appendingPathComponent("claude")
        try makeExecutable(fake, script: "#!/bin/sh\necho boom 1>&2\nexit 2\n")
        XCTAssertThrowsError(try ClaudeRunner(configuredPath: fake.path).run(prompt: "x", workingDirectory: dir)) { e in
            XCTAssertEqual(e as? SummaryError, .claudeFailed(2, "boom\n"))
        }
        try makeExecutable(fake, script: "#!/bin/sh\nexit 0\n")
        XCTAssertThrowsError(try ClaudeRunner(configuredPath: fake.path).run(prompt: "x", workingDirectory: dir)) { e in
            XCTAssertEqual(e as? SummaryError, .emptyOutput)
        }
        try makeExecutable(fake, script: "#!/bin/sh\nsleep 5\n")
        XCTAssertThrowsError(try ClaudeRunner(configuredPath: fake.path, timeout: 0.3).run(prompt: "x", workingDirectory: dir)) { e in
            XCTAssertEqual(e as? SummaryError, .timeout)
        }
    }

    func testFailureMessageFallsBackToStdout() throws {
        let fake = dir.appendingPathComponent("claude")
        try makeExecutable(fake, script: "#!/bin/sh\necho \"out-line\"\nexit 2\n")
        XCTAssertThrowsError(try ClaudeRunner(configuredPath: fake.path).run(prompt: "x", workingDirectory: dir)) { e in
            XCTAssertEqual(e as? SummaryError, .claudeFailed(2, "out-line\n"))
        }
    }

    // MARK: locate

    @discardableResult
    func fake(_ rel: String) throws -> String {
        let u = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeExecutable(u, script: "#!/bin/sh\necho x\n")
        return u.path
    }
    func find(_ configured: String = "", shell: String? = nil) -> (path: String, source: String)? {
        ClaudeRunner.locateWithSource(configured: configured, home: dir, shellLookup: { shell })
    }

    func testConfiguredDirectoryRejected() throws {
        let sh = try fake("sh/claude")
        let r = find(dir.path, shell: sh)
        XCTAssertEqual(r?.path, sh)
        XCTAssertEqual(r?.source, "로그인 셸")
    }

    func testConfiguredBeatsShell() throws {
        let c = try fake("mine/claude"), sh = try fake("sh/claude")
        let r = find(c, shell: sh)
        XCTAssertEqual(r?.path, c)
        XCTAssertEqual(r?.source, "설정 경로")
    }

    func testShellLookupGarbageIgnored() throws {
        let nonExec = dir.appendingPathComponent("noexec")
        try "x".write(to: nonExec, atomically: true, encoding: .utf8)
        for bad in ["claude: aliased to foo", "relative/claude", nonExec.path, dir.path] {
            let r = find(shell: bad)
            XCTAssertTrue(r == nil || r!.source != "로그인 셸", bad)
        }
    }

    func testKnownPathOrder() throws {
        let npm = try fake(".npm-global/bin/claude")
        XCTAssertEqual(find()?.path, npm)
        let local = try fake(".local/bin/claude")
        XCTAssertEqual(find()?.path, local)
        XCTAssertEqual(find()?.source, "기본 위치")
    }

    func testNvmNewestWins() throws {
        try fake(".nvm/versions/node/v18.19.0/bin/claude")
        try fake(".nvm/versions/node/v20.9.0/bin/claude")
        let newest = try fake(".nvm/versions/node/v20.11.0/bin/claude")
        let r = find()
        XCTAssertEqual(r?.path, newest)
        XCTAssertEqual(r?.source, "nvm")
    }

    func testDesktopEmbeddedNewestVersion() throws {
        try fake("Library/Application Support/Claude/claude-code/2.1.9/claude.app/Contents/MacOS/claude")
        let newest = try fake("Library/Application Support/Claude/claude-code/2.1.10/claude.app/Contents/MacOS/claude")
        let r = find()
        XCTAssertEqual(r?.path, newest)
        XCTAssertEqual(r?.source, "Claude 데스크톱 앱")
    }

    func testNothingUnderHomeIsNotFound() {
        // 시스템 경로(/opt/homebrew 등)에 실제 claude 가 있을 수 있어, 임시 홈 기반 결과가 없다는 것만 본다.
        let r = find()
        XCTAssertTrue(r == nil || !r!.path.hasPrefix(dir.path))
    }

    func testRunPathIncludesBinaryDir() throws {
        let bin = dir.appendingPathComponent("custom/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let fake = bin.appendingPathComponent("claude")
        try makeExecutable(fake, script: "#!/bin/sh\necho \"$PATH\"\n")
        let out = try ClaudeRunner(configuredPath: fake.path, baseEnvironment: ["PATH": "/usr/bin:/bin"]).run(prompt: "x", workingDirectory: dir)
        XCTAssertTrue(out.hasPrefix(bin.path + ":"), out)
    }

    func testNotFound() {
        XCTAssertThrowsError(try ClaudeRunner(configuredPath: "/nonexistent/claude").runLocated(prompt: "x", home: dir, workingDirectory: dir, shellLookup: { nil })) { e in
            XCTAssertEqual(e as? SummaryError, .claudeNotFound)
        }
    }

    func testUserMessages() {
        XCTAssertEqual(SummaryError.claudeNotFound.userMessage, "claude CLI를 찾지 못했습니다. 터미널에서 `command -v claude` 결과를 설정 > 요약 > claude 경로에 넣어주세요.")
        XCTAssertEqual(SummaryError.timeout.userMessage, "claude 응답 시간 초과")
        XCTAssertEqual(SummaryError.claudeFailed(2, "a\nlast line\n").userMessage, "claude 실패 (exit 2): last line")
        XCTAssertEqual(SummaryError.emptyOutput.userMessage, "claude 출력이 비어 있음")
        XCTAssertEqual(SummaryError.busy.userMessage, "이미 생성 중")
    }
}
