import Foundation

public enum Schedule {
    /// 오늘 hour:minute 가 now 보다 뒤면 오늘, 아니면(같거나 지났으면) 내일.
    public static func nextFireDate(after now: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date {
        var c = calendar.dateComponents([.year, .month, .day], from: now)
        c.hour = hour
        c.minute = minute
        c.second = 0
        let today = calendar.date(from: c)!
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today)!
    }
}
