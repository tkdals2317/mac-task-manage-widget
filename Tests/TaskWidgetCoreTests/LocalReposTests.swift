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
}
