import XCTest
@testable import TaskWidgetCore

final class TabConfigTests: XCTestCase {
    let all = ["tasks", "summary"]

    func testDefaultBoth() {
        XCTAssertEqual(TabConfig.enabled(from: "tasks,summary", all: all), all)
    }
    func testUnknownAndDuplicateDropped() {
        XCTAssertEqual(TabConfig.enabled(from: "tasks,foo,tasks", all: all), ["tasks"])
    }
    func testOrderFollowsAll() {
        XCTAssertEqual(TabConfig.enabled(from: "summary,tasks", all: all), all)
    }
    func testEmptyFallsBackToFirst() {
        XCTAssertEqual(TabConfig.enabled(from: "", all: all), ["tasks"])
        XCTAssertEqual(TabConfig.enabled(from: "foo", all: all), ["tasks"])
    }
    func testToggleOff() {
        XCTAssertEqual(TabConfig.toggled("tasks", in: "tasks,summary", all: all), "summary")
    }
    func testToggleOffLastUnchanged() {
        XCTAssertEqual(TabConfig.toggled("summary", in: "summary", all: all), "summary")
    }
    func testToggleOnKeepsAllOrder() {
        XCTAssertEqual(TabConfig.toggled("tasks", in: "summary", all: all), "tasks,summary")
    }
}
