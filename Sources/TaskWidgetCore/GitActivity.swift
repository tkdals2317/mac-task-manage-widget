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

        let key = DayKey.string(from: day, calendar: calendar)
        let r = ProcessRunner.run(executable: "/usr/bin/git",
                                  arguments: ["-C", cwd, "log",
                                              "--since=\(key) 00:00:00", "--until=\(key) 23:59:59",
                                              "--format=%h %s", "-n", "30"],
                                  timeout: timeout)
        guard r.status == 0 else { return [] }
        return r.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
