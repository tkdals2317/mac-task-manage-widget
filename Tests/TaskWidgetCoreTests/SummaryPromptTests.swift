import XCTest
@testable import TaskWidgetCore

final class SummaryPromptTests: XCTestCase {
    let seoul: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func rec(_ project: String, _ event: String, _ text: String, _ offset: TimeInterval = 0) -> ActivityRecord {
        ActivityRecord(ts: Date(timeIntervalSince1970: 1_790_000_000 + offset), event: event, session: "s",
                       cwd: "/Users/x/projects/\(project)", text: text)
    }

    func testIsEmpty() {
        XCTAssertTrue(SummaryPrompt.isEmpty(SummaryInput(dayKey: "2026-10-02", worklogRaw: nil, worklogProjects: [], activity: [], commits: [:])))
        XCTAssertTrue(SummaryPrompt.isEmpty(SummaryInput(dayKey: "2026-10-02", worklogRaw: "  \n", worklogProjects: [], activity: [], commits: ["p": []])))
        XCTAssertFalse(SummaryPrompt.isEmpty(SummaryInput(dayKey: "2026-10-02", worklogRaw: "# x", worklogProjects: [], activity: [], commits: [:])))
        XCTAssertFalse(SummaryPrompt.isEmpty(SummaryInput(dayKey: "2026-10-02", worklogRaw: nil, worklogProjects: [], activity: [rec("a", "prompt", "x")], commits: [:])))
        XCTAssertFalse(SummaryPrompt.isEmpty(SummaryInput(dayKey: "2026-10-02", worklogRaw: nil, worklogProjects: [], activity: [], commits: ["p": ["abc feat"]])))
    }

    func testFilterDropsCoveredProjects() {
        let out = SummaryPrompt.filterActivity([rec("mrs-cms", "prompt", "a"), rec("task-manager", "prompt", "b")], coveredProjects: ["mrs-cms"])
        XCTAssertEqual(out.map(\.text), ["b"])
    }

    func testFilterCapsPerMessage() {
        let out = SummaryPrompt.filterActivity([
            rec("p", "prompt", String(repeating: "u", count: 1000)),
            rec("p", "stop", String(repeating: "a", count: 5000)),
        ], coveredProjects: [])
        XCTAssertEqual(out[0].text.count, SummaryPrompt.promptCap + 1)   // + "…"
        XCTAssertTrue(out[0].text.hasSuffix("…"))
        XCTAssertEqual(out[1].text.count, SummaryPrompt.stopCap + 1)
    }

    func testFilterDropsOldestWhenOverTotal() {
        // 1200자짜리 stop 100개 = 120,000 > 80,000 → 앞에서부터 제거
        let recs = (0..<100).map { i in rec("p", "stop", String(repeating: "x", count: 1200), TimeInterval(i)) }
        let out = SummaryPrompt.filterActivity(recs, coveredProjects: [])
        XCTAssertLessThanOrEqual(out.reduce(0) { $0 + $1.text.count }, SummaryPrompt.totalCap)
        XCTAssertEqual(out.last?.ts, recs.last?.ts, "최신 것이 남는다")
    }

    func testBuildSections() {
        let input = SummaryInput(
            dayKey: "2026-10-02",
            worklogRaw: "## 09:40 · mrs-cms\n- 일지 내용",
            worklogProjects: ["mrs-cms"],
            activity: [rec("task-manager", "prompt", "위젯 설계"), rec("task-manager", "stop", "스펙 작성함", 60)],
            commits: ["task-manager": ["abc1234 docs: 스펙"], "mrs-cms": []]
        )
        let p = SummaryPrompt.build(input, calendar: seoul)
        XCTAssertTrue(p.contains("날짜: 2026-10-02"))
        XCTAssertTrue(p.contains("=== 1) 업무 일지 ===\n## 09:40 · mrs-cms"))
        XCTAssertTrue(p.contains("=== 2) 대화 기록: task-manager (/Users/x/projects/task-manager) ==="))
        XCTAssertTrue(p.contains("] user: 위젯 설계"))
        XCTAssertTrue(p.contains("] assistant: 스펙 작성함"))
        XCTAssertTrue(p.contains("=== 3) 커밋: task-manager ===\nabc1234 docs: 스펙"))
        XCTAssertFalse(p.contains("커밋: mrs-cms"), "빈 커밋 목록은 섹션 생략")
        XCTAssertTrue(p.contains("도구를 사용하지 말고"))
    }

    func testBuildEmptySectionsSayNone() {
        let input = SummaryInput(dayKey: "2026-10-02", worklogRaw: nil, worklogProjects: [], activity: [], commits: [:])
        let p = SummaryPrompt.build(input, calendar: seoul)
        XCTAssertTrue(p.contains("=== 1) 업무 일지 ===\n(없음)"))
        XCTAssertTrue(p.contains("=== 2) 대화 기록 ===\n(없음)"))
        XCTAssertTrue(p.contains("=== 3) 커밋 ===\n(없음)"))
    }
}
