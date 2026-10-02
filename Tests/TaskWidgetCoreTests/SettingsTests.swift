import XCTest
@testable import TaskWidgetCore

final class SettingsTests: XCTestCase {
    var suite: String!
    var defaults: UserDefaults!

    override func setUp() {
        suite = "TaskWidgetTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaults() {
        let s = Settings(defaults: defaults)
        XCTAssertEqual(s.opacity, 1.0)
        XCTAssertTrue(s.hoverOpaque)
        XCTAssertEqual(s.theme, "system")
        XCTAssertEqual(s.fontScale, 1.0)
        XCTAssertTrue(s.alwaysOnTop)
        XCTAssertTrue(s.allSpaces)
        XCTAssertEqual(s.jiraBaseURL, "https://midasitweb-jira.atlassian.net")
        XCTAssertEqual(s.jiraEmail, "")
        XCTAssertEqual(s.jiraRefreshMinutes, 5)
        XCTAssertEqual(s.jiraJQL, "")
        XCTAssertEqual(s.summaryHour, 18)
        XCTAssertEqual(s.summaryMinute, 0)
        XCTAssertTrue(s.summaryNotify)
        XCTAssertEqual(s.claudeModel, "")
        XCTAssertEqual(s.claudePath, "")
        XCTAssertEqual(s.lastTab, "tasks")
    }

    func testSetAndGet() {
        let s = Settings(defaults: defaults)
        s.opacity = 0.7
        s.summaryHour = 9
        s.summaryMinute = 30
        s.jiraEmail = "a@b.c"
        s.hoverOpaque = false
        XCTAssertEqual(s.opacity, 0.7)
        XCTAssertEqual(s.summaryHour, 9)
        XCTAssertEqual(s.summaryMinute, 30)
        XCTAssertEqual(s.jiraEmail, "a@b.c")
        XCTAssertFalse(s.hoverOpaque)
    }

    func testKeysMatchAppStorageNames() {
        // SwiftUI 쪽 @AppStorage 가 같은 문자열을 쓰므로 상수 값이 바뀌면 안 된다
        XCTAssertEqual(SettingsKey.opacity, "opacity")
        XCTAssertEqual(SettingsKey.summaryHour, "summaryHour")
        XCTAssertEqual(SettingsKey.jiraJQL, "jiraJQL")
    }
}
