import Darwin
import Foundation

public struct E2ERunOptions {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var timeout: TimeInterval
    /// Aside 가 읽고 쓰는 실행용 폴더 (`AsideCLI.workDir`). 실행 중에만 있고 끝나면 결과만 job 폴더로 가져온 뒤 지운다.
    public var workDir: URL
    /// SIGTERM 뒤 SIGKILL 까지 기다리는 시간.
    public var killGrace: TimeInterval
    /// SIGKILL 까지 간 경우 남았을 수 있는 Aside 세션을 멈춘다 (백그라운드에서 부른다).
    public var stopSession: ((String) -> Void)?
    /// 실행 전에 run.log 에 남길 줄 (예: Jira 내용을 못 받은 이슈).
    public var logNotes: [String]

    public init(executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval,
                workDir: URL, killGrace: TimeInterval = 5, stopSession: ((String) -> Void)? = nil, logNotes: [String] = []) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.timeout = timeout
        self.workDir = workDir
        self.killGrace = killGrace
        self.stopSession = stopSession
        self.logNotes = logNotes
    }
}

/// 실행 중 stdout/stderr 를 run.log 에 줄 단위로 적는다.
final class E2ERunLog {
    private let lock = NSLock()
    private let handle: FileHandle?
    private var partial: [Int: Data] = [:]
    private var tailText = ""
    private var session: String?
    private static let maxLine = 64 * 1024

    init(url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) { try? OwnerOnlyFile.write(Data(), to: url) }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    var sessionId: String? { lock.lock(); defer { lock.unlock() }; return session }
    var tail: String { lock.lock(); defer { lock.unlock() }; return tailText }

    func note(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        write("[ATM \(DiagLog.timestamp())] \(line)")
    }

    /// stream 0 = stdout, 1 = stderr
    func append(_ data: Data, stream: Int) {
        lock.lock(); defer { lock.unlock() }
        var buf = (partial[stream] ?? Data()) + data
        while let nl = buf.firstIndex(of: 0x0A) {
            emit(String(decoding: buf[buf.startIndex..<nl], as: UTF8.self), stream: stream)
            buf = Data(buf[buf.index(after: nl)...])
        }
        if buf.count > Self.maxLine {
            emit(String(decoding: buf, as: UTF8.self), stream: stream)
            buf = Data()
        }
        partial[stream] = buf
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        for (s, d) in partial.sorted(by: { $0.key < $1.key }) where !d.isEmpty { emit(String(decoding: d, as: UTF8.self), stream: s) }
        partial = [:]
        try? handle?.close()
    }

    private func emit(_ raw: String, stream: Int) {
        if stream == 1, session == nil, let id = AsideCLI.sessionId(in: raw) { session = id }
        tailText += raw + "\n"
        if tailText.count > 4000 { tailText = String(tailText.suffix(3000)) }
        write(stream == 1 ? "[err] \(raw)" : raw)
    }

    private func write(_ line: String) {
        try? handle?.write(contentsOf: Data((line + "\n").utf8))
    }
}

/// aside 실행을 한 번에 하나씩 돌린다 (브라우저를 같이 쓰므로). 실행이 끝나면(성공·실패·취소·시간 초과·앱 종료)
/// 실행용 폴더에서 결과만 job 폴더로 가져오고 실행용 폴더를 지운다.
public final class E2ERunner {
    public let store: E2EJobStore
    /// job 상태가 바뀔 때 (시작·끝·대기 취소). 내부 큐에서 불린다.
    public var onUpdate: ((E2EJob) -> Void)?

    private final class Running {
        let job: E2EJob
        let options: E2ERunOptions
        let process: Process
        let log: E2ERunLog
        let streams = DispatchGroup()
        var pipes: [Pipe] = []
        var cancelled = false
        var cancelReason: String?
        var timedOut = false
        var killed = false
        var timer: DispatchSourceTimer?

        init(job: E2EJob, options: E2ERunOptions, process: Process, log: E2ERunLog) {
            self.job = job
            self.options = options
            self.process = process
            self.log = log
        }
    }

    private let q = DispatchQueue(label: "com.lsm0506.TaskWidget.e2e-runner")
    private var current: Running?
    private var pending: [(job: E2EJob, options: E2ERunOptions)] = []
    private let idle = DispatchGroup()

    public init(store: E2EJobStore = E2EJobStore()) {
        self.store = store
    }

    public var state: (running: String?, queued: [String]) {
        q.sync { (current?.job.id, pending.map(\.job.id)) }
    }

