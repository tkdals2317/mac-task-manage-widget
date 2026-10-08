import Foundation

public enum SummaryError: Error, Equatable {
    case claudeNotFound
    case timeout
    case claudeFailed(Int32, String)
    case emptyOutput
    case busy
    case noDailySummaries

    public var userMessage: String {
        switch self {
        case .claudeNotFound: return "claude CLI를 찾지 못했습니다. 터미널에서 `command -v claude` 결과를 설정 > 요약 > claude 경로에 넣어주세요."
        case .timeout: return "claude 응답 시간 초과"
        case .claudeFailed(let code, let tail):
            let last = tail.split(separator: "\n").last.map(String.init) ?? ""
            return "claude 실패 (exit \(code)): \(last)"
        case .emptyOutput: return "claude 출력이 비어 있음"
        case .busy: return "이미 생성 중"
        case .noDailySummaries: return "이번 주 일간 요약 없음"
        }
    }
}

public struct ClaudeRunner {
    public var configuredPath: String
    public var model: String
    public var timeout: TimeInterval
    /// 자식 프로세스 환경의 바탕. 테스트에서 주입.
    public var baseEnvironment: [String: String]

    public init(configuredPath: String = "", model: String = "", timeout: TimeInterval = 180,
                baseEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.configuredPath = configuredPath
        self.model = model
        self.timeout = timeout
        self.baseEnvironment = baseEnvironment
    }

    static func isExe(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    /// 로그인 셸에서 `command -v claude`. GUI 앱은 셸 PATH 를 못 받으므로 셸에게 묻는다.
    public static func loginShellLookup() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let r = ProcessRunner.run(executable: shell, arguments: ["-lc", "command -v claude"], timeout: 5)
        guard !r.timedOut, r.status == 0 else { return nil }
        return r.stdout.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }

    /// 디렉터리 항목을 버전 숫자 비교로 내림차순(v20.11.0 > v20.9.0).
    private static func subdirs(_ dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
    }

    /// 설정 경로 → 로그인 셸 → 기본 위치 → nvm → Claude 데스크톱 앱 순. 실행 가능한 첫 번째.
    public static func locateWithSource(configured: String,
                                        home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                        shellLookup: () -> String? = ClaudeRunner.loginShellLookup) -> (path: String, source: String)? {
        let h = home.path
        if !configured.isEmpty, isExe(configured) { return (configured, "설정 경로") }
        if let p = shellLookup(), p.hasPrefix("/"), isExe(p) { return (p, "로그인 셸") }
        let known = ["\(h)/.local/bin/claude", "\(h)/.claude/local/claude",
                     "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                     "\(h)/.npm-global/bin/claude", "\(h)/.bun/bin/claude", "\(h)/.volta/bin/claude"]
        if let p = known.first(where: isExe) { return (p, "기본 위치") }
        let nvm = "\(h)/.nvm/versions/node"
        if let p = subdirs(nvm).map({ "\(nvm)/\($0)/bin/claude" }).first(where: isExe) { return (p, "nvm") }
        let desk = "\(h)/Library/Application Support/Claude/claude-code"
        for v in subdirs(desk) {
            let vd = "\(desk)/\(v)"
            var cands = ["\(vd)/claude", "\(vd)/claude.app/Contents/MacOS/claude"]
            for sub in subdirs(vd) {
                cands += ["\(vd)/\(sub)/claude.app/Contents/MacOS/claude", "\(vd)/\(sub)/claude"]
            }
            if let p = cands.first(where: isExe) { return (p, "Claude 데스크톱 앱") }
        }
        return nil
    }

    public static func locate(configured: String,
                              home: URL = FileManager.default.homeDirectoryForCurrentUser,
                              shellLookup: () -> String? = ClaudeRunner.loginShellLookup) -> String? {
        locateWithSource(configured: configured, home: home, shellLookup: shellLookup)?.path
    }

    public func run(prompt: String, workingDirectory: URL = Paths.dataDir) throws -> String {
        try runLocated(prompt: prompt, home: FileManager.default.homeDirectoryForCurrentUser, workingDirectory: workingDirectory)
    }

    func runLocated(prompt: String, home: URL, workingDirectory: URL,
                    shellLookup: () -> String? = ClaudeRunner.loginShellLookup) throws -> String {
        guard let exe = Self.locate(configured: configuredPath, home: home, shellLookup: shellLookup) else { throw SummaryError.claudeNotFound }
        // 도구·MCP 없이 텍스트만, 세션 디스크 저장 없음 (요약은 프롬프트 안의 자료만으로 쓴다).
        var args = ["-p", "--output-format", "text", "--tools", "", "--strict-mcp-config", "--no-session-persistence"]
        if !model.isEmpty { args += ["--model", model] }

        var env = baseEnvironment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        // 바이너리 자신의 폴더를 앞에 붙인다 (`#!/usr/bin/env node` 가 nvm/npm 의 node 를 찾도록).
        let binDir = URL(fileURLWithPath: exe).deletingLastPathComponent().path
        env["PATH"] = "\(binDir):\(home.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")

        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let r = ProcessRunner.run(executable: exe, arguments: args, stdin: prompt,
                                  currentDirectory: workingDirectory, environment: env, timeout: timeout)
        if r.timedOut { throw SummaryError.timeout }
        guard r.status == 0 else {
            let detail = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? r.stdout : r.stderr
            throw SummaryError.claudeFailed(r.status, String(detail.suffix(2000)))
        }
        let out = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { throw SummaryError.emptyOutput }
        return out
    }
}
