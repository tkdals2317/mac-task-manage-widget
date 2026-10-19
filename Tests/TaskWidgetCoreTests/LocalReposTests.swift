import XCTest
@testable import TaskWidgetCore

final class LocalReposTests: XCTestCase {
    var root: URL!
    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("localrepos-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func write(_ rel: String, _ text: String) {
        let u = root.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }
    func config(_ url: String) -> String {
        "[core]\n\tbare = false\n[remote \"upstream\"]\n\turl = git@bitbucket.org:other/zzz.git\n[remote \"origin\"]\n\turl = \(url)\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n"
    }

    func testFindsDirectChildGrandchildAndGitdirFile() {
        write("a/.git/config", config("git@bitbucket.org:midas/alpha.git"))
        write("group/b/.git/config", config("https://u@bitbucket.org/midas/beta.git"))
        write("other/.git/config", config("git@bitbucket.org:someone/gamma.git"))
        write("gh/.git/config", config("git@github.com:midas/delta.git"))
        // 워크트리 스타일: .git 이 파일, gitdir 이 실제 폴더를 가리킴
        write("real/store/config", config("git@bitbucket.org:midas/epsilon.git"))
        write("wt/.git", "gitdir: \(root.path)/real/store\n")
        // 너무 깊은 것은 무시
        write("x/y/z/.git/config", config("git@bitbucket.org:midas/deep.git"))
        let slugs = LocalRepos.bitbucketSlugs(workspace: "midas", roots: [root, root.appendingPathComponent("missing")])
        XCTAssertEqual(slugs, ["alpha", "beta", "epsilon"])
    }

    func testCountPerRoot() {
        write("one/a/.git/config", config("git@bitbucket.org:midas/alpha.git"))
        write("one/g/b/.git/config", config("git@bitbucket.org:midas/beta.git"))
        write("two/c/.git/config", config("git@bitbucket.org:other/gamma.git"))
        XCTAssertEqual(LocalRepos.count(workspace: "midas", root: root.appendingPathComponent("one")), 2)
        XCTAssertEqual(LocalRepos.count(workspace: "midas", root: root.appendingPathComponent("two")), 0)
        XCTAssertEqual(LocalRepos.count(workspace: "midas", root: root.appendingPathComponent("missing")), 0)
    }

    func testUniqueDirsMergesSameFolder() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = base.appendingPathComponent("Projects"), b = base.appendingPathComponent("dev")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let lower = base.appendingPathComponent("projects").path
        let caseInsensitive = FileManager.default.fileExists(atPath: lower)
        let r = LocalRepos.uniqueDirs([a.path, lower, b.path, b.path + "/"])
        XCTAssertEqual(r.count, caseInsensitive ? 2 : 3)
        XCTAssertEqual(r.first, a.path)
    }
}
