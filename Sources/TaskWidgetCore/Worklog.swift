import Foundation

public enum Worklog {
    public static func fileURL(for day: Date, dir: URL = Paths.worklogDir, calendar: Calendar = .current) -> URL {
        dir.appendingPathComponent(DayKey.string(from: day, calendar: calendar) + ".md")
    }

    public static func raw(on day: Date, dir: URL = Paths.worklogDir, calendar: Calendar = .current) -> String? {
        try? String(contentsOf: fileURL(for: day, dir: dir, calendar: calendar), encoding: .utf8)
    }

    public static func entries(on day: Date, dir: URL = Paths.worklogDir, calendar: Calendar = .current) -> [WorklogEntry] {
        raw(on: day, dir: dir, calendar: calendar).map(parse) ?? []
    }

    /// `## HH:mm · project` 헤더로 분할. 구분자 없는 `##` 줄은 본문.
    public static func parse(_ markdown: String) -> [WorklogEntry] {
        var out: [WorklogEntry] = []
        var time = "", project = "", lines: [String] = []
        var open = false

        func flush() {
            guard open else { return }
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(WorklogEntry(time: time, project: project, body: body))
        }

        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("## "), let sep = line.range(of: " · ") {
                flush()
                time = String(line[line.index(line.startIndex, offsetBy: 3)..<sep.lowerBound]).trimmingCharacters(in: .whitespaces)
                project = String(line[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
                lines = []
                open = true
            } else if open {
                lines.append(line)
            }
        }
        flush()
        return out
    }
}
