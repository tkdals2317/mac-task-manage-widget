import XCTest
@testable import TaskWidgetCore

final class PathsTests: XCTestCase {
    func testDataDirUnderApplicationSupport() {
        XCTAssertEqual(Paths.dataDir.lastPathComponent, "TaskWidget")
        XCTAssertTrue(Paths.dataDir.path.contains("/Library/Application Support/"))
    }

    func testFileLocations() {
        XCTAssertEqual(Paths.todosFile.lastPathComponent, "todos.json")
        XCTAssertEqual(Paths.activityFile.lastPathComponent, "activity.jsonl")
        XCTAssertEqual(Paths.worklogDir.lastPathComponent, "worklog")
        XCTAssertEqual(Paths.summariesDir.lastPathComponent, "summaries")
        XCTAssertEqual(Paths.logsDir.lastPathComponent, "logs")
        XCTAssertEqual(Paths.claudeDir.lastPathComponent, ".claude")
    }
}
