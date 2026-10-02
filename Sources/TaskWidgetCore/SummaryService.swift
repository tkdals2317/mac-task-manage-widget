import Foundation

public final class SummaryService {
    public typealias Runner = (String) throws -> String

    public let dataDir: URL
    public let calendar: Calendar
    private let runner: Runner
    private let lock = NSLock()

    public init(dataDir: URL = Paths.dataDir, calendar: Calendar = .current, runner: @escaping Runner) {
        self.dataDir = dataDir
        self.calendar = calendar
        self.runner = runner
    }

    public func summaryURL(for day: Date) -> URL {
        dataDir.appendingPathComponent("summaries/\(DayKey.string(from: day, calendar: calendar)).md")
    }

    public func existing(for day: Date) -> Summary? {
        let url = summaryURL(for: day)
        guard let md = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
        return Summary(dayKey: DayKey.string(from: day, calendar: calendar), markdown: md, generatedAt: mtime)
    }

    public static func noRecordMarkdown(dayKey: String) -> String {
        "# \(dayKey) 업무 요약\n\n오늘 기록 없음\n"
    }

    /// 일지 → 활동(일지 없는 프로젝트만) → 커밋(활동에서 본 모든 cwd) 수집.
    public func collect(for day: Date) -> SummaryInput {
        let key = DayKey.string(from: day, calendar: calendar)
        let worklogDir = dataDir.appendingPathComponent("worklog", isDirectory: true)
        let raw = Worklog.raw(on: day, dir: worklogDir, calendar: calendar)
        let entries = Worklog.entries(on: day, dir: worklogDir, calendar: calendar)
        let covered = Set(entries.map(\.project))

        let all = ActivityLog.records(on: day, from: dataDir.appendingPathComponent("activity.jsonl"), calendar: calendar)

        var commits: [String: [String]] = [:]
        var seen = Set<String>()  // 저장소 루트와 하위 폴더가 둘 다 cwd 로 잡혀도 같은 커밋은 한 번만
        for cwd in Set(all.map(\.cwd)).filter({ !$0.isEmpty }).sorted() {
            let lines = GitActivity.commits(in: cwd, on: day, calendar: calendar).filter {
                guard let hash = $0.split(separator: " ").first else { return false }
                return seen.insert(String(hash)).inserted
            }
            if !lines.isEmpty {
                commits[(cwd as NSString).lastPathComponent, default: []] += lines
            }
        }

        let activity = SummaryPrompt.filterActivity(all, coveredProjects: covered)
        let projects = Set(all.map(\.project)).union(covered).sorted()
        return SummaryInput(dayKey: key, worklogRaw: raw, worklogProjects: covered, activity: activity, commits: commits,
                            worklogSectionCount: entries.count, activityDropped: all.count - activity.count, projects: projects)
    }

    @discardableResult
    public func generate(for day: Date, force: Bool) throws -> Summary {
        if !force, let s = existing(for: day) { return s }
        guard lock.try() else { throw SummaryError.busy }
        defer { lock.unlock() }

        let input = collect(for: day)
        let key = input.dayKey
        var log = "[\(key)] worklog_sections=\(input.worklogSectionCount) activity_kept=\(input.activity.count) activity_dropped=\(input.activityDropped) projects=\(input.projects.joined(separator: ",")) commits=\(input.commits.values.map(\.count).reduce(0, +))\n"

        let markdown: String
        if SummaryPrompt.isEmpty(input) {
            markdown = Self.noRecordMarkdown(dayKey: key)
            log += "no records\n"
        } else {
            do {
                markdown = try runner(SummaryPrompt.build(input, calendar: calendar))
            } catch {
                log += "error: \(error)\n"
                writeLog(key, log)
                throw error
            }
        }

        let url = summaryURL(for: day)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        writeLog(key, log + "ok\n")
        return Summary(dayKey: key, markdown: markdown, generatedAt: Date())
    }

    private func writeLog(_ key: String, _ text: String) {
        let url = dataDir.appendingPathComponent("logs/summary-\(key).log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
