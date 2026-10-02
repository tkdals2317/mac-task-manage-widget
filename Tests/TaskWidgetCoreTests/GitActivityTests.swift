import XCTest
@testable import TaskWidgetCore

final class GitActivityTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func git(_ args: [String]) {
        let r = ProcessRunner.run(executable: "/usr/bin/git", arguments: ["-C", dir.path] + args, timeout: 10)
        XCTAssertEqual(r.status, 0, r.stderr)
    }

    func testNonGitDirectoryIsEmpty() {
        XCTAssertEqual(GitActivity.commits(in: dir.path, on: Date()), [])
    }

    func testMissingDirectoryIsEmpty() {
        XCTAssertEqual(GitActivity.commits(in: "/nonexistent/path", on: Date()), [])
    }

    func testTodayCommitListed() throws {
        git(["init", "-q"])
        git(["config", "user.email", "t@t"])  // author 필터가 이 값을 쓰므로 전역 설정에 의존하지 않게 고정
        try "a".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        git(["add", "."])
        git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "feat: first commit"])
        let lines = GitActivity.commits(in: dir.path, on: Date())
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].hasSuffix(" feat: first commit"), lines[0])
    }

    func testAuthorFilter() throws {
        git(["init", "-q"])
        git(["config", "user.email", "me@test"])
        for (name, email) in [("mine", "me@test"), ("theirs", "other@test")] {
            try name.write(to: dir.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
            git(["add", "."])
            git(["-c", "user.name=t", "-c", "user.email=\(email)", "commit", "-q", "-m", "by \(name)"])
        }
        let lines = GitActivity.commits(in: dir.path, on: Date())
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].hasSuffix(" by mine"), lines[0])
    }

    func testYesterdayExcluded() throws {
        git(["init", "-q"])
        git(["config", "user.email", "t@t"])  // author 필터가 이 값을 쓰므로 전역 설정에 의존하지 않게 고정
        try "a".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        git(["add", "."])
        git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "old"])
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertEqual(GitActivity.commits(in: dir.path, on: yesterday), [])
    }
}
