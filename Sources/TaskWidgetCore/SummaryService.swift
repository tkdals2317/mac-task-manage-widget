import Foundation

public final class SummaryService {
    public typealias Runner = (String) throws -> String

    public let dataDir: URL
    public let calendar: Calendar
    private let runner: Runner
    private let instructions: () -> String?
    private let jiraProjectKeys: () -> Set<String>
    private let lock = NSLock()

    public init(dataDir: URL = Paths.dataDir, calendar: Calendar = .current,
                instructions: @escaping () -> String? = { nil },
                jiraProjectKeys: @escaping () -> Set<String> = { [] }, runner: @escaping Runner) {
        self.dataDir = dataDir
        self.calendar = calendar
        self.runner = runner
        self.instructions = instructions
        self.jiraProjectKeys = jiraProjectKeys
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

        let prefixes = jiraProjectKeys()
        var branches: [String: String] = [:]
        var commits: [String: [String]] = [:]
        var seen = Set<String>()  // 저장소 루트와 하위 폴더가 둘 다 cwd 로 잡혀도 같은 커밋은 한 번만
        for cwd in Set(all.map(\.cwd)).filter({ !$0.isEmpty }).sorted() {
            let lines = GitActivity.commits(in: cwd, on: day, calendar: calendar).filter {
                guard let hash = $0.split(separator: " ").first else { return false }
                return seen.insert(String(hash)).inserted
            }
            if !prefixes.isEmpty, let b = GitActivity.branch(in: cwd) { branches[(cwd as NSString).lastPathComponent] = b }
            if !lines.isEmpty {
                commits[(cwd as NSString).lastPathComponent, default: []] += lines
            }
        }

        let activity = SummaryPrompt.filterActivity(all, coveredProjects: covered)
        let projects = Set(all.map(\.project)).union(covered).sorted()
        var jira: [String: [String]] = [:]
        for p in projects {
            let texts = entries.filter { $0.project == p }.map(\.body) + all.filter { $0.project == p }.map(\.text)
                + (commits[p] ?? []) + [branches[p]].compactMap { $0 }
            let keys = SummaryPrompt.jiraKeys(in: texts, prefixes: prefixes)
            if !keys.isEmpty { jira[p] = keys }
        }
        return SummaryInput(dayKey: key, worklogRaw: raw, worklogProjects: covered, activity: activity, commits: commits,
                            worklogSectionCount: entries.count, activityDropped: all.count - activity.count, projects: projects,
                            jiraKeys: jira)
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
                markdown = try runner(SummaryPrompt.build(input, instructions: instructions(), calendar: calendar))
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

    // MARK: - 주간

    private var isoCalendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = calendar.timeZone
        return c
    }

    /// 월~일 7일과 "2026-W41" 키.
    public func weekDays(containing day: Date) -> (key: String, days: [Date]) {
        let iso = isoCalendar
        let start = iso.dateInterval(of: .weekOfYear, for: day)!.start
        let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)
        return (String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!),
                (0..<7).map { iso.date(byAdding: .day, value: $0, to: start)! })
    }

    /// "2026-W41 (10/05~10/11)"
    public func weekLabel(containing day: Date) -> String {
        let (key, days) = weekDays(containing: day)
        let md = { (d: Date) -> String in
            let c = self.calendar.dateComponents([.month, .day], from: d)
            return String(format: "%02d/%02d", c.month!, c.day!)
        }
        return "\(key) (\(md(days[0]))~\(md(days[6])))"
    }

    public func weeklyURL(for day: Date) -> URL {
        dataDir.appendingPathComponent("summaries/week-\(weekDays(containing: day).key).md")
    }

    public func existingWeekly(for day: Date) -> Summary? {
        let url = weeklyURL(for: day)
        guard let md = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
        return Summary(dayKey: weekDays(containing: day).key, markdown: md, generatedAt: mtime)
    }

    /// 그 주의 일간 요약 파일(없거나 "기록 없음"은 제외)을 합쳐 주간 요약 생성. 일간 요약이 하나도 없으면 claude 를 부르지 않고 throw.
    @discardableResult
    public func generateWeekly(weekContaining day: Date, force: Bool) throws -> Summary {
        if !force, let s = existingWeekly(for: day) { return s }
        guard lock.try() else { throw SummaryError.busy }
        defer { lock.unlock() }

        let (key, days) = weekDays(containing: day)
        var body = ""
        var used = 0
        for d in days {
            guard let s = existing(for: d), s.markdown != Self.noRecordMarkdown(dayKey: s.dayKey) else { continue }
            body += "\n\n=== \(s.dayKey) ===\n" + s.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            used += 1
        }
        var log = "[\(key)] weekly daily_summaries=\(used)\n"
        guard used > 0 else {
            writeLog("week-\(key)", log + "no daily summaries\n")
            throw SummaryError.noDailySummaries
        }

        let prompt = SummaryPrompt.weeklyInstructions.replacingOccurrences(of: "{주}", with: weekLabel(containing: day)) + body + "\n"
        let markdown: String
        do {
            markdown = try runner(prompt)
        } catch {
            writeLog("week-\(key)", log + "error: \(error)\n")
            throw error
        }
        let url = weeklyURL(for: day)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        log += "ok\n"
        writeLog("week-\(key)", log)
        return Summary(dayKey: key, markdown: markdown, generatedAt: Date())
    }

    private func writeLog(_ key: String, _ text: String) {
        let url = dataDir.appendingPathComponent("logs/summary-\(key).log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
