import XCTest
@testable import TaskWidgetCore

final class TagsTests: XCTestCase {
    var dir: URL!
    let tags = TagDefaults.all   // urgent, high, normal, low

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testOldTodoJSONWithoutTagIds() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","title":"a","done":false,"createdAt":"2026-10-01T00:00:00Z"}]"#
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let todos = try d.decode([Todo].self, from: Data(json.utf8))
        XCTAssertEqual(todos[0].tagIds, [])
    }

    func testTodoTagIdsRoundTrip() throws {
        let store = TodoStore(fileURL: dir.appendingPathComponent("todos.json"))
        try store.save([Todo(title: "a", tagIds: ["urgent", "low"])])
        XCTAssertEqual(store.load()[0].tagIds, ["urgent", "low"])
    }

    func testStoreMissingIsDefaults() {
        XCTAssertEqual(TagStore(fileURL: dir.appendingPathComponent("tags.json")).load(), TagDefaults.all)
    }

    func testStoreRoundTrip() throws {
        let store = TagStore(fileURL: dir.appendingPathComponent("tags.json"))
        let t = [Tag(id: "x", name: "엑스", color: .purple)]
        try store.save(t)
        XCTAssertEqual(store.load(), t)
    }

    func testStoreCorruptBacksUp() throws {
        let url = dir.appendingPathComponent("tags.json")
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(TagStore(fileURL: url).load(), TagDefaults.all)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("tags.corrupt-") })
    }

    func testRank() {
        XCTAssertEqual(TagSort.rank(Todo(title: "a"), tags: tags), Int.max)
        XCTAssertEqual(TagSort.rank(Todo(title: "a", tagIds: ["zzz"]), tags: tags), Int.max)
        XCTAssertEqual(TagSort.rank(Todo(title: "a", tagIds: ["zzz", "low", "high"]), tags: tags), 1)
    }

    func testSortedByTag() {
        let t0 = Date(timeIntervalSince1970: 0)
        let none = Todo(title: "none", createdAt: t0, dueDate: "2026-01-01")
        let lowSoon = Todo(title: "lowSoon", createdAt: t0, dueDate: "2026-01-01", tagIds: ["low"])
        let urgentLate = Todo(title: "urgentLate", createdAt: t0, dueDate: "2026-12-01", tagIds: ["urgent"])
        let urgentSoon = Todo(title: "urgentSoon", createdAt: t0, dueDate: "2026-02-01", tagIds: ["urgent"])
        let urgentNoDue = Todo(title: "urgentNoDue", createdAt: t0, tagIds: ["urgent"])
        let out = TagSort.sorted([none, lowSoon, urgentNoDue, urgentLate, urgentSoon], tags: tags, byTag: true)
        XCTAssertEqual(out.map(\.title), ["urgentSoon", "urgentLate", "urgentNoDue", "lowSoon", "none"])
    }

    func testSortedByTagOffEqualsDueBadge() {
        let list = [
            Todo(title: "a", createdAt: Date(timeIntervalSince1970: 2), tagIds: ["low"]),
            Todo(title: "b", createdAt: Date(timeIntervalSince1970: 1), dueDate: "2026-05-05", tagIds: ["urgent"]),
            Todo(title: "c", createdAt: Date(timeIntervalSince1970: 3), dueDate: "2026-01-01"),
        ]
        XCTAssertEqual(TagSort.sorted(list, tags: tags, byTag: false), DueBadge.sorted(list))
    }

    func testOrdered() {
        let out = TagSort.ordered(["low", "zzz", "urgent"], tags: tags)
        XCTAssertEqual(out.map(\.id), ["urgent", "low"])
    }

    func testDefaults() {
        XCTAssertEqual(TagDefaults.all.map(\.id), ["urgent", "high", "normal", "low"])
        XCTAssertEqual(TagDefaults.all.map(\.color), [.red, .orange, .gray, .blue])
    }
}
