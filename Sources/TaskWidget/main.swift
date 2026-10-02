import Foundation
import TaskWidgetCore

if CommandLine.arguments.contains("--hook") {
    // readDataToEndOfFile 은 읽기 오류 시 ObjC 예외를 던져 Swift 로 못 잡는다. readToEnd 는 throws.
    ActivityLog.handleHook(input: (try? FileHandle.standardInput.readToEnd()) ?? Data())
    exit(0)
}

print("TaskWidget data dir: \(Paths.dataDir.path)")