    public func enqueue(_ job: E2EJob, options: E2ERunOptions) {
        idle.enter()
        q.async {
            self.pending.append((job, options))
            self.pump()
        }
    }

    /// 대기 중이면 빼고 cancelled 로, 실행 중이면 프로세스를 멈춘다.
    public func cancel(jobId: String) {
        q.async {
            if let r = self.current, r.job.id == jobId {
                r.cancelled = true
                r.log.note("사용자가 취소")
                self.stop(r)
            } else if let i = self.pending.firstIndex(where: { $0.job.id == jobId }) {
                let p = self.pending.remove(at: i)
                self.close(p.job, status: .cancelled, error: nil, sessionId: nil)
            }
        }
    }

    @discardableResult
    public func waitUntilIdle(timeout: TimeInterval) -> Bool {
        idle.wait(timeout: .now() + timeout) == .success
    }

    /// 앱 종료 시: 대기열을 비우고 실행 중인 것을 멈춘 뒤 잠깐 기다린다.
    /// 그 안에 안 끝나면 남은 실행용 폴더는 다음 실행 때 `E2EJobStore.pruneWorkDirs` 가 지운다.
    public func shutdown(timeout: TimeInterval = 3) {
        q.sync {
            for p in pending { close(p.job, status: .cancelled, error: "ATM 을 종료해서 취소했어요", sessionId: nil) }
            pending = []
            if let r = current {
                r.cancelled = true
                r.cancelReason = "ATM 을 종료해서 멈췄어요"
                r.log.note("ATM 종료로 중지")
                stop(r)
            }
        }
        waitUntilIdle(timeout: timeout)
    }

    // MARK: - 내부 (q 위에서만)

    private func pump() {
        guard current == nil, !pending.isEmpty else { return }
        let next = pending.removeFirst()
        start(next.job, next.options)
    }

