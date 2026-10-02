import XCTest
@testable import TaskWidgetCore

final class ClaudeIntegrationTests: XCTestCase {
    var dir: URL!
    let exeA = "/Applications/TaskWidget.app/Contents/MacOS/TaskWidget"
    let exeB = "/Users/x/projects/task-manager/build/TaskWidget.app/Contents/MacOS/TaskWidget"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func copyFixture() throws {
        let src = Bundle.module.url(forResource: "settings-with-hooks", withExtension: "json", subdirectory: "Fixtures")!
        try FileManager.default.copyItem(at: src, to: dir.appendingPathComponent("settings.json"))
    }

    func readJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: dir.appendingPathComponent("settings.json"))
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func ourCommands(_ root: [String: Any], _ event: String) -> [String] {
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let groups = hooks[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
            .filter { $0.contains("TaskWidget") }
    }

    func testStatusNotInstalledWhenMissingFile() {
        XCTAssertEqual(ClaudeIntegration(claudeDir: dir, executablePath: exeA).hookStatus(), .notInstalled)
    }

    func testInstallPreservesOtherHooksAndKeys() throws {
        try copyFixture()
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        try ci.installHook()
        let root = try readJSON()
        XCTAssertNotNil(root["permissions"], "다른 키 보존")
        let hooks = root["hooks"] as! [String: Any]
        XCTAssertEqual((hooks["SessionStart"] as! [[String: Any]]).count, 1, "다른 이벤트 보존")
        let ups = hooks["UserPromptSubmit"] as! [[String: Any]]
        XCTAssertEqual(ups.count, 2, "기존 그룹 + 우리 그룹")
        XCTAssertEqual(ourCommands(root, "UserPromptSubmit"), [ci.hookCommand])
        XCTAssertEqual(ourCommands(root, "Stop"), [ci.hookCommand])
        XCTAssertEqual(ci.hookStatus(), .installed)
        let text = try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8)
        XCTAssertFalse(text.contains("\\/"), "슬래시 이스케이프 금지")
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("settings.json.bak-") }
        XCTAssertEqual(backups.count, 1)
    }

    func testInstallIsIdempotent() throws {
        try copyFixture()
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        try ci.installHook()
        try ci.installHook()
        let root = try readJSON()
        XCTAssertEqual(ourCommands(root, "UserPromptSubmit").count, 1)
        XCTAssertEqual(ourCommands(root, "Stop").count, 1)
    }

    func testPathMismatchAndReinstall() throws {
        try copyFixture()
        try ClaudeIntegration(claudeDir: dir, executablePath: exeB).installHook()
        let ciA = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        XCTAssertEqual(ciA.hookStatus(), .pathMismatch)
        try ciA.installHook()
        XCTAssertEqual(ciA.hookStatus(), .installed)
        XCTAssertEqual(ourCommands(try readJSON(), "Stop"), [ciA.hookCommand])
    }

    func testRemoveRestoresOthers() throws {
        try copyFixture()
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        try ci.installHook()
        try ci.removeHook()
        let root = try readJSON()
        let hooks = root["hooks"] as! [String: Any]
        XCTAssertNil(hooks["Stop"], "우리만 있던 이벤트는 키 삭제")
        XCTAssertEqual((hooks["UserPromptSubmit"] as! [[String: Any]]).count, 1, "남의 그룹만 남음")
        XCTAssertEqual(ourCommands(root, "UserPromptSubmit"), [])
        XCTAssertEqual(ci.hookStatus(), .notInstalled)
    }

    func testInstallCreatesFileWhenMissing() throws {
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        try ci.installHook()
        XCTAssertEqual(ci.hookStatus(), .installed)
        XCTAssertEqual(ourCommands(try readJSON(), "UserPromptSubmit").count, 1)
    }

    func testInvalidJSONThrowsAndLeavesFile() throws {
        try "{ not json".write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        XCTAssertThrowsError(try ci.installHook()) { XCTAssertEqual($0 as? IntegrationError, .invalidSettingsJSON) }
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8), "{ not json")
        XCTAssertEqual(ci.hookStatus(), .notInstalled)
    }

    func testMalformedEventValueReplaced() throws {
        try #"{"hooks":{"Stop":"oops","UserPromptSubmit":[]}}"#.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        try ci.installHook()
        XCTAssertEqual(ci.hookStatus(), .installed)
        XCTAssertEqual(ourCommands(try readJSON(), "Stop").count, 1)
    }

    func testHookCommandQuotesPath() {
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: "/Users/me/My Apps/TaskWidget.app/Contents/MacOS/TaskWidget")
        XCTAssertEqual(ci.hookCommand, "\"/Users/me/My Apps/TaskWidget.app/Contents/MacOS/TaskWidget\" --hook")
    }

    func testSkillInstallRemove() throws {
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        XCTAssertFalse(ci.skillInstalled())
        try ci.installSkill()
        XCTAssertTrue(ci.skillInstalled())
        let md = try String(contentsOf: ci.skillURL, encoding: .utf8)
        XCTAssertTrue(md.hasPrefix("---\nname: worklog\n"))
        XCTAssertTrue(md.contains("~/Library/Application Support/TaskWidget/worklog/YYYY-MM-DD.md"))
        XCTAssertTrue(md.contains("## HH:mm · <프로젝트명>"))
        try ci.removeSkill()
        XCTAssertFalse(ci.skillInstalled())
        XCTAssertFalse(FileManager.default.fileExists(atPath: ci.skillURL.deletingLastPathComponent().path))
    }
}
