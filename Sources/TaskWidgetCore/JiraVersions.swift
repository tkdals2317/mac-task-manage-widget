import Foundation

public enum VersionFilter: Equatable {
    case all, none, named(String)

    static let noneToken = "\u{1}none"

    public init(storage: String) {
        switch storage {
        case "": self = .all
        case Self.noneToken: self = .none
        default: self = .named(storage)
        }
    }

    public var storage: String {
        switch self {
        case .all: return ""
        case .none: return Self.noneToken
        case .named(let n): return n
        }
    }
}

public enum JiraVersions {
    /// 최신 버전 먼저 (숫자 인지 비교 내림차순, 동률은 이름순)
    static func newestFirst(_ a: String, _ b: String) -> Bool {
        let r = a.compare(b, options: .numeric)
        return r == .orderedSame ? a < b : r == .orderedDescending
    }

    public static func counts(_ issues: [JiraIssue]) -> (versions: [(name: String, count: Int)], noneCount: Int) {
        var c: [String: Int] = [:]
        var none = 0
        for i in issues {
            if i.fixVersions.isEmpty { none += 1 }
            for v in Set(i.fixVersions) { c[v, default: 0] += 1 }
        }
        return (c.keys.sorted(by: newestFirst).map { ($0, c[$0]!) }, none)
    }

    public static func filter(_ issues: [JiraIssue], _ f: VersionFilter) -> [JiraIssue] {
        switch f {
        case .all: return issues
        case .none: return issues.filter { $0.fixVersions.isEmpty }
        case .named(let n): return issues.filter { $0.fixVersions.contains(n) }
        }
    }

    public static func grouped(_ issues: [JiraIssue]) -> [(title: String?, issues: [JiraIssue])] {
        let sorted = JiraClient.sortedForDisplay(issues)
        var out = counts(issues).versions.map { v in
            (title: Optional(v.name), issues: sorted.filter { $0.fixVersions.contains(v.name) })
        }
        let none = sorted.filter { $0.fixVersions.isEmpty }
        if !none.isEmpty { out.append((title: nil, issues: none)) }
        return out
    }

    public static func tag(for issue: JiraIssue) -> String? {
        guard let first = issue.fixVersions.first else { return nil }
        return issue.fixVersions.count > 1 ? "\(first) +\(issue.fixVersions.count - 1)" : first
    }
}