    private func start(_ job: E2EJob, _ o: E2ERunOptions) {
        let log = E2ERunLog(url: store.logFile(job.id))
        log.note("시작 env=\(job.env.rawValue) issues=\(job.issueKeys.joined(separator: ",")) timeout=\(Int(o.timeout))s")
        log.note("실행 \(o.executable) \(o.arguments.dropLast().joined(separator: " ")) <지시문>")
        log.note("실행용 폴더 \(o.workDir.path)")
        for n in o.logNotes { log.note(n) }
        func fail(_ message: String) {
            log.note(message)
            log.close()
            try? FileManager.default.removeItem(at: o.workDir)
            close(job, status: .failed, error: message, sessionId: nil)
            pump()
        }
        do {
            try store.prepareWorkDir(job, at: o.workDir)
            try store.patch(job.id, set: ["status": E2EJobStatus.running.rawValue])
        } catch {
            return fail("요청 파일을 쓰지 못했어요: \(error.localizedDescription)")
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: o.executable)
        p.arguments = o.arguments
        p.environment = o.environment
        // 실제 aside(guard)는 작업 폴더를 무시하고 계정 폴더에서 돈다. 테스트용 가짜 aside 가 $PWD 로 실행용 폴더를 안다.
        p.currentDirectoryURL = o.workDir
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let r = Running(job: job, options: o, process: p, log: log)
        r.pipes = [out, err]
        for (i, pipe) in [out, err].enumerated() {
            r.streams.enter()
            let ended = Flag()
            pipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty {
                    h.readabilityHandler = nil
                    if ended.set() { r.streams.leave() }
                } else {
                    log.append(d, stream: i)
                }
            }
        }
        p.terminationHandler = { [weak self] _ in
            // Swift 5.10: weak self(var)를 안쪽 클로저로 바로 넘기면 막힌다. let 으로 옮겨 넘긴다.
            let me = self
            // 손자 프로세스가 파이프를 쥐고 있으면 EOF 가 안 온다. 오래 기다리지 않는다.
            DispatchQueue.global().async {
                let drained = r.streams.wait(timeout: .now() + 3) == .success
                me?.q.async { me?.finalize(r, drained: drained) }
            }
        }
        do {
            try p.run()
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            return fail("aside 를 실행하지 못했어요: \(error.localizedDescription)")
        }
        current = r
        store.writePid(p.processIdentifier, for: job.id)
        log.note("pid \(p.processIdentifier)")
        if let j = store.load(job.id) { onUpdate?(j) }

        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now() + o.timeout)
        t.setEventHandler { [weak self] in
            guard let self, self.current === r else { return }
            r.timedOut = true
            r.log.note("제한 시간 \(Int(o.timeout))s 초과 → 중지")
            self.stop(r)
        }
        t.resume()
        r.timer = t
    }

    private func stop(_ r: Running) {
        let pid = r.process.processIdentifier
        guard r.process.isRunning, pid > 0 else { return }
        Self.signalTree(pid, SIGTERM)
        q.asyncAfter(deadline: .now() + r.options.killGrace) { [weak self] in
            guard let self, self.current === r, r.process.isRunning else { return }
            r.killed = true
            r.log.note("SIGTERM 에 응답 없음 → SIGKILL")
            Self.signalTree(pid, SIGKILL)
        }
    }

    /// Process 로 띄운 자식은 자기 프로세스 그룹의 리더라서, 그룹 전체에 보내면 손자까지 멈춘다.
    /// groupOnly: 자식이 이미 끝난 뒤라 pid 가 재사용됐을 수 있으면 그룹에만 보낸다.
    static func signalTree(_ pid: Int32, _ sig: Int32, groupOnly: Bool = false) {
        if kill(-pid, sig) != 0, !groupOnly { kill(pid, sig) }
    }

    private func finalize(_ r: Running, drained: Bool) {
        guard current === r else { return }
        current = nil
        r.timer?.cancel()
        // 파이프를 쥔 채 남은 손자 프로세스 정리 (그룹이 남아 있는 동안은 같은 id 가 재사용되지 않는다)
        if !drained {
            Self.signalTree(r.process.processIdentifier, SIGTERM, groupOnly: true)
            for p in r.pipes { p.fileHandleForReading.readabilityHandler = nil }
        }
        let code = r.process.terminationStatus
        let sessionId = r.log.sessionId
        r.log.note("종료 exit=\(code)\(sessionId.map { " session=\($0)" } ?? "")")
        // SIGTERM 으로 끝난 CLI 는 세션도 멈추지만, SIGKILL·다른 신호로 죽으면 세션이 남을 수 있다.
        let diedBySignal = r.killed || r.process.terminationReason == .uncaughtSignal
        if diedBySignal, let sid = sessionId, let stopSession = r.options.stopSession {
            DispatchQueue.global().async { stopSession(sid) }
        }
        let skipped = store.importResults(from: r.options.workDir, into: r.job.id)
        if !skipped.isEmpty { r.log.note("가져오지 않은 파일 (이미지·result.json 이 아니거나 링크·너무 큼): \(skipped.joined(separator: ", "))") }
        let (status, error) = Self.outcome(cancelled: r.cancelled, cancelReason: r.cancelReason, timedOut: r.timedOut,
                                           timeout: r.options.timeout, result: store.result(r.job.id),
                                           exitCode: code, output: r.log.tail)
        r.log.note("결과 \(status.rawValue)\(error.map { " · \($0)" } ?? "")")
        r.log.close()
        close(r.job, status: status, error: error, sessionId: sessionId)
        pump()
    }

    /// job 을 끝내고 알린다. enqueue 한 job 마다 정확히 한 번 불린다.
    private func close(_ job: E2EJob, status: E2EJobStatus, error: String?, sessionId: String?) {
        var out = job
        out.status = status
        out.error = error
        if let saved = try? store.finish(job, status: status, error: error, sessionId: sessionId) { out = saved }
        onUpdate?(out)
        idle.leave()
    }

    static func outcome(cancelled: Bool, cancelReason: String?, timedOut: Bool, timeout: TimeInterval,
                        result: E2EResultLoad, exitCode: Int32, output: String) -> (E2EJobStatus, String?) {
        if cancelled { return (.cancelled, cancelReason) }
        if case .ok(let r) = result {
            return r.issues.isEmpty ? (.failed, "result.json 에 이슈 결과가 없어요") : (.done, nil)
        }
        if timedOut { return (.failed, "제한 시간 \(max(1, Int(timeout / 60)))분을 넘겨 멈췄어요") }
        if case .invalid(let m) = result { return (.failed, "result.json 을 읽지 못했어요 (\(m))") }
        return (.failed, E2EFailureHint.missingResult(exitCode: exitCode, output: output))
    }
}

/// 한 번만 true 를 돌려주는 깃발 (EOF 가 두 번 와도 DispatchGroup.leave 는 한 번).
private final class Flag {
    private let lock = NSLock()
    private var done = false
    func set() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
