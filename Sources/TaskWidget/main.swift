import Foundation
import TaskWidgetCore

if CommandLine.arguments.contains("--hook") {
    ActivityLog.handleHook(input: FileHandle.standardInput.readDataToEndOfFile())
    exit(0)
}

print("TaskWidget data dir: \(Paths.dataDir.path)")
