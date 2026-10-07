import Foundation

public enum DueStyle: Equatable {
    case none, overdue, today, normal
}

public enum DueBadge {
    /// 잘못된 dueDate 문자열은 nil 처럼 취급.
    public static func badge(due: String?, today: Date, calendar: Calendar = .current) -> (text: String, style: DueStyle) {
        guard let due, let dueDate = DayKey.date(from: due, calendar: calendar) else { return ("", .none) }
        let start = calendar.startOfDay(for: today)
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: dueDate)).day ?? 0
        switch days {
        case ..<0:
            return ("D+\(-days)", .overdue)
        case 0:
            return ("오늘", .today)
        case 1...7:
            return ("D-\(days)", .normal)
        default:
            let c = calendar.dateComponents([.month, .day], from: dueDate)
            return ("\(c.month!)/\(c.day!)", .normal)
        }
    }

    /// 안 끝난 할 일 중 마감이 오늘이거나 지난 개수 (메뉴바 배지용).
    public static func urgentCount(todos: [Todo], now: Date, calendar: Calendar = .current) -> Int {
        todos.filter { t in
            guard !t.done else { return false }
            let s = badge(due: t.dueDate, today: now, calendar: calendar).style
            return s == .today || s == .overdue
        }.count
    }

    /// dueDate 오름차순, nil 은 뒤, 동률은 createdAt 오름차순. "yyyy-MM-dd" 는 문자열 비교로 충분.
    public static func sorted(_ todos: [Todo]) -> [Todo] {
        todos.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case (nil, nil): return a.createdAt < b.createdAt
            case (nil, _): return false
            case (_, nil): return true
            case let (x?, y?): return x == y ? a.createdAt < b.createdAt : x < y
            }
        }
    }
}
