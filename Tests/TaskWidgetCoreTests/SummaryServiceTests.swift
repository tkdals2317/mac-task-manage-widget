import XCTest
@testable import TaskWidgetCore

final class SummaryServiceTests: XCTestCase {
    let seoul: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    var dir: URL!
    var day: Date { DayKey.date(from: "2026-10-02", calendar: seoul)! }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func writeActivity(_ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent("activity.jsonl"), atomically: true, encoding: .utf8)
    }

    func testNoRecordsWritesPlaceholderWithoutCallingRunner() throws {
        var called = false
        let svc = SummaryService(dataDir: dir, calendar: seoul) { _ in called = true; return "x" }
        let s = try svc.generate(for: day, force: false)
        XCTAssertFalse(called)
        XCTAssertEqual(s.markdown, SummaryService.noRecordMarkdown(dayKey: "2026-10-02"))
        XCTAssertTrue(s.markdown.contains("오늘 기록 없음"))
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("summaries/2026-10-02.md"), encoding: .utf8), s.markdown)
    }

    func testGenerateFromActivityAndWritesFileAndLog() throws {
        try writeActivity([
            #"{"cwd":"/Users/x/projects/mrs-cms","event":"prompt","session":"s1","text":"PDF 느림","ts":"2026-10-02T09:12:33+09:00"}"#,
            #"{"cwd":"/Users/x/projects/mrs-cms","event":"stop","session":"s1","text":"N+1 제거","ts":"2026-10-02T09:40:10+09:00"}"#,
        ])
        var received = ""
        let svc = SummaryService(dataDir: dir, calendar: seoul) { prompt in received = prompt; return "# 2026-10-02 업무 요약\n## mrs-cms\n- N+1 제거" }
        let s = try svc.generate(for: day, force: false)
        XCTAssertTrue(received.contains("대화 기록: mrs-cms"))
        XCTAssertTrue(received.contains("PDF 느림"))
        XCTAssertEqual(s.markdown, "# 2026-10-02 업무 요약\n## mrs-cms\n- N+1 제거")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("summaries/2026-10-02.md").path))
        let log = try String(contentsOf: dir.appendingPathComponent("logs/summary-2026-10-02.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("activity_kept=2"))
        XCTAssertTrue(log.contains("activity_dropped=0"))
        XCTAssertTrue(log.contains("projects=mrs-cms"))
        XCTAssertTrue(log.contains("ok"))
    }

    func testWorklogCoversProjectSoRawDropped() throws {
        try writeActivity([
            #"{"cwd":"/Users/x/projects/mrs-cms","event":"prompt","session":"s1","text":"RAW-SHOULD-DROP","ts":"2026-10-02T09:12:33+09:00"}"#,
            #"{"cwd":"/Users/x/projects/other","event":"prompt","session":"s2","text":"RAW-KEEP","ts":"2026-10-02T10:00:00+09:00"}"#,
        ])
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("worklog"), withIntermediateDirectories: true)
        try "## 09:40 · mrs-cms\n- 일지".write(to: dir.appendingPathComponent("worklog/2026-10-02.md"), atomically: true, encoding: .utf8)
        var received = ""
        let svc = SummaryService(dataDir: dir, calendar: seoul) { p in received = p; return "ok" }
        _ = try svc.generate(for: day, force: false)
        XCTAssertTrue(received.contains("- 일지"))
        XCTAssertFalse(received.contains("RAW-SHOULD-DROP"))
        XCTAssertTrue(received.contains("RAW-KEEP"))
        let log = try String(contentsOf: dir.appendingPathComponent("logs/summary-2026-10-02.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("worklog_sections=1 activity_kept=1 activity_dropped=1 projects=mrs-cms,other"))
    }

    func testExistingReturnedWithoutRunnerUnlessForce() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("summaries"), withIntermediateDirectories: true)
        try "old".write(to: dir.appendingPathComponent("summaries/2026-10-02.md"), atomically: true, encoding: .utf8)
        try writeActivity([#"{"cwd":"/p","event":"prompt","session":"s","text":"t","ts":"2026-10-02T09:00:00+09:00"}"#])
        var calls = 0
        let svc = SummaryService(dataDir: dir, calendar: seoul) { _ in calls += 1; return "new" }
        XCTAssertEqual(try svc.generate(for: day, force: false).markdown, "old")
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(try svc.generate(for: day, force: true).markdown, "new")
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(svc.existing(for: day)?.markdown, "new")
    }

    func testRunnerErrorLeavesNoFileAndLogsError() throws {
        try writeActivity([#"{"cwd":"/p","event":"prompt","session":"s","text":"t","ts":"2026-10-02T09:00:00+09:00"}"#])
        let svc = SummaryService(dataDir: dir, calendar: seoul) { _ in throw SummaryError.timeout }
        XCTAssertThrowsError(try svc.generate(for: day, force: false)) { XCTAssertEqual($0 as? SummaryError, .timeout) }
        XCTAssertNil(svc.existing(for: day))
        let log = try String(contentsOf: dir.appendingPathComponent("logs/summary-2026-10-02.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("error: timeout"))
    }

    func testExistingNilWhenMissing() {
        let svc = SummaryService(dataDir: dir, calendar: seoul) { _ in "x" }
        XCTAssertNil(svc.existing(for: day))
    }
}
