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
    /// 먼저 나갈 버전 먼저 (숫자 인지 비교 오름차순: 15.5.a → 15.6.0, 동률은 이름순)
    static func releaseOrder(_ a: String, _ b: String) -> Bool {
        let r = a.compare(b, options: .numeric)
        return r == .orderedSame ? a < b : r == .orderedAscending
    }

    public static func counts(_ issues: [JiraIssue]) -> (versions: [(name: String, count: Int)], noneCount: Int) {
        var c: [String: Int] = [:]
        var none = 0
        for i in issues {
            if i.fixVersions.isEmpty { none += 1 }
            for v in Set(i.fixVersions) { c[v, default: 0] += 1 }
        }
        return (c.keys.sorted(by: releaseOrder).map { ($0, c[$0]!) }, none)
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

    /// 모든 버전 이름이 같은 "XXX_" 접두어(첫 '_' 까지 포함)로 시작하면 그 접두어, 아니면 "". 이름이 하나뿐이어도 적용. 접두어를 빼면 빈 문자열이 되는 이름이 있으면 "".
    public static func commonPrefix(_ names: [String]) -> String {
        guard let first = names.first, let i = first.firstIndex(of: "_") else { return "" }
        let prefix = String(first[...i])
        return names.allSatisfy { $0.hasPrefix(prefix) && $0.count > prefix.count } ? prefix : ""
    }

    public static func display(_ name: String, prefix: String) -> String {
        name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }

    public static func tag(for issue: JiraIssue, prefix: String = "") -> String? {
        // 여러 버전이면 가장 먼저 나갈 버전을 보여준다.
        guard let first = issue.fixVersions.sorted(by: releaseOrder).first else { return nil }
        let shown = display(first, prefix: prefix)
        return issue.fixVersions.count > 1 ? "\(shown) +\(issue.fixVersions.count - 1)" : shown
    }
}
