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
    public var todoSkillURL: URL { claudeDir.appendingPathComponent("skills/atm-todo/SKILL.md") }
    public var hookCommand: String { "\"\(executablePath)\" --hook" }

    static let events = ["UserPromptSubmit", "Stop"]

    static func isOurs(_ command: Any?) -> Bool {
        guard let c = command as? String else { return false }
        return c.contains("TaskWidget") && c.hasSuffix("--hook")
    }

    // MARK: settings.json

    /// 파일이 없을 때만 빈 설정. 있는데 읽거나 파싱할 수 없으면 던진다 (사용자 설정을 덮어쓰지 않기 위해).
    func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: settingsURL),
              let obj = try? JSONSerialization.jsonObject(with: data), let dict = obj as? [String: Any] else {
            throw IntegrationError.invalidSettingsJSON
        }
        return dict
    }

    /// 기존 파일은 백업이 성공해야만 덮어쓴다. settings.json 이 심볼릭 링크면 링크 대상에 쓴다 (링크 보존).
    func writeSettings(_ root: [String: Any]) throws {
        let fm = FileManager.default
        let target = settingsURL.resolvingSymlinksInPath()
        if fm.fileExists(atPath: target.path) {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let stamp = f.string(from: Date())
            var backup = target.appendingPathExtension("bak-" + stamp)
            var n = 1
            while fm.fileExists(atPath: backup.path) {   // 같은 초에 두 번 쓰면 기존 백업을 덮지 않고 번호를 붙인다
                backup = target.appendingPathExtension("bak-\(stamp)-\(n)")
                n += 1
            }
            try fm.copyItem(at: target, to: backup)
        }
        try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: target, options: .atomic)
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

    /// SKILL.md 만 지우고, 디렉터리는 비었을 때만 지운다 (사용자가 넣어 둔 다른 파일 보존).
    public func removeSkill() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: skillURL.path) {
            try fm.removeItem(at: skillURL)
        }
        let dir = skillURL.deletingLastPathComponent()
        if let rest = try? fm.contentsOfDirectory(atPath: dir.path), rest.isEmpty {
            try fm.removeItem(at: dir)
        }
    }

    public static let skillMarkdown = """
    ---
    name: worklog
    description: 현재 세션에서 한 일을 정리해 ATM 업무 일지에 기록한다. "/worklog", "오늘 한 거 기록해", "업무 일지 남겨", "worklog" 요청 시 사용.
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

    // MARK: atm-todo SKILL.md

    public func todoSkillInstalled() -> Bool {
        FileManager.default.fileExists(atPath: todoSkillURL.path)
    }

    /// 바이너리 경로가 박히므로 앱을 옮기면 다시 설치해야 한다.
    public func installTodoSkill() throws {
        try FileManager.default.createDirectory(at: todoSkillURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try todoSkillMarkdown.write(to: todoSkillURL, atomically: true, encoding: .utf8)
    }

    public func removeTodoSkill() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: todoSkillURL.path) { try fm.removeItem(at: todoSkillURL) }
        let dir = todoSkillURL.deletingLastPathComponent()
        if let rest = try? fm.contentsOfDirectory(atPath: dir.path), rest.isEmpty { try fm.removeItem(at: dir) }
    }

    public var todoSkillMarkdown: String {
        let q = "\"" + executablePath.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        return """
        ---
        name: atm-todo
        description: ATM 위젯 할 일 목록에 할 일을 추가한다. '할 일에 추가해', 'ATM 에 넣어줘', 'todo 추가' 요청 시 사용.
        ---

        ATM 위젯의 할 일 목록에 할 일을 추가한다. 아래 명령을 Bash 로 실행한다 (할 일 하나당 한 번).

        ```
        \(q) --add-todo --title "<제목>" [--due YYYY-MM-DD] [--tag "<태그 이름>"]... [--memo "<메모>"]
        ```

        순서:
        1. 사용자 요청에서 간결한 제목을 만든다 (한국어 가능, 한 줄).
        2. 사용자가 날짜나 상대적인 날(내일, 금요일까지, 다음 주 월요일 등)을 말했을 때만 `--due YYYY-MM-DD` 를 붙인다. 기준 날짜는 `date +%F` 로 오늘을 확인해 계산한다.
        3. 사용자가 태그 이름을 직접 말했을 때만 `--tag` 를 붙인다 (여러 개면 반복).
        4. 제목에 못 담은 세부 내용이나 링크는 `--memo` 에 넣는다.
        5. 인자는 쉘에서 안전하게 따옴표로 감싼다 (작은따옴표 등 특수문자 주의).
        6. 출력된 한 줄 JSON 결과를 사용자에게 알린다. `"ok":false` 면 `error` 를 그대로 전달한다.
        7. `unknownTags` 가 비어 있지 않으면 그 태그는 ATM 에 없어서 붙지 않았다고 알린다.

        규칙:
        - 마감일과 태그를 지어내지 않는다. 말하지 않았으면 붙이지 않는다.
        - 앱이 꺼져 있어도 다음 실행 때 반영된다.

        """
    }
}
