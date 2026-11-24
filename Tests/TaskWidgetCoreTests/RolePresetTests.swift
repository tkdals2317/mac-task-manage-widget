import XCTest
@testable import TaskWidgetCore

final class RolePresetTests: XCTestCase {
    func testPresets() {
        let d = RolePreset.preset(for: .developer)
        XCTAssertEqual(RolePreset.tabsString(d.tabs), "tasks,summary,notes,pr,teleport")
        XCTAssertEqual(d.jira, .assignee); XCTAssertEqual(d.e2eScope, "assignee")
        let p = RolePreset.preset(for: .planner)
        XCTAssertEqual(RolePreset.tabsString(p.tabs), "tasks,notes,e2e")
        XCTAssertEqual(p.jira, .reporter); XCTAssertEqual(p.e2eScope, "reporter")
        let c = RolePreset.preset(for: .custom)
        XCTAssertTrue(c.tabs.isEmpty); XCTAssertFalse(RolePreset.isValid(tabs: c.tabs))
        XCTAssertEqual(c.jira, .assignee)
    }

    func testJQLMapping() {
        XCTAssertEqual(RolePreset.jql(for: .assignee), "")
        XCTAssertEqual(RolePreset.jql(for: .reporter), JiraClient.reporterJQL)
        XCTAssertEqual(RolePreset.jql(for: .both), RolePreset.bothJQL)
        XCTAssertNil(RolePreset.jql(for: .keep))
        for s in [JiraListScope.assignee, .reporter, .both] {
            XCTAssertEqual(RolePreset.scope(forJQL: RolePreset.jql(for: s)!), s)
        }
        XCTAssertEqual(RolePreset.scope(forJQL: "  "), .assignee)
        XCTAssertEqual(RolePreset.scope(forJQL: JiraClient.defaultJQL), .assignee)
        XCTAssertEqual(RolePreset.scope(forJQL: "project = X"), .keep)
    }

    func testSteps() {
        XCTAssertEqual(RolePreset.steps(tabs: ["tasks"]), [.role, .storage, .atlassian, .finish])
        XCTAssertEqual(RolePreset.steps(tabs: ["summary"]), [.role, .claude, .finish])
        XCTAssertEqual(RolePreset.steps(tabs: ["teleport"]), [.role, .storage, .teleport, .finish])
        XCTAssertEqual(RolePreset.steps(tabs: ["e2e"]), [.role, .storage, .atlassian, .e2e, .finish])
        XCTAssertEqual(RolePreset.steps(tabs: ["pr"], showPRRepos: true), [.role, .storage, .pr, .prRepos, .finish])
        XCTAssertEqual(RolePreset.steps(tabs: Set(RolePreset.tabOrder)),
                       [.role, .storage, .atlassian, .notes, .pr, .e2e, .claude, .teleport, .finish])
    }

    func testPreview() {
        XCTAssertEqual(RolePreset.previewLine(RolePreset.steps(tabs: ["tasks"])), "다음: 저장 위치 → Atlassian → 마무리")
        XCTAssertEqual(RolePreset.previewLine(RolePreset.steps(tabs: Set(RolePreset.tabOrder))),
                       "다음: 저장 위치 → Atlassian → … → 마무리")
    }

    func testApply() {
        let suite = "RolePresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let s = Settings(defaults: defaults)
        s.jiraJQL = "project = X"
        var plan = RolePreset.preset(for: .planner)
        plan.jira = .keep
        RolePreset.apply(plan, to: s)
        XCTAssertEqual(s.jiraJQL, "project = X"); XCTAssertEqual(s.enabledTabs, "tasks,notes,e2e"); XCTAssertEqual(s.e2eIssueScope, "reporter")
        RolePreset.apply(RolePreset.preset(for: .planner), to: s)
        XCTAssertEqual(s.jiraJQL, JiraClient.reporterJQL)
        // 탭이 비면 기존 탭을 건드리지 않는다
        RolePreset.apply(RolePreset.preset(for: .custom), to: s)
        XCTAssertEqual(s.enabledTabs, "tasks,notes,e2e"); XCTAssertEqual(s.jiraJQL, "")
    }
}
