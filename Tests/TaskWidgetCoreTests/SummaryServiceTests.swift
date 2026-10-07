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

    func testUsesInstructionsProvider() throws {
        try writeActivity([
            #"{"cwd":"/Users/x/projects/mrs-cms","event":"prompt","session":"s1","text":"PDF 느림","ts":"2026-10-02T09:12:33+09:00"}"#,
        ])
        var received = ""
        let svc = SummaryService(dataDir: dir, calendar: seoul, instructions: { "MARK {날짜}" }) { p in received = p; return "ok" }
        try svc.generate(for: day, force: false)
        XCTAssertTrue(received.hasPrefix("MARK 2026-10-02"))
        XCTAssertTrue(received.contains("PDF 느림"))
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

    func testCollectDedupesCommitsAcrossCwds() throws {
        // git --since/--until 은 로컬 시간 기준이라 이 테스트만 Date() + Calendar.current 사용
        let repo = dir.appendingPathComponent("repo")
        let sub = repo.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        func git(_ args: [String]) {
            let r = ProcessRunner.run(executable: "/usr/bin/git", arguments: ["-C", repo.path] + args, timeout: 10)
            XCTAssertEqual(r.status, 0, r.stderr)
        }
        git(["init", "-q"])
        git(["config", "user.email", "me@test"])
        try "a".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        git(["add", "."])
        git(["-c", "user.name=t", "commit", "-q", "-m", "feat: once"])

        let now = Date()
        for cwd in [repo.path, sub.path] {
            try ActivityLog.append(ActivityRecord(ts: now, event: "prompt", session: "s", cwd: cwd, text: "t"),
                                   to: dir.appendingPathComponent("activity.jsonl"))
        }
        let input = SummaryService(dataDir: dir, calendar: .current) { _ in "x" }.collect(for: now)
        let all = input.commits.values.flatMap { $0 }
        XCTAssertEqual(all.filter { $0.hasSuffix(" feat: once") }.count, 1, "\(input.commits)")
    }

    func testExistingNilWhenMissing() {
        let svc = SummaryService(dataDir: dir, calendar: seoul) { _ in "x" }
        XCTAssertNil(svc.existing(for: day))
    }

    // MARK: - Jira 키 / 주간

    func testCollectFindsJiraKeysForKnownPrefixes() throws {
        try writeActivity([
            #"{"cwd":"/Users/x/projects/mrs-cms","event":"prompt","session":"s1","text":"NMRS-5 UTF-8 처리, NMRS-5 again","ts":"2026-10-02T09:12:33+09:00"}"#,
        ])
        let svc = SummaryService(dataDir: dir, calendar: seoul, jiraProjectKeys: { ["NMRS"] }) { _ in "" }
        XCTAssertEqual(svc.collect(for: day).jiraKeys, ["mrs-cms": ["NMRS-5"]])
        let none = SummaryService(dataDir: dir, calendar: seoul) { _ in "" }
        XCTAssertTrue(none.collect(for: day).jiraKeys.isEmpty)
    }

    func writeDaily(_ key: String, _ md: String) throws {
        let d = dir.appendingPathComponent("summaries")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try md.write(to: d.appendingPathComponent("\(key).md"), atomically: true, encoding: .utf8)
    }

    func testWeekRangeMonToSunAndIsoYearBoundary() {
        let svc = SummaryService(dataDir: dir, calendar: seoul) { _ in "" }
        let w = svc.weekDays(containing: DayKey.date(from: "2026-10-07", calendar: seoul)!)
        XCTAssertEqual(w.key, "2026-W41")
        XCTAssertEqual(w.days.map { DayKey.string(from: $0, calendar: seoul) }.first, "2026-10-05")
        XCTAssertEqual(w.days.map { DayKey.string(from: $0, calendar: seoul) }.last, "2026-10-11")
        XCTAssertEqual(svc.weekLabel(containing: DayKey.date(from: "2026-10-07", calendar: seoul)!), "2026-W41 (10/05~10/11)")
        // 2026-12-31 은 ISO 2026-W53 (12/28~01/03)
        let y = svc.weekDays(containing: DayKey.date(from: "2026-12-31", calendar: seoul)!)
        XCTAssertEqual(y.key, "2026-W53")
        XCTAssertEqual(DayKey.string(from: y.days[6], calendar: seoul), "2027-01-03")
    }

    func testWeeklySkipsMissingAndNoRecordDaysAndSaves() throws {
        try writeDaily("2026-10-05", "# 2026-10-05 업무 요약\n## a\n- 월요일 일")
        try writeDaily("2026-10-06", SummaryService.noRecordMarkdown(dayKey: "2026-10-06"))
        try writeDaily("2026-10-08", "# 2026-10-08 업무 요약\n## a\n- 목요일 일 (NMRS-1)")
        var received = ""
        let svc = SummaryService(dataDir: dir, calendar: seoul) { p in received = p; return "WEEK" }
        let s = try svc.generateWeekly(weekContaining: DayKey.date(from: "2026-10-07", calendar: seoul)!, force: false)
        XCTAssertEqual(s.markdown, "WEEK")
        XCTAssertTrue(received.hasPrefix("2026-W41 (10/05~10/11) 개발자 주간 업무 요약"))
        XCTAssertTrue(received.contains("=== 2026-10-05 ===\n# 2026-10-05"))
        XCTAssertTrue(received.contains("=== 2026-10-08 ==="))
        XCTAssertFalse(received.contains("2026-10-06 ==="))
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("summaries/week-2026-W41.md"), encoding: .utf8), "WEEK")
        XCTAssertEqual(svc.existingWeekly(for: DayKey.date(from: "2026-10-09", calendar: seoul)!)?.markdown, "WEEK")
    }

    func testWeeklyWithoutDailiesThrowsWithoutRunner() throws {
        try writeDaily("2026-10-06", SummaryService.noRecordMarkdown(dayKey: "2026-10-06"))
        var called = false
        let svc = SummaryService(dataDir: dir, calendar: seoul) { _ in called = true; return "x" }
        XCTAssertThrowsError(try svc.generateWeekly(weekContaining: DayKey.date(from: "2026-10-07", calendar: seoul)!, force: false)) {
            XCTAssertEqual($0 as? SummaryError, .noDailySummaries)
        }
        XCTAssertFalse(called)
    }
}
