import XCTest
@testable import TaskWidgetCore

final class OnboardingTests: XCTestCase {
    private func show(done: Bool = false, todos: Bool = false, email: String = "", tp: Bool = false, notes: Bool = false) -> Bool {
        Onboarding.shouldShow(done: done, todosExists: todos, jiraEmail: email, teleportExists: tp, notesExists: notes)
    }

    func testShowsOnlyWhenFreshAndNotDone() {
        XCTAssertTrue(show())
        XCTAssertTrue(show(email: "  "))
    }
    func testDoneNeverShows() {
        XCTAssertFalse(show(done: true))
        XCTAssertFalse(show(done: true, todos: true))
    }
    func testAnyPriorUsageSkips() {
        XCTAssertFalse(show(todos: true))
        XCTAssertFalse(show(email: "a@b.com"))
        XCTAssertFalse(show(tp: true))
        XCTAssertFalse(show(notes: true))
    }
    func testNormalizedURL() {
        XCTAssertEqual(Onboarding.normalizedURL(""), "")
        XCTAssertEqual(Onboarding.normalizedURL("  x.atlassian.net/ "), "https://x.atlassian.net")
        XCTAssertEqual(Onboarding.normalizedURL("https://x.atlassian.net"), "https://x.atlassian.net")
        XCTAssertEqual(Onboarding.normalizedURL("http://x.local"), "http://x.local")
    }
    func testEnabledTabs() {
        XCTAssertEqual(Onboarding.enabledTabs(summary: false, notes: false, teleport: false), "tasks")
        XCTAssertEqual(Onboarding.enabledTabs(summary: true, notes: true, teleport: true), "tasks,summary,notes,teleport")
        XCTAssertEqual(Onboarding.enabledTabs(summary: false, notes: true, teleport: true), "tasks,notes,teleport")
        XCTAssertEqual(Onboarding.enabledTabs(summary: true, notes: true, teleport: true, pr: true), "tasks,summary,notes,pr,teleport")
    }
}
