import Foundation

public enum HookStatus: Equatable {
    case installed, notInstalled, pathMismatch
}

public enum IntegrationError: Error, Equatable {
    case invalidSettingsJSON
}

public struct ClaudeIntegration {
    public let claudeDir: URL
    public let executablePath: String

    public init(claudeDir: URL = Paths.claudeDir, executablePath: String) {
        self.claudeDir = claudeDir
        self.executablePath = executablePath
    }

    public var settingsURL: URL { claudeDir.appendingPathComponent("settings.json") }
    public var skillURL: URL { claudeDir.appendingPathComponent("skills/worklog/SKILL.md") }
    public var hookCommand: String { "\"\(executablePath)\" --hook" }

    static let events = ["UserPromptSubmit", "Stop"]

    static func isOurs(_ command: Any?) -> Bool {
        guard let c = command as? String else { return false }
        return c.contains("TaskWidget") && c.hasSuffix("--hook")
    }

    // MARK: settings.json

    func readSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data), let dict = obj as? [String: Any] else {
            throw IntegrationError.invalidSettingsJSON
        }
        return dict
    }

    func writeSettings(_ root: [String: Any]) throws {
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let backup = settingsURL.appendingPathExtension("bak-" + f.string(from: Date()))
            try? FileManager.default.copyItem(at: settingsURL, to: backup)
        }
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }

    public func hookStatus() -> HookStatus {
        guard let root = try? readSettings(), let hooks = root["hooks"] as? [String: Any] else { return .notInstalled }
        var found = 0, exact = 0
        for ev in Self.events {
            for group in hooks[ev] as? [[String: Any]] ?? [] {
                for h in group["hooks"] as? [[String: Any]] ?? [] where Self.isOurs(h["command"]) {
                    found += 1
                    if (h["command"] as? String) == hookCommand { exact += 1 }
                }
            }
        }
        if found == 0 { return .notInstalled }
        return (found == Self.events.count && exact == found) ? .installed : .pathMismatch
    }

    /// 두 이벤트에 우리 훅을 넣는다. 이미 있으면 command 만 현재 경로로 갱신. 다른 훅/키는 보존.
    public func installHook() throws {
        var root = try readSettings()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for ev in Self.events {
            var groups = hooks[ev] as? [[String: Any]] ?? []   // 잘못된 값이면 빈 배열로 교체
            var found = false
            for gi in groups.indices {
                var inner = groups[gi]["hooks"] as? [[String: Any]] ?? []
                for hi in inner.indices where Self.isOurs(inner[hi]["command"]) {
                    inner[hi]["command"] = hookCommand
                    found = true
                }
                groups[gi]["hooks"] = inner
            }
            if !found {
                groups.append(["hooks": [["type": "command", "command": hookCommand, "timeout": 5]]])
            }
            hooks[ev] = groups
        }
        root["hooks"] = hooks
        try writeSettings(root)
    }

    /// 우리 훅만 제거. 비게 된 그룹/이벤트/hooks 키는 삭제.
    public func removeHook() throws {
        var root = try readSettings()
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for ev in Self.events {
            guard let groups = hooks[ev] as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { g in
                var g = g
                let inner = (g["hooks"] as? [[String: Any]] ?? []).filter { !Self.isOurs($0["command"]) }
                if inner.isEmpty { return nil }
                g["hooks"] = inner
                return g
            }
            if kept.isEmpty { hooks.removeValue(forKey: ev) } else { hooks[ev] = kept }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try writeSettings(root)
    }

    // MARK: SKILL.md

    public func skillInstalled() -> Bool {
        FileManager.default.fileExists(atPath: skillURL.path)
    }

    public func installSkill() throws {
        try FileManager.default.createDirectory(at: skillURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.skillMarkdown.write(to: skillURL, atomically: true, encoding: .utf8)
    }

    public func removeSkill() throws {
        let dir = skillURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    public static let skillMarkdown = """
    ---
    name: worklog
    description: 현재 세션에서 한 일을 정리해 TaskWidget 업무 일지에 기록한다. "/worklog", "오늘 한 거 기록해", "업무 일지 남겨", "worklog" 요청 시 사용.
    ---

    현재 세션에서 지금까지 한 일을 정리해 아래 파일 끝에 append 한다.

    파일: `~/Library/Application Support/TaskWidget/worklog/YYYY-MM-DD.md` (오늘 로컬 날짜. 디렉터리 없으면 만든다)

    형식:

    ## HH:mm · <프로젝트명>
    - 한 일 (성과/결과 위주) 3~7개, 각 1~2문장
    - 미완료: (있을 때만, 한 줄)

    규칙:
    - 프로젝트명 = 현재 작업 디렉터리의 마지막 경로 요소.
    - 파일이 없으면 첫 줄 `# YYYY-MM-DD 업무 일지` 후 빈 줄, 그 다음 섹션.
    - 기존 내용은 수정하지 않는다. 끝에 append만.
    - `$ARGUMENTS`가 있으면 그 범위나 관점을 반영한다 (예: "오전 작업만", "버그 수정 위주").
    - 추측하지 않는다. 이 세션에서 실제로 한 일만 쓴다.
    - 기록 후 추가한 섹션을 그대로 보여준다.

    """
}
