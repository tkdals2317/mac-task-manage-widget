import XCTest
@testable import TaskWidgetCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesStdout() {
        let r = ProcessRunner.run(executable: "/bin/echo", arguments: ["hi"], timeout: 5)
        XCTAssertEqual(r.status, 0)
        XCTAssertEqual(r.stdout, "hi\n")
        XCTAssertFalse(r.timedOut)
    }

    func testPassesStdin() {
        let r = ProcessRunner.run(executable: "/bin/cat", arguments: [], stdin: "abc\n한글", timeout: 5)
        XCTAssertEqual(r.stdout, "abc\n한글")
    }

    func testLargeStdinDoesNotDeadlock() {
        let big = String(repeating: "x", count: 300_000)
        let r = ProcessRunner.run(executable: "/bin/cat", arguments: [], stdin: big, timeout: 10)
        XCTAssertEqual(r.stdout.count, 300_000)
    }

    func testTimeout() {
        let r = ProcessRunner.run(executable: "/bin/sleep", arguments: ["5"], timeout: 0.3)
        XCTAssertTrue(r.timedOut)
    }

    func testTimeoutKillsChildThatIgnoresSIGTERM() {
        let start = Date()
        let r = ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "trap '' TERM; sleep 30"], timeout: 0.3)
        XCTAssertTrue(r.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 6, "SIGKILL 폴백으로 수 초 내 반환")
    }

    func testTimeoutWithChildThatNeverReadsStdin() {
        let big = String(repeating: "x", count: 200_000)
        let start = Date()
        let r = ProcessRunner.run(executable: "/bin/sleep", arguments: ["30"], stdin: big, timeout: 0.3)
        XCTAssertTrue(r.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "stdin 을 안 읽는 자식도 timeout 으로 묶인다")
    }

    func testNonZeroExitAndStderr() {
        let r = ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "echo err 1>&2; exit 3"], timeout: 5)
        XCTAssertEqual(r.status, 3)
        XCTAssertEqual(r.stderr, "err\n")
    }

    func testMissingExecutable() {
        let r = ProcessRunner.run(executable: "/nonexistent/bin", arguments: [], timeout: 5)
        XCTAssertEqual(r.status, -1)
    }
}
