import XCTest
@testable import TaskWidgetCore

final class UpdaterTests: XCTestCase {
    func res(_ out: String = "", err: String = "", status: Int32 = 0) -> ProcessResult {
        ProcessResult(status: status, stdout: out, stderr: err, timedOut: false)
    }

    /// 인자에 포함된 git 하위 명령으로 응답을 고르는 가짜 runner. 호출된 인자도 기록.
    func updater(_ replies: [String: ProcessResult], calls: UnsafeMutablePointer<[[String]]>? = nil) -> Updater {
        Updater(sourceDir: "/src") { _, args, _ in
            calls?.pointee.append(args)
            for (k, v) in replies where args.contains(k) { return v }
            return ProcessResult(status: 0, stdout: "", stderr: "", timedOut: false)
        }
    }

    func testBuildInfoParsing() {
        let b = BuildInfo(infoDictionary: ["CFBundleShortVersionString": "1.0", "ATMBuildNumber": "57",
                                           "ATMCommit": "abc1234", "ATMBuildDate": "2026-10-07 10:00",
                                           "ATMSourceDir": "/x", "ATMDirty": "false"])
        XCTAssertEqual(b.displayVersion, "1.0 (빌드 57 · abc1234)")
        XCTAssertEqual(b.sourceDir, "/x")
        XCTAssertFalse(b.dirty)
    }

    func testBuildInfoDefaultsAndDirty() {
        let d = BuildInfo(infoDictionary: [:])
        XCTAssertEqual(d.buildNumber, "unknown")
        XCTAssertEqual(d.sourceDir, "")
        XCTAssertFalse(d.dirty)
        let b = BuildInfo(infoDictionary: ["CFBundleShortVersionString": "1.0", "ATMBuildNumber": "5",
                                           "ATMCommit": "c", "ATMDirty": "true"])
        XCTAssertEqual(b.displayVersion, "1.0 (빌드 5 · c) · 로컬 수정 포함")
    }

    func testCheckParsesBehindAndCommits() throws {
        var calls: [[String]] = []
        let u = updater(["--abbrev-ref": res("dev\n"), "--count": res("2\n"),
                         "--format=%h %s": res("bbb2 second\naaa1 first\n")], calls: &calls)
        let s = try u.check()
        XCTAssertEqual(s.behind, 2)
        XCTAssertEqual(s.newCommits, ["bbb2 second", "aaa1 first"])
        XCTAssertTrue(calls.contains { $0.contains("HEAD..origin/dev") })
    }

    func testDetachedHeadUsesMain() throws {
        var calls: [[String]] = []
        let u = updater(["--abbrev-ref": res("HEAD\n"), "--count": res("0\n")], calls: &calls)
        let s = try u.check()
        XCTAssertEqual(s.behind, 0)
        XCTAssertEqual(s.newCommits, [])
        XCTAssertTrue(calls.contains { $0.contains("HEAD..origin/main") })
    }

    func testNotARepo() {
        let u = updater(["--is-inside-work-tree": res(status: 128)])
        XCTAssertThrowsError(try u.check()) { XCTAssertEqual($0 as? UpdateError, .notARepo) }
    }

    func testNoSourceDir() {
        XCTAssertThrowsError(try Updater(sourceDir: "").check()) { XCTAssertEqual($0 as? UpdateError, .noSourceDir) }
    }

    func testFetchFailureCarriesStderr() {
        let u = updater(["fetch": res(err: "no network\n", status: 1)])
        XCTAssertThrowsError(try u.check()) { XCTAssertEqual($0 as? UpdateError, .fetchFailed("no network")) }
    }

    func testHasLocalChanges() throws {
        XCTAssertTrue(try updater(["status": res(" M a.swift\n")]).hasLocalChanges())
        XCTAssertFalse(try updater(["status": res("")]).hasLocalChanges())
    }

    func testUpdateScript() {
        let s = Updater.updateScript(sourceDir: "/Users/a b/task manager", logPath: "/L/Application Support/update.log")
        XCTAssertTrue(s.contains("git pull --ff-only"))
        XCTAssertTrue(s.contains("make install"))
        XCTAssertTrue(s.contains("open ~/Applications/ATM.app"))
        XCTAssertTrue(s.contains("cd '/Users/a b/task manager'"))
        XCTAssertTrue(s.contains(">> '/L/Application Support/update.log'"))
        XCTAssertTrue(s.contains("UPDATE_FAILED"))
    }

    func testRealGitReportsBehind() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ dir: String, _ args: [String]) {
            let r = ProcessRunner.run(executable: "/usr/bin/git", arguments: ["-C", dir] + args, timeout: 20)
            XCTAssertEqual(r.status, 0, r.stderr)
        }
        let bare = root.appendingPathComponent("bare.git").path
        let c1 = root.appendingPathComponent("c1").path, c2 = root.appendingPathComponent("c2").path
        try FileManager.default.createDirectory(atPath: root.path, withIntermediateDirectories: true)
        git(root.path, ["init", "-q", "--bare", "-b", "main", bare])
        git(root.path, ["clone", "-q", bare, c1])
        git(c1, ["config", "user.email", "t@t"]); git(c1, ["config", "user.name", "t"])
        try "a".write(toFile: c1 + "/a.txt", atomically: true, encoding: .utf8)
        git(c1, ["add", "."]); git(c1, ["commit", "-q", "-m", "init"]); git(c1, ["push", "-q", "origin", "HEAD:main"])
        git(root.path, ["clone", "-q", bare, c2])
        git(c2, ["config", "user.email", "t@t"]); git(c2, ["config", "user.name", "t"])
        try "b".write(toFile: c2 + "/b.txt", atomically: true, encoding: .utf8)
        git(c2, ["add", "."]); git(c2, ["commit", "-q", "-m", "feat: second"]); git(c2, ["push", "-q", "origin", "HEAD:main"])

        let s = try Updater(sourceDir: c1).check()
        XCTAssertEqual(s.behind, 1)
        XCTAssertTrue(s.newCommits[0].hasSuffix(" feat: second"), s.newCommits.description)
    }
}
