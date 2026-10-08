import Foundation

public struct ReleaseNote: Equatable {
    public let version: String
    public let date: String?
    public let body: String
}

/// CHANGELOG.md 파싱. 섹션은 `## <버전>` 또는 `## <버전> — <날짜>` (` - ` 도 허용).
public enum ReleaseNotes {
    public static func parse(_ markdown: String) -> [ReleaseNote] {
        var notes: [ReleaseNote] = []
        var head: (String, String?)?
        var lines: [String] = []
        func flush() {
            if let h = head {
                notes.append(ReleaseNote(version: h.0, date: h.1,
                                         body: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            lines = []
        }
        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                let t = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var v = t, d: String?
                for sep in [" — ", " - "] {
                    if let r = t.range(of: sep) {
                        v = String(t[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                        d = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                        break
                    }
                }
                head = (v, d)
            } else if head != nil {
                lines.append(line)
            }
        }
        flush()
        return notes
    }

    private static func components(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
    }

    public static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let x = components(a), y = components(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// installed 보다 새로운 노트(최신순). installed 가 "숫자.숫자" 형식이 아니면 최신 노트 하나만.
    public static func newer(than installed: String, in notes: [ReleaseNote]) -> [ReleaseNote] {
        let sorted = notes.sorted { compareVersions($0.version, $1.version) == .orderedDescending }
        guard installed.first?.isNumber == true else { return Array(sorted.prefix(1)) }
        return sorted.filter { compareVersions($0.version, installed) == .orderedDescending }
    }
}
