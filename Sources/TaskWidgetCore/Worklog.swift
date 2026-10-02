import Foundation

public enum Worklog {
    public static func fileURL(for day: Date, dir: URL = Paths.worklogDir, calendar: Calendar = .current) -> URL {
        dir.appendingPathComponent(DayKey.string(from: day, calendar: calendar) + ".md")
    }

    public static func raw(on day: Date, dir: URL = Paths.worklogDir, calendar: Calendar = .current) -> String? {
        // 깨진 UTF-8 바이트가 있어도 일지 전체를 버리지 않는다 (U+FFFD 로 치환). 파일이 없을 때만 nil.
        guard let data = try? Data(contentsOf: fileURL(for: day, dir: dir, calendar: calendar)) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func entries(on day: Date, dir: URL = Paths.worklogDir, calendar: Calendar = .current) -> [WorklogEntry] {
        raw(on: day, dir: dir, calendar: calendar).map(parse) ?? []
    }

    /// `^## (\d{2}:\d{2}) · (.+)$` 헤더로 분할 (spec §8.4). 이 형식이 아닌 `##` 줄은 본문.
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
            if let header = header(line) {
                flush()
                (time, project) = header
                lines = []
                open = true
            } else if open {
                lines.append(line)
            }
        }
        flush()
        return out
    }

    /// `## HH:mm · project` 이면 (time, project), 아니면 nil. 구분자는 `## ` 접두 뒤에서만 찾는다.
    private static func header(_ line: String) -> (time: String, project: String)? {
        guard line.hasPrefix("## ") else { return nil }
        let start = line.index(line.startIndex, offsetBy: 3)
        guard let sep = line.range(of: " · ", range: start..<line.endIndex) else { return nil }
        let time = String(line[start..<sep.lowerBound])
        let project = String(line[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard time.range(of: "^[0-9]{2}:[0-9]{2}$", options: .regularExpression) != nil, !project.isEmpty else { return nil }
        return (time, project)
    }
}
