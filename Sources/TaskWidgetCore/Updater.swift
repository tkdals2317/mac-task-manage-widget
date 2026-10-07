import Foundation

public struct BuildInfo: Equatable {
    public let version, buildNumber, commit, buildDate, sourceDir: String
    public let dirty: Bool

    public init(infoDictionary d: [String: Any]) {
        func s(_ k: String, _ def: String) -> String { (d[k] as? String) ?? def }
        version = s("CFBundleShortVersionString", "unknown")
        buildNumber = s("ATMBuildNumber", "unknown")
        commit = s("ATMCommit", "unknown")
        buildDate = s("ATMBuildDate", "unknown")
        sourceDir = s("ATMSourceDir", "")
        dirty = s("ATMDirty", "false") == "true"
    }

    public var displayVersion: String {
        "\(version) (빌드 \(buildNumber) · \(commit))" + (dirty ? " · 로컬 수정 포함" : "")
    }
}

public struct UpdateStatus: Equatable {
    public let behind: Int
    public let newCommits: [String]
    public let checkedAt: Date
}

public enum UpdateError: Error, Equatable {
    case noSourceDir, notARepo, fetchFailed(String), pullFailed(String), localChanges

    public var userMessage: String {
        switch self {
        case .noSourceDir: return "소스 폴더 정보 없음"
        case .notARepo: return "git 저장소가 아님"
        case .fetchFailed(let m): return "최신 정보 받기 실패: \(m)"
        case .pullFailed(let m): return "업데이트 실패: \(m)"
        case .localChanges: return "소스 폴더에 커밋하지 않은 수정이 있음"
        }
    }
}

public struct Updater {
    public typealias Runner = (String, [String], URL?) -> ProcessResult
    public let sourceDir: String
    let runner: Runner

    public init(sourceDir: String, runner: Runner? = nil) {
        self.sourceDir = sourceDir
        self.runner = runner ?? { exe, args, cwd in
            ProcessRunner.run(executable: exe, arguments: args, currentDirectory: cwd, timeout: 60)
        }
    }

    private func git(_ args: [String]) -> ProcessResult {
        runner("/usr/bin/git", ["-C", sourceDir] + args, nil)
    }

    private func failure(_ r: ProcessResult) -> String {
        if r.timedOut { return "시간 초과" }
        let m = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? "종료 코드 \(r.status)" : m
    }

    public func check(now: Date = Date()) throws -> UpdateStatus {
        guard !sourceDir.isEmpty else { throw UpdateError.noSourceDir }
        guard git(["rev-parse", "--is-inside-work-tree"]).status == 0 else { throw UpdateError.notARepo }
        let fetch = git(["fetch", "--quiet", "origin"])
        guard fetch.status == 0 else { throw UpdateError.fetchFailed(failure(fetch)) }

        let head = git(["rev-parse", "--abbrev-ref", "HEAD"])
        var branch = head.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.status != 0 || branch.isEmpty || branch == "HEAD" { branch = "main" }
        let range = "HEAD..origin/\(branch)"

        let count = git(["rev-list", "--count", range])
        guard count.status == 0, let behind = Int(count.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw UpdateError.fetchFailed(failure(count))
        }
        var commits: [String] = []
        if behind > 0 {
            let log = git(["log", "--format=%h %s", "-n", "20", range])
            commits = log.stdout.split(separator: "\n").map(String.init)
        }
        return UpdateStatus(behind: behind, newCommits: commits, checkedAt: now)
    }

    public func hasLocalChanges() throws -> Bool {
        guard !sourceDir.isEmpty else { throw UpdateError.noSourceDir }
        let r = git(["status", "--porcelain", "--untracked-files=no"])
        guard r.status == 0 else { throw UpdateError.notARepo }
        return !r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 앱이 분리 실행하는 스크립트. make install 이 앱을 죽이므로 실패 시 설치된 앱을 다시 연다.
    public static func updateScript(sourceDir: String, logPath: String) -> String {
        """
        #!/bin/sh
        exec >> \(shellQuote(logPath)) 2>&1
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        echo "=== update $(date '+%Y-%m-%d %H:%M:%S') ==="
        fail() { open ~/Applications/ATM.app >/dev/null 2>&1; echo "UPDATE_FAILED: $1"; exit 1; }
        cd \(shellQuote(sourceDir)) || fail "cd"
        git pull --ff-only || fail "git pull"
        make install || fail "make install"
        open ~/Applications/ATM.app
        echo "UPDATE_OK"

        """
    }
}
