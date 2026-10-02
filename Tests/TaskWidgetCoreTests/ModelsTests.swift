import XCTest
@testable import TaskWidgetCore

final class ModelsTests: XCTestCase {
    let seoul: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func testDayKeyRoundTrip() {
        let d = DayKey.date(from: "2026-10-02", calendar: seoul)!
        XCTAssertEqual(DayKey.string(from: d, calendar: seoul), "2026-10-02")
    }

    func testDayKeyRejectsInvalid() {
        XCTAssertNil(DayKey.date(from: "2026-02-30", calendar: seoul))
        XCTAssertNil(DayKey.date(from: "abc", calendar: seoul))
        XCTAssertNil(DayKey.date(from: "2026-10", calendar: seoul))
    }

    func testNormalizedTitle() {
        XCTAssertEqual(Todo.normalizedTitle("  배포 문서  "), "배포 문서")
        XCTAssertNil(Todo.normalizedTitle("   "))
        XCTAssertNil(Todo.normalizedTitle(""))
    }

    func testActivityRecordProject() {
        let r = ActivityRecord(ts: Date(), event: "prompt", session: "s", cwd: "/Users/x/projects/mrs-cms", text: "t")
        XCTAssertEqual(r.project, "mrs-cms")
    }
}
