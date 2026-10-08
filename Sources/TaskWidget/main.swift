import AppKit
import TaskWidgetCore

if CommandLine.arguments.contains("--hook") {
    // readDataToEndOfFile 은 읽기 오류 시 ObjC 예외를 던져 Swift 로 못 잡는다. readToEnd 는 throws.
    ActivityLog.handleHook(input: (try? FileHandle.standardInput.readToEnd()) ?? Data())
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--add-todo") {
    let r = TodoInbox.runCLI(args: Array(CommandLine.arguments[(i + 1)...]))
    print(r.output)
    exit(r.code)
}

let app = NSApplication.shared
// main.swift 최상위 코드는 Swift 5 모드에서 MainActor 가 아니다. @MainActor 클래스 생성은 명시적으로 격리.
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
