import Foundation

public enum SummaryError: Error, Equatable {
    case claudeNotFound
    case timeout
    case claudeFailed(Int32, String)
    case emptyOutput
    case busy

    public var userMessage: String {
        switch self {
        case .claudeNotFound: return "claude CLI 없음. 설정에서 경로 지정"
        case .timeout: return "claude 응답 시간 초과"
        case .claudeFailed(let code, let tail):
            let last = tail.split(separator: "\n").last.map(String.init) ?? ""
            return "claude 실패 (exit \(code)): \(last)"
        case .emptyOutput: return "claude 출력이 비어 있음"
        case .busy: return "이미 생성 중"
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

    /// 설정 경로 → ~/.local/bin → /opt/homebrew/bin → /usr/local/bin 순. 실행 가능한 첫 번째.
    public static func locate(configured: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        var candidates: [String] = []
        if !configured.isEmpty { candidates.append(configured) }
        candidates += [
            home.appendingPathComponent(".local/bin/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func run(prompt: String, workingDirectory: URL = Paths.dataDir) throws -> String {
        try runLocated(prompt: prompt, home: FileManager.default.homeDirectoryForCurrentUser, workingDirectory: workingDirectory)
    }

    func runLocated(prompt: String, home: URL, workingDirectory: URL) throws -> String {
        guard let exe = Self.locate(configured: configuredPath, home: home) else { throw SummaryError.claudeNotFound }
        // 도구·MCP 없이 텍스트만, 세션 디스크 저장 없음 (요약은 프롬프트 안의 자료만으로 쓴다).
        var args = ["-p", "--output-format", "text", "--tools", "", "--strict-mcp-config", "--no-session-persistence"]
        if !model.isEmpty { args += ["--model", model] }

        var env = baseEnvironment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(homePath)/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")

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
