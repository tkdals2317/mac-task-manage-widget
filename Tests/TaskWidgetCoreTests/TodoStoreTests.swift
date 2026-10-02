import XCTest
@testable import TaskWidgetCore

final class TodoStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMissingFileIsEmpty() {
        let store = TodoStore(fileURL: dir.appendingPathComponent("todos.json"))
        XCTAssertEqual(store.load(), [])
    }

    func testRoundTrip() throws {
        let store = TodoStore(fileURL: dir.appendingPathComponent("todos.json"))
        let todos = [
            Todo(title: "a", dueDate: "2026-10-03"),
            Todo(title: "b", done: true, completedAt: Date(timeIntervalSince1970: 1_700_000_000)),
        ]
        try store.save(todos)
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].title, "a")
        XCTAssertEqual(loaded[0].dueDate, "2026-10-03")
        XCTAssertTrue(loaded[1].done)
        XCTAssertEqual(loaded[1].completedAt?.timeIntervalSince1970 ?? 0, 1_700_000_000, accuracy: 1)
    }

    func testCorruptFileIsBackedUpAndEmpty() throws {
        let file = dir.appendingPathComponent("todos.json")
        try "not json".write(to: file, atomically: true, encoding: .utf8)
        let store = TodoStore(fileURL: file)
        XCTAssertEqual(store.load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("todos.corrupt-") }
        XCTAssertEqual(backups.count, 1)
    }

    func testSaveCreatesParentDirectory() throws {
        let store = TodoStore(fileURL: dir.appendingPathComponent("nested/todos.json"))
        try store.save([Todo(title: "x")])
        XCTAssertEqual(store.load().count, 1)
    }
}
