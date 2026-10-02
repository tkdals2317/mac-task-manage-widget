import Foundation

public enum GitActivity {
    /// cwd 가 git 작업 트리면 그날의 커밋을 "<short-hash> <subject>" 줄로 최대 30개. 아니면 [].
    public static func commits(in cwd: String, on day: Date, calendar: Calendar = .current, timeout: TimeInterval = 10) -> [String] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir), isDir.boolValue else { return [] }

        let probe = ProcessRunner.run(executable: "/usr/bin/git",
                                      arguments: ["-C", cwd, "rev-parse", "--is-inside-work-tree"],
                                      timeout: timeout)
        guard probe.status == 0, probe.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else { return [] }

        // 같은 저장소의 다른 사람 커밋이 내 업무로 섞이지 않게 로컬 사용자 이메일로 거른다. 설정이 없으면 필터 없음.
        let me = ProcessRunner.run(executable: "/usr/bin/git", arguments: ["-C", cwd, "config", "user.email"], timeout: timeout)
        let email = me.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var args = ["-C", cwd, "log"]
        if me.status == 0, !email.isEmpty { args.append("--author=\(email)") }

        let key = DayKey.string(from: day, calendar: calendar)
        let r = ProcessRunner.run(executable: "/usr/bin/git",
                                  arguments: args + ["--since=\(key) 00:00:00", "--until=\(key) 23:59:59",
                                                     "--format=%h %s", "-n", "30"],
                                  timeout: timeout)
        guard r.status == 0 else { return [] }
        return r.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
