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
        XCTAssertEqual(ClaudeRunner.locate(configured: custom.path, home: dir), custom.path)
    }

    func testLocateFallsBackToHomeLocalBin() throws {
        let local = dir.appendingPathComponent(".local/bin/claude")
        try makeExecutable(local, script: "#!/bin/sh\necho x\n")
        XCTAssertEqual(ClaudeRunner.locate(configured: "/nonexistent/claude", home: dir), local.path)
    }

    func testLocateSkipsNonExecutable() throws {
        let local = dir.appendingPathComponent(".local/bin/claude")
        try "not exec".write(to: local, atomically: true, encoding: .utf8)
        // 홈에 실행 파일이 없으면 시스템 경로로 넘어간다 (이 머신에 claude 가 있을 수 있으므로 local 이 아닌 것만 확인)
        XCTAssertNotEqual(ClaudeRunner.locate(configured: "", home: dir), local.path)
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

    func testNotFound() {
        XCTAssertThrowsError(try ClaudeRunner(configuredPath: "/nonexistent/claude").runLocated(prompt: "x", home: dir, workingDirectory: dir)) { e in
            XCTAssertEqual(e as? SummaryError, .claudeNotFound)
        }
    }

    func testUserMessages() {
        XCTAssertEqual(SummaryError.claudeNotFound.userMessage, "claude CLI 없음. 설정에서 경로 지정")
        XCTAssertEqual(SummaryError.timeout.userMessage, "claude 응답 시간 초과")
        XCTAssertEqual(SummaryError.claudeFailed(2, "a\nlast line\n").userMessage, "claude 실패 (exit 2): last line")
        XCTAssertEqual(SummaryError.emptyOutput.userMessage, "claude 출력이 비어 있음")
        XCTAssertEqual(SummaryError.busy.userMessage, "이미 생성 중")
    }
}
