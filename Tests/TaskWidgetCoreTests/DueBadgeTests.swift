import XCTest
@testable import TaskWidgetCore

final class DueBadgeTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    var today: Date { DayKey.date(from: "2026-10-02", calendar: cal)! }

    func badge(_ due: String?) -> (text: String, style: DueStyle) {
        DueBadge.badge(due: due, today: today, calendar: cal)
    }

    func testNil() { XCTAssertEqual(badge(nil).style, .none) }

    func testOverdue() {
        let b = badge("2026-10-01")
        XCTAssertEqual(b.text, "D+1")
        XCTAssertEqual(b.style, .overdue)
    }

    func testToday() {
        let b = badge("2026-10-02")
        XCTAssertEqual(b.text, "오늘")
        XCTAssertEqual(b.style, .today)
    }

    func testWithinWeek() {
        XCTAssertEqual(badge("2026-10-03").text, "D-1")
        XCTAssertEqual(badge("2026-10-09").text, "D-7")
        XCTAssertEqual(badge("2026-10-09").style, .normal)
    }

    func testBeyondWeekShowsMonthDay() {
        XCTAssertEqual(badge("2026-10-10").text, "10/10")
        XCTAssertEqual(badge("2026-11-05").text, "11/5")
    }

    func testTodayParameterIsNotMidnightSensitive() {
        // today 가 23:50 이어도 같은 날이면 "오늘"
        let late = cal.date(byAdding: .minute, value: 23 * 60 + 50, to: today)!
        XCTAssertEqual(DueBadge.badge(due: "2026-10-02", today: late, calendar: cal).style, .today)
    }

    func testInvalidDueDateIsNone() {
        XCTAssertEqual(badge("2026-02-30").style, .none)
        XCTAssertEqual(badge("abc").style, .none)
    }

    func testSortedDueFirstThenNilThenCreated() {
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 10)
        let a = Todo(title: "a", createdAt: t1, dueDate: nil)
        let b = Todo(title: "b", createdAt: t0, dueDate: nil)
        let c = Todo(title: "c", createdAt: t1, dueDate: "2026-10-05")
        let d = Todo(title: "d", createdAt: t0, dueDate: "2026-10-05")
        let e = Todo(title: "e", createdAt: t1, dueDate: "2026-10-01")
        let sorted = DueBadge.sorted([a, b, c, d, e]).map(\.title)
        XCTAssertEqual(sorted, ["e", "d", "c", "b", "a"])
    }

    func testUrgentCount() {
        func n(_ ts: [Todo]) -> Int { DueBadge.urgentCount(todos: ts, now: today, calendar: cal) }
        XCTAssertEqual(n([]), 0)
        XCTAssertEqual(n([Todo(title: "a")]), 0)
        XCTAssertEqual(n([Todo(title: "a", dueDate: "2026-10-02")]), 1)
        XCTAssertEqual(n([Todo(title: "a", dueDate: "2026-10-01"), Todo(title: "b", dueDate: "2026-10-02")]), 2)
        var done = Todo(title: "d", dueDate: "2026-10-01"); done.done = true
        XCTAssertEqual(n([done]), 0)
        XCTAssertEqual(n([Todo(title: "f", dueDate: "2026-10-03")]), 0)
    }
}
