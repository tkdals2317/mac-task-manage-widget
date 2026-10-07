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
        // --author 는 "Name <email>" 에 대한 정규식이라 <> 로 감싸야 kim@co.com 이 jkim@co.com 에 걸리지 않는다.
        let me = ProcessRunner.run(executable: "/usr/bin/git", arguments: ["-C", cwd, "config", "user.email"], timeout: timeout)
        let email = me.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var args = ["-C", cwd, "log"]
        if me.status == 0, !email.isEmpty { args.append("--author=<\(email)>") }

        let key = DayKey.string(from: day, calendar: calendar)
        let r = ProcessRunner.run(executable: "/usr/bin/git",
                                  arguments: args + ["--since=\(key) 00:00:00", "--until=\(key) 23:59:59",
                                                     "--format=%h %s", "-n", "30"],
                                  timeout: timeout)
        guard r.status == 0 else { return [] }
        return r.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// cwd 의 현재 브랜치 이름. 저장소가 아니거나 detached 면 nil.
    public static func branch(in cwd: String, timeout: TimeInterval = 10) -> String? {
        let r = ProcessRunner.run(executable: "/usr/bin/git", arguments: ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"], timeout: timeout)
        let b = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.status == 0 && !b.isEmpty && b != "HEAD" ? b : nil
    }
}
