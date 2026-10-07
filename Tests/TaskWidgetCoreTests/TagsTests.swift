import XCTest
@testable import TaskWidgetCore

final class TagsTests: XCTestCase {
    var dir: URL!
    let cfg = TagDefaults.config   // importance(single): urgent, high, normal, low

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
        XCTAssertEqual(TagStore(fileURL: dir.appendingPathComponent("tags.json")).load(), TagDefaults.config)
    }

    func testStoreRoundTripV2() throws {
        let store = TagStore(fileURL: dir.appendingPathComponent("tags.json"))
        let c = TagConfig(groups: [
            TagGroup(id: "g1", name: "종류", selection: .multiple, tags: [Tag(id: "x", name: "엑스", colorHex: "#C77DFF")]),
            TagGroup(id: "g2", name: "빈", selection: .single),
        ], sortGroupId: "g2")
        try store.save(c)
        XCTAssertEqual(store.load(), c)
        let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("\"version\" : 2"))
    }

    func testMigratesV1() throws {
        let url = dir.appendingPathComponent("tags.json")
        let v1 = #"[{"id":"urgent","name":"긴급","color":"red"},{"id":"zz","name":"기타","color":"gray"}]"#
        try Data(v1.utf8).write(to: url)
        let c = TagStore(fileURL: url).load()
        XCTAssertEqual(c.groups.count, 1)
        XCTAssertEqual(c.groups[0].id, "importance")
        XCTAssertEqual(c.groups[0].name, "중요도")
        XCTAssertEqual(c.groups[0].selection, .single)
        XCTAssertEqual(c.sortGroupId, "importance")
        XCTAssertEqual(c.allTags.map(\.id), ["urgent", "zz"])
        XCTAssertEqual(c.allTags.map(\.colorHex), [TagColor.red.hex, TagColor.gray.hex])
        // 다시 읽으면 v2
        XCTAssertEqual(TagStore(fileURL: url).load(), c)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("\"version\""))
    }

    func testStoreCorruptBacksUp() throws {
        let url = dir.appendingPathComponent("tags.json")
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(TagStore(fileURL: url).load(), TagDefaults.config)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("tags.corrupt-") })
    }

    private var twoGroups: TagConfig {
        TagConfig(groups: [
            TagGroup(id: "kind", name: "종류", selection: .multiple, tags: [
                Tag(id: "bug", name: "버그", colorHex: "#E24B4A"), Tag(id: "feat", name: "기능", colorHex: "#22C55E")]),
            TagGroup(id: "importance", name: "중요도", selection: .single, tags: [
                Tag(id: "urgent", name: "긴급", colorHex: "#E24B4A"), Tag(id: "low", name: "낮음", colorHex: "#7896C8")]),
        ], sortGroupId: "importance")
    }

    func testToggled() {
        let c = twoGroups
        XCTAssertEqual(c.toggled("urgent", in: ["low", "bug"]), ["bug", "urgent"])   // single 은 형제 교체
        XCTAssertEqual(c.toggled("feat", in: ["bug"]), ["bug", "feat"])              // multiple 은 추가
        XCTAssertEqual(c.toggled("bug", in: ["bug", "low"]), ["low"])                // 끄기
        XCTAssertEqual(c.toggled("nope", in: ["bug"]), ["bug"])
    }

    func testNormalized() {
        let c = twoGroups
        XCTAssertEqual(c.normalized(["low", "zzz", "urgent", "feat", "bug"]), ["bug", "feat", "urgent"])
    }

    func testRankAndSortWithSortGroup() {
        let c = twoGroups
        XCTAssertEqual(TagSort.rank(Todo(title: "a"), config: c), Int.max)
        XCTAssertEqual(TagSort.rank(Todo(title: "a", tagIds: ["bug"]), config: c), Int.max)   // 정렬 그룹 밖
        XCTAssertEqual(TagSort.rank(Todo(title: "a", tagIds: ["bug", "low"]), config: c), 1)
        var missing = c
        missing.sortGroupId = "gone"   // 없는 그룹 → 첫 그룹(종류)
        XCTAssertEqual(TagSort.rank(Todo(title: "a", tagIds: ["feat"]), config: missing), 1)
        missing.sortGroupId = nil
        XCTAssertEqual(TagSort.rank(Todo(title: "a", tagIds: ["feat"]), config: missing), Int.max)
    }

    func testSortedByTag() {
        let t0 = Date(timeIntervalSince1970: 0)
        let none = Todo(title: "none", createdAt: t0, dueDate: "2026-01-01")
        let lowSoon = Todo(title: "lowSoon", createdAt: t0, dueDate: "2026-01-01", tagIds: ["low"])
        let urgentLate = Todo(title: "urgentLate", createdAt: t0, dueDate: "2026-12-01", tagIds: ["urgent"])
        let urgentSoon = Todo(title: "urgentSoon", createdAt: t0, dueDate: "2026-02-01", tagIds: ["urgent"])
        let urgentNoDue = Todo(title: "urgentNoDue", createdAt: t0, tagIds: ["urgent"])
        let out = TagSort.sorted([none, lowSoon, urgentNoDue, urgentLate, urgentSoon], config: cfg, byTag: true)
        XCTAssertEqual(out.map(\.title), ["urgentSoon", "urgentLate", "urgentNoDue", "lowSoon", "none"])
    }

    func testSortedByTagOffEqualsDueBadge() {
        let list = [
            Todo(title: "a", createdAt: Date(timeIntervalSince1970: 2), tagIds: ["low"]),
            Todo(title: "b", createdAt: Date(timeIntervalSince1970: 1), dueDate: "2026-05-05", tagIds: ["urgent"]),
            Todo(title: "c", createdAt: Date(timeIntervalSince1970: 3), dueDate: "2026-01-01"),
        ]
        XCTAssertEqual(TagSort.sorted(list, config: cfg, byTag: false), DueBadge.sorted(list))
    }

    func testOrderedByGroupThenTag() {
        let out = TagSort.ordered(["low", "zzz", "feat", "urgent", "bug"], config: twoGroups)
        XCTAssertEqual(out.map(\.id), ["bug", "feat", "urgent", "low"])
    }

    func testHexColor() throws {
        let c = try XCTUnwrap(HexColor.rgb("#e24b4a"))
        XCTAssertEqual(HexColor.hex(r: c.r, g: c.g, b: c.b), "#E24B4A")
        for p in TagColor.allCases {
            let v = try XCTUnwrap(HexColor.rgb(p.hex))
            XCTAssertEqual(HexColor.hex(r: v.r, g: v.g, b: v.b), p.hex)
        }
        XCTAssertNil(HexColor.rgb("#12345"))
        XCTAssertNil(HexColor.rgb("#GGGGGG"))
        XCTAssertNil(HexColor.rgb(""))
    }

    func testDefaults() {
        let c = TagDefaults.config
        XCTAssertEqual(c.groups.count, 1)
        XCTAssertEqual(c.groups[0].id, "importance")
        XCTAssertEqual(c.groups[0].selection, .single)
        XCTAssertEqual(c.sortGroupId, "importance")
        XCTAssertEqual(c.allTags.map(\.id), ["urgent", "high", "normal", "low"])
        XCTAssertEqual(c.allTags.map(\.colorHex), [TagColor.red, .orange, .gray, .blue].map(\.hex))
    }
}
