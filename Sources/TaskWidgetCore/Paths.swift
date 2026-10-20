import Foundation

public enum Paths {
    public static var dataDir: URL { dataDir(env: ProcessInfo.processInfo.environment) }

    /// `ATM_DATA_DIR` 가 있으면 그 폴더 (스크린샷 데모용), 없으면 Application Support/TaskWidget.
    static func dataDir(env: [String: String]) -> URL {
        if let p = env["ATM_DATA_DIR"], !p.isEmpty { return URL(fileURLWithPath: p, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TaskWidget", isDirectory: true)
    }
    public static var todosFile: URL { dataDir.appendingPathComponent("todos.json") }
    public static var notesFile: URL { dataDir.appendingPathComponent("notes.json") }
    public static var activityFile: URL { dataDir.appendingPathComponent("activity.jsonl") }
    public static var worklogDir: URL { dataDir.appendingPathComponent("worklog", isDirectory: true) }
    public static var summariesDir: URL { dataDir.appendingPathComponent("summaries", isDirectory: true) }
    public static var teleportFile: URL { dataDir.appendingPathComponent("teleport.json") }
    public static var secretsFile: URL { dataDir.appendingPathComponent("secrets.json") }
    public static var logsDir: URL { dataDir.appendingPathComponent("logs", isDirectory: true) }
    public static var claudeDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    public static func ensureDirectories() throws {
        for dir in [dataDir, worklogDir, summariesDir, logsDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
