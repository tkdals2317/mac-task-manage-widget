import Foundation

public struct Todo: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var done: Bool
    public var createdAt: Date
    public var completedAt: Date?
    /// "yyyy-MM-dd" 로컬 날짜. 시각 없음.
    public var dueDate: String?
    public var tagIds: [String]

    public init(id: UUID = UUID(), title: String, done: Bool = false, createdAt: Date = Date(),
                completedAt: Date? = nil, dueDate: String? = nil, tagIds: [String] = []) {
        self.id = id
        self.title = title
        self.done = done
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.dueDate = dueDate
        self.tagIds = tagIds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        done = try c.decode(Bool.self, forKey: .done)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        tagIds = try c.decodeIfPresent([String].self, forKey: .tagIds) ?? []
    }

    /// 앞뒤 공백 제거. 비면 nil.
    public static func normalizedTitle(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

public struct JiraIssue: Codable, Identifiable, Equatable {
    public var id: String              // issue key
    public var summary: String
    public var status: String          // fields.status.name
    public var statusCategory: String  // new | indeterminate | done | (unknown)
    public var priority: String?
    public var updated: Date
    public var fixVersions: [String]

    public init(id: String, summary: String, status: String, statusCategory: String,
                priority: String?, updated: Date, fixVersions: [String] = []) {
        self.id = id
        self.summary = summary
        self.status = status
        self.statusCategory = statusCategory
        self.priority = priority
        self.updated = updated
        self.fixVersions = fixVersions
    }
}

public struct Summary: Equatable {
    public var dayKey: String
    public var markdown: String
    public var generatedAt: Date

    public init(dayKey: String, markdown: String, generatedAt: Date) {
        self.dayKey = dayKey
        self.markdown = markdown
        self.generatedAt = generatedAt
    }
}

public struct ActivityRecord: Codable, Equatable {
    public var ts: Date
    public var event: String   // "prompt" | "stop"
    public var session: String
    public var cwd: String
    public var text: String

    public init(ts: Date, event: String, session: String, cwd: String, text: String) {
        self.ts = ts
        self.event = event
        self.session = session
        self.cwd = cwd
        self.text = text
    }

    public var project: String { (cwd as NSString).lastPathComponent }
}

public struct WorklogEntry: Equatable {
    public var time: String     // "HH:mm"
    public var project: String
    public var body: String

    public init(time: String, project: String, body: String) {
        self.time = time
        self.project = project
        self.body = body
    }
}

public enum DayKey {
    public static func string(from date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        guard let d = calendar.date(from: c) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: d)
        guard back.year == parts[0], back.month == parts[1], back.day == parts[2] else { return nil }
        return d
    }
}
