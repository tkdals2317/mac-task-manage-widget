import Foundation

public struct ProcessResult {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool
}

public enum ProcessRunner {
    /// 자식이 stdin 을 닫은 뒤 write 하면 SIGPIPE 로 프로세스가 죽는다. 한 번만 무시 설정.
    private static let ignoreSigpipe: Void = { _ = signal(SIGPIPE, SIG_IGN) }()

    public static func run(executable: String,
                           arguments: [String],
                           stdin: String? = nil,
                           currentDirectory: URL? = nil,
                           environment: [String: String]? = nil,
                           timeout: TimeInterval) -> ProcessResult {
        _ = ignoreSigpipe
        // timeout 은 run 전체(쓰기·종료 대기·출력 수거)를 묶는다. I/O 전에 마감 시각을 하나 정한다.
        let deadline = DispatchTime.now() + timeout
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        if let cwd = currentDirectory { p.currentDirectoryURL = cwd }
        if let env = environment { p.environment = env }

        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = inPipe

        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }

        do {
            try p.run()
        } catch {
            return ProcessResult(status: -1, stdout: "", stderr: "\(error)", timedOut: false)
        }

        // 읽기를 먼저 시작해야 큰 stdin 쓰기와 자식 stdout 쓰기가 서로 막히지 않는다.
        // @Sendable 클로저 안에서 캡처한 var 를 바꾸면 컴파일 에러라 참조 타입 박스를 쓴다.
        let out = DataBox(), err = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { out.data = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { err.data = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        // stdin 을 안 읽는 자식이면 write 가 영원히 막힌다. 호출 스레드에서 쓰면 timeout 이 시작도 못 하므로 백그라운드로.
        // 자식이 죽으면 write 가 EPIPE 로 풀린다(SIGPIPE 는 무시 중).
        let input = stdin.map { Data($0.utf8) }
        DispatchQueue.global().async {
            if let input { try? inPipe.fileHandleForWriting.write(contentsOf: input) }
            try? inPipe.fileHandleForWriting.close()
        }

        let timedOut = done.wait(timeout: deadline) == .timedOut
        if timedOut {
            p.terminate()
            if done.wait(timeout: .now() + 2) == .timedOut {
                // SIGTERM 을 무시하는 자식 → SIGKILL
                kill(p.processIdentifier, SIGKILL)
                _ = done.wait(timeout: .now() + 2)
            }
        }
        // 자식이 정상 종료해도 손자가 파이프를 쥐고 있으면 EOF 가 안 온다. 영원히 기다리지 않는다.
        if group.wait(timeout: max(deadline, .now()) + 2) == .timedOut {
            // 리더 스레드가 아직 DataBox 에 쓸 수 있으니 읽지 않는다(data race).
            return ProcessResult(status: -1, stdout: "", stderr: "", timedOut: true)
        }

        // 아직 살아 있으면 terminationStatus 접근이 NSInvalidArgumentException. -1 로 보고.
        let status: Int32 = p.isRunning ? -1 : p.terminationStatus
        return ProcessResult(status: status,
                             stdout: String(decoding: out.data, as: UTF8.self),
                             stderr: String(decoding: err.data, as: UTF8.self),
                             timedOut: timedOut)
    }
}

private final class DataBox {
    var data = Data()
}
