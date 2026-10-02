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

    func testUnreadableSettingsThrowsAndLeavesFile() throws {
        let url = dir.appendingPathComponent("settings.json")
        let original = #"{"model":"opus","permissions":{"allow":["Bash(ls:*)"]}}"#
        try original.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        try XCTSkipIf(FileManager.default.isReadableFile(atPath: url.path), "root 로 실행 중이면 000 파일도 읽힌다")

        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        XCTAssertThrowsError(try ci.installHook()) { XCTAssertEqual($0 as? IntegrationError, .invalidSettingsJSON) }
        XCTAssertThrowsError(try ci.removeHook()) { XCTAssertEqual($0 as? IntegrationError, .invalidSettingsJSON) }
        XCTAssertEqual(ci.hookStatus(), .notInstalled)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original, "읽을 수 없던 파일은 그대로")
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".bak-") }
        XCTAssertEqual(backups, [])
    }

    func testSymlinkedSettingsKeepsLinkAndWritesTarget() throws {
        let real = dir.appendingPathComponent("real-settings.json")
        try #"{"model":"opus"}"#.write(to: real, atomically: true, encoding: .utf8)
        let link = dir.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        try ci.installHook()

        XCTAssertNoThrow(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), "심볼릭 링크 유지")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: real)) as! [String: Any]
        XCTAssertEqual(root["model"] as? String, "opus")
        XCTAssertEqual(ourCommands(root, "Stop"), [ci.hookCommand], "링크 대상 파일에 기록")
        XCTAssertEqual(ci.hookStatus(), .installed)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(names.filter { $0.hasPrefix("real-settings.json.bak-") }.count, 1, "백업은 대상 옆에")
        XCTAssertEqual(names.filter { $0.hasPrefix("settings.json.bak-") }.count, 0)
    }

    func testSecondInstallInSameSecondKeepsEarlierBackup() throws {
        try copyFixture()
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        try ci.installHook()
        try ci.installHook()
        try ci.removeHook()
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("settings.json.bak-") }
        XCTAssertEqual(backups.count, 3, "쓸 때마다 백업, 같은 초여도 덮어쓰지 않음")
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: ci.skillURL.deletingLastPathComponent().path), "SKILL.md 만 있었으면 디렉터리도 삭제")
    }

    func testRemoveSkillKeepsOtherFilesInDirectory() throws {
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        try ci.installSkill()
        let notes = ci.skillURL.deletingLastPathComponent().appendingPathComponent("notes.md")
        try "mine".write(to: notes, atomically: true, encoding: .utf8)
        try ci.removeSkill()
        XCTAssertFalse(ci.skillInstalled())
        XCTAssertEqual(try String(contentsOf: notes, encoding: .utf8), "mine")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ci.skillURL.deletingLastPathComponent().path))
        try ci.removeSkill()   // 이미 없어도 던지지 않는다
    }
}
