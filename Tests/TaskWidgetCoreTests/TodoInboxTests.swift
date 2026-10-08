import XCTest
@testable import TaskWidgetCore

final class TodoInboxTests: XCTestCase {
    var dir: URL!
    let cfg = TagConfig(groups: [
        TagGroup(id: "g", name: "중요도", selection: .single, tags: [
            Tag(id: "urgent", name: "긴급", colorHex: "#E24B4A"), Tag(id: "low", name: "낮음", colorHex: "#7896C8")]),
        TagGroup(id: "w", name: "분류", selection: .multiple, tags: [Tag(id: "Work", name: "Work", colorHex: "#9A9A9A")]),
    ], sortGroupId: "g")

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func run(_ args: [String]) -> (obj: [String: Any], code: Int32) {
        let r = TodoInbox.runCLI(args: args, inboxDir: dir, config: cfg)
        return (try! JSONSerialization.jsonObject(with: Data(r.output.utf8)) as! [String: Any], r.code)
    }

    func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "json" }
    }

    func testCLIWritesInboxAndResolvesTags() throws {
        let (o, code) = run(["--title", " 보고서 ", "--due", "2026-10-09", "--tag", " work ", "--tag", "없음", "--memo", "링크"])
        XCTAssertEqual(code, 0)
        XCTAssertEqual(o["ok"] as? Bool, true)
        XCTAssertEqual(o["title"] as? String, "보고서")
        XCTAssertEqual(o["tags"] as? [String], ["work"])
        XCTAssertEqual(o["unknownTags"] as? [String], ["없음"])
        let f = try XCTUnwrap(files().first)
        XCTAssertEqual(f.deletingPathExtension().lastPathComponent, o["id"] as? String)
        let item = try TodoInbox.decoder.decode(InboxItem.self, from: Data(contentsOf: f))
        XCTAssertEqual(item.memo, "링크")
        XCTAssertEqual(item.due, "2026-10-09")
    }

    func testCLIValidation() {
        for args in [["--title", "  "], [], ["--title", "a", "--due", "2026-02-30"], ["--title", "a", "--due", "2026-1-5"], ["--title"]] {
            let (o, code) = run(args)
            XCTAssertEqual(code, 2, "\(args)")
            XCTAssertEqual(o["ok"] as? Bool, false)
        }
        XCTAssertTrue(files().isEmpty)
    }

    func testImportResolvesTagsDeletesFilesAndMovesBad() throws {
        let id = run(["--title", "t", "--tag", "긴급", "--tag", "낮음", "--tag", "WORK", "--due", "2026-10-09", "--memo", "  상세 내용\n- 링크  "]).obj["id"] as! String
        try Data("{oops".utf8).write(to: dir.appendingPathComponent("junk.json"))
        var got: [Todo] = []
        XCTAssertEqual(TodoInbox.importPending(inboxDir: dir, config: cfg) { got = $0 }, 1)
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got[0].id.uuidString, id)
        XCTAssertEqual(got[0].dueDate, "2026-10-09")
        XCTAssertEqual(got[0].memo, "상세 내용\n- 링크")
        XCTAssertEqual(got[0].tagIds, ["urgent", "Work"])   // 하나만 그룹은 첫 태그만
        XCTAssertTrue(files().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("bad/junk.json").path))
    }

    func testFilesKeptWhenApplyFails() throws {
        _ = run(["--title", "t"])
        struct E: Error {}
        XCTAssertEqual(TodoInbox.importPending(inboxDir: dir, config: cfg) { _ in throw E() }, 0)
        XCTAssertEqual(files().count, 1)
    }

    func testTodoSkillMarkdown() throws {
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: "/Apps/ATM.app/Contents/MacOS/TaskWidget")
        XCTAssertFalse(ci.todoSkillInstalled())
        try ci.installTodoSkill()
        XCTAssertTrue(ci.todoSkillInstalled())
        let text = try String(contentsOf: ci.todoSkillURL, encoding: .utf8)
        XCTAssertTrue(text.contains("name: atm-todo"))
        XCTAssertTrue(text.contains("\"/Apps/ATM.app/Contents/MacOS/TaskWidget\" --add-todo"))
        try ci.removeTodoSkill()
        XCTAssertFalse(FileManager.default.fileExists(atPath: ci.todoSkillURL.deletingLastPathComponent().path))
    }
}
