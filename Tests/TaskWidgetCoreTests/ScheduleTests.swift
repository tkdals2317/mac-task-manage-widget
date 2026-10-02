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

    func testCatchUpDaysBeforeScheduledTimeHasOnlyPastDays() {
        let days = Schedule.catchUpDays(now: at("2026-10-02", 17, 59), hour: 18, minute: 0, calendar: cal)
        XCTAssertEqual(days.map { DayKey.string(from: $0, calendar: cal) },
                       ["2026-09-25", "2026-09-26", "2026-09-27", "2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01"])
    }

    func testCatchUpDaysAfterScheduledTimeIncludesToday() {
        let days = Schedule.catchUpDays(now: at("2026-10-02", 18, 0), hour: 18, minute: 0, calendar: cal)
        XCTAssertEqual(days.count, 8)
        XCTAssertEqual(DayKey.string(from: days.first!, calendar: cal), "2026-09-25")
        XCTAssertEqual(DayKey.string(from: days.last!, calendar: cal), "2026-10-02")
    }

    func testCatchUpDaysZeroLookbackIsTodayOnly() {
        let days = Schedule.catchUpDays(now: at("2026-10-02", 19, 0), hour: 18, minute: 0, lookbackDays: 0, calendar: cal)
        XCTAssertEqual(days.map { DayKey.string(from: $0, calendar: cal) }, ["2026-10-02"])
    }
}
