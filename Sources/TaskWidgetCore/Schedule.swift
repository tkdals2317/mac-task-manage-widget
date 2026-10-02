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

    /// 놓친 날짜 후보: 오늘(예정 시각이 지났을 때만) + 직전 lookbackDays 일. 오래된 날부터.
    public static func catchUpDays(now: Date, hour: Int, minute: Int, lookbackDays: Int = 7, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        var days = (0..<max(lookbackDays, 0)).reversed().compactMap { calendar.date(byAdding: .day, value: -($0 + 1), to: today) }
        if let scheduled = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today), now >= scheduled {
            days.append(today)
        }
        return days
    }
}
