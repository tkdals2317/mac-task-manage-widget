import XCTest
@testable import TaskWidgetCore

final class ScheduleTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func at(_ day: String, _ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        var c = cal.dateComponents([.year, .month, .day], from: DayKey.date(from: day, calendar: cal)!)
        c.hour = h; c.minute = m; c.second = s
        return cal.date(from: c)!
    }

    func testBeforeScheduledTimeFiresToday() {
        let next = Schedule.nextFireDate(after: at("2026-10-02", 17, 59), hour: 18, minute: 0, calendar: cal)
        XCTAssertEqual(next, at("2026-10-02", 18, 0))
    }

    func testAfterScheduledTimeFiresTomorrow() {
        let next = Schedule.nextFireDate(after: at("2026-10-02", 18, 1), hour: 18, minute: 0, calendar: cal)
        XCTAssertEqual(next, at("2026-10-03", 18, 0))
    }

    func testExactlyAtScheduledTimeFiresTomorrow() {
        let next = Schedule.nextFireDate(after: at("2026-10-02", 18, 0, 0), hour: 18, minute: 0, calendar: cal)
        XCTAssertEqual(next, at("2026-10-03", 18, 0))
    }

    func testMonthBoundary() {
        let next = Schedule.nextFireDate(after: at("2026-10-31", 20, 0), hour: 18, minute: 30, calendar: cal)
        XCTAssertEqual(next, at("2026-11-01", 18, 30))
    }
}
