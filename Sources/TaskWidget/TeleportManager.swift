import AppKit
import Foundation
import TaskWidgetCore

enum TunnelState: Equatable {
    case disconnected, connecting, connected
    case failed(String)
    case portInUse
}

/// tsh 로그인 상태와 DB 터널(`tsh proxy db`)을 관리한다. 터널 프로세스는 ATM 이 직접 띄우고 직접 끈다.
@MainActor
final class TeleportManager: ObservableObject {
    @Published private(set) var config: TeleportConfig
    @Published private(set) var states: [String: TunnelState] = [:] {
        didSet {
            for (n, st) in states where oldValue[n] != st {
                switch st {
                case .failed(let m): DiagLog.append("teleport tunnel \(n) failed: \(m)")
                case .portInUse: DiagLog.append("teleport tunnel \(n) portInUse")
                default: break
                }
            }
        }
    }
    @Published private(set) var validUntil: Date?
    @Published private(set) var busy: String?          // "로그인 중…" 등
    @Published private(set) var message: String?       // 마지막 오류/안내
    @Published private(set) var tshPath: String?
    @Published private(set) var hasSecrets: Bool
    /// 설정 > Teleport 의 "설정 다시 하기" 가 켠다. 탭이 설정 화면을 보여준다.
    @Published var setupRequested = false
    @Published private(set) var lastLogin: Date? = UserDefaults.standard.object(forKey: lastLoginKey) as? Date

    private static let lastLoginKey = "teleportLastLogin"
    private var procs: [String: Process] = [:]
    private var intentionalStop = Set<String>()
    /// 진행 중인 로그인. 여러 DB 를 동시에 켤 때 로그인은 한 번만 하고 나머지는 결과를 기다린다.
    private var loginTask: Task<Bool, Never>?
    /// 마지막 로그인에 쓴 OTP 구간. 같은 코드를 두 번 보내지 않는다.
    /// 마지막으로 쓴 OTP 카운터. 같은 30초 구간 코드를 두 번 쓰면 Teleport 가 거부해서, 설정 화면의 검증 로그인도 이 값을 갱신한다.
    static var lastOTPCounter: Int64?
    /// 비밀번호/OTP 가 틀려 로그인이 거부됐다. 자동 재시도가 계정 잠금으로 이어지지 않게, 사용자가 다시 입력하거나
    /// "다시 로그인"을 누르기 전까지 자동 로그인(watchdog·자동 연결)을 멈춘다.
    @Published private(set) var authFailed = false
    /// 사용자가 켜 둔 터널. 프로세스가 예기치 않게 죽어도 유지되고, 사용자가 끄면 빠진다 (자동 재연결은 포기하지 않는다).
    private var wanted = Set<String>() {
        didSet { UserDefaults.standard.set(wanted.sorted(), forKey: SettingsKey.teleportWanted) }   // 종료(shutdown)는 건드리지 않는다: 다음 실행에서 복원
    }
    /// 지난 실행에서 켜 두었던 터널. 시작 시 한 번 복원한다.
    private var pendingRestore: [String]
    private var failures: [String: Int] = [:]
    /// 실패한 터널의 다음 시도 시각 (지수 백오프).
    private var retryAt: [String: Date] = [:]
    private var watchdogBusy = false
    private var timer: Timer?
    private var timerSeconds = 0
    /// 진행 중인 tsh 로그인의 시작 시각과 취소 손잡이. 잠자기 등으로 오래 걸리면 watchdog 이 취소한다.
    private var loginStarted: Date?
    private var loginCancel: LoginCancel?
    private static let loginStuckSeconds: TimeInterval = 90
    private var observers: [NSObjectProtocol] = []
    /// 이 실행 중 터널을 띄웠거나 로그인한 적이 있나. 종료 시 남의 tsh 세션을 건드리지 않기 위한 표식.
    private var touched = false

    init() {
        config = TeleportConfig.load()
        // 데모: 키체인을 읽지 않고, tsh 는 있는 것으로 보이게 하되 실제로 부르지 않는다.
        hasSecrets = DemoFixtures.isOn ? true : TeleportSecrets.load() != nil
        pendingRestore = UserDefaults.standard.stringArray(forKey: SettingsKey.teleportWanted) ?? []
        locateTsh()
    }

    var isConfigured: Bool { !config.user.isEmpty && !config.tunnels.isEmpty && hasSecrets }
    var loggedIn: Bool { validUntil.map { $0 > Date() } ?? false }

    func state(_ t: TeleportTunnel) -> TunnelState { states[t.name] ?? .disconnected }

    static var loginLogURL: URL { Paths.logsDir.appendingPathComponent("teleport-login.log") }

    /// 실패한 터널의 로그: 로그인 실패면 로그인 기록, 아니면 tsh proxy 로그.
    func logURL(for t: TeleportTunnel) -> URL {
        if case .failed(let m) = state(t), m == message { return Self.loginLogURL }
        let u = Paths.logsDir.appendingPathComponent("teleport-\(t.name).log")
        return FileManager.default.fileExists(atPath: u.path) ? u : Self.loginLogURL
    }

    func locateTsh() {
        if DemoFixtures.isOn { tshPath = "/usr/bin/false"; return }
        tshPath = TeleportTsh.locate(configured: Settings.shared.tshPath)
    }

    func reloadConfig() {
        config = TeleportConfig.load()
        hasSecrets = DemoFixtures.isOn ? true : TeleportSecrets.load() != nil
        authFailed = false   // 비밀 정보를 다시 넣었을 수 있으니 자동 로그인을 다시 허용
    }

    func setupFinished(_ c: TeleportConfig) {
        config = c
        hasSecrets = TeleportSecrets.load() != nil
        authFailed = false
        setupRequested = false
        for t in c.tunnels where states[t.name] == nil { states[t.name] = .disconnected }
        Task { await refreshStatus() }
    }

    func start() {
        guard !DemoFixtures.isOn else { return }
        Task { await refreshStatus() }
        scheduleTimer()
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self, self.timerSeconds != Settings.shared.teleportCheckSeconds { self.scheduleTimer() }
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })
    }

    /// 확인 주기(설정)대로 타이머를 (다시) 만든다. 세션 상태 갱신도 같은 타이머를 쓴다.
    private func scheduleTimer() {
        timer?.invalidate()
        timerSeconds = Settings.shared.teleportCheckSeconds
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timerSeconds), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard tshPath != nil, config.user != "" else { return }
        Task { await refreshStatus(); await watchdog() }
    }

    /// 잠자기에서 깨면 네트워크가 올라올 시간(5초)을 두고 바로 확인한다. 백오프 대기는 건너뛴다.
    private func didWake() {
        guard !wanted.isEmpty else { return }
        DiagLog.append("teleport wake: check in 5s (wanted=\(wanted.sorted().joined(separator: ",")))")
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            retryAt.removeAll()
            tick()
        }
    }

    // MARK: - 로그인 상태

    func refreshStatus() async {
        guard !DemoFixtures.isOn else { return }
        guard let tsh = tshPath else { validUntil = nil; return }
        let r = await Task.detached { ProcessRunner.run(executable: tsh, arguments: ["status", "--format=json"], timeout: 10) }.value
        validUntil = r.status == 0 ? TeleportTsh.parseSessionExpiry(json: Data(r.stdout.utf8)) : nil
    }

    /// 저장된 비밀번호/OTP 키로 로그인. 이미 유효하면 아무것도 안 한다.
    @discardableResult
    func ensureLoggedIn(force: Bool = false, kind: String = "connect") async -> Bool {
        guard !DemoFixtures.isOn else { return false }
        if let t = loginTask { return await t.value }
        let t = Task { await self.performLogin(force: force, kind: kind) }
        loginTask = t
        let ok = await t.value
        loginTask = nil
        return ok
    }

    private func performLogin(force: Bool, kind: String) async -> Bool {
        guard let tsh = tshPath else { message = "tsh 가 설치되어 있지 않아요"; return false }
        if authFailed && kind != "manual" && kind != "setup" {
            message = Self.authFailedMessage
            return false
        }
        if !force {
            await refreshStatus()
            if loggedIn { return true }
        }
        guard let sec = TeleportSecrets.load(), let totp = TOTP(input: sec.otpSecret), !config.user.isEmpty else {
            message = "Teleport 설정이 필요해요"; return false
        }
        busy = "로그인 중…"; message = nil
        defer { busy = nil }
        var login = TeleportLogin(tsh: tsh, proxy: config.proxy, user: config.user)
        let cancel = LoginCancel()
        login.cancel = cancel
        loginCancel = cancel; loginStarted = Date()
        defer { loginCancel = nil; loginStarted = nil }
        let last = Self.lastOTPCounter
        let used = OTPBox()
        // Task.detached 안에서 var 를 쓰면 Swift 5.10 이 "captured var in concurrently-executing code" 로 막는다. 복사본을 넘긴다.
        let runner = login
        var (res, report) = await Task.detached {
            runner.runReported(password: sec.password, otp: { let r = totp.freshCode(after: last); used.counter = r.counter; return r.code })
        }.value
        TeleportLoginLog.append(kind: kind, user: config.user, proxy: config.proxy, tsh: tsh, report: report, result: res)
        // 빈 인증서 파일 때문에 tsh 가 바로 죽으면 그 파일만 지우고 한 번 더 시도한다.
        if case .failure(let e) = res, e.message.contains(TshProfileRepair.errorMarker) {
            let removed = await Task.detached { TshProfileRepair.removeEmptyFiles() }.value
            if !removed.isEmpty {
                DiagLog.append("teleport: 빈 tsh 인증서 파일 정리 후 재시도: \(removed.joined(separator: ", "))")
                (res, report) = await Task.detached {
                    runner.runReported(password: sec.password, otp: { let r = totp.freshCode(after: used.counter ?? last); used.counter = r.counter; return r.code })
                }.value
                TeleportLoginLog.append(kind: kind + "+repair", user: config.user, proxy: config.proxy, tsh: tsh, report: report, result: res)
            }
        }
        if let c = used.counter { Self.lastOTPCounter = c }
        switch res {
        case .success:
            touched = true
            authFailed = false
            lastLogin = Date()
            UserDefaults.standard.set(lastLogin, forKey: Self.lastLoginKey)
            await refreshStatus()
            return loggedIn
        case .failure(let e):
            if TeleportTsh.isAuthFailure(e.message) {
                authFailed = true
                message = Self.authFailedMessage
                DiagLog.append("teleport: 인증 실패로 자동 로그인 중지 (\(kind))")
            } else {
                message = e.message
            }
            return false
        }
    }

    static let authFailedMessage = "비밀번호나 OTP 키가 맞지 않아 자동 로그인을 멈췄어요. 설정 > Teleport > 설정 다시 하기에서 다시 입력해 주세요."



    // MARK: - 터널

    /// 사용자가 켠 터널. 이후 watchdog 이 살아 있게 유지한다.
    func connect(_ t: TeleportTunnel) async {
        guard !DemoFixtures.isOn else { return }
        wanted.insert(t.name); failures[t.name] = 0; retryAt[t.name] = nil
        await open(t)
    }

    /// ATM 이 강제 종료돼 남은 같은 터널 프로세스는 정리하고 다시 띄운다.
    private func reclaimLeftover(_ t: TeleportTunnel) async {
        let pids = await Task.detached { TeleportTsh.leftoverTunnelPIDs(port: t.port, name: t.name) }.value
        guard !pids.isEmpty else { return }
        for pid in pids { kill(pid, SIGTERM) }
        for _ in 0..<20 where TeleportTsh.isListening(port: t.port) {   // ~2초
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func open(_ t: TeleportTunnel) async {
        if let p = procs[t.name], p.isRunning { return }
        await reclaimLeftover(t)
        if TeleportTsh.isListening(port: t.port) { states[t.name] = .portInUse; return }
        states[t.name] = .connecting
        guard await ensureLoggedIn(), let tsh = tshPath else {
            states[t.name] = .failed(message ?? "로그인 필요"); return
        }
        // 로그인 중 다른 경로로 이미 떴을 수 있다.
        if let p = procs[t.name], p.isRunning { return }
        if TeleportTsh.isListening(port: t.port) { states[t.name] = .portInUse; return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: tsh)
        p.arguments = ["proxy", "db", "--tunnel", t.name, "--db-user", t.dbUser, "--port", String(t.port)]
        let logURL = Paths.logsDir.appendingPathComponent("teleport-\(t.name).log")
        try? FileManager.default.createDirectory(at: Paths.logsDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let h = try? FileHandle(forWritingTo: logURL) { p.standardOutput = h; p.standardError = h }
        p.standardInput = FileHandle.nullDevice
        let name = t.name
        p.terminationHandler = { [weak self] proc in
            let me = self   // Swift 5.10: weak self(var)를 바깥 클로저에서 let 으로 옮겨야 넘길 수 있다
            DispatchQueue.main.async {
                MainActor.assumeIsolated { me?.exited(name, proc) }
            }
        }
        do { try p.run() } catch {
            states[name] = .failed("실행 실패: \(error.localizedDescription)"); return
        }
        touched = true
        procs[name] = p

        for _ in 0..<40 {   // ~10초
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard procs[name] === p, p.isRunning else { return }   // exited() 가 상태를 정한다
            if TeleportTsh.isListening(port: t.port) { states[name] = .connected; return }
        }
        states[name] = .failed("10초 안에 열리지 않았어요 (로그 확인)")
        stop(name)
    }

    private func exited(_ name: String, _ proc: Process) {
        guard procs[name] === proc else { return }
        procs[name] = nil
        if intentionalStop.remove(name) != nil { states[name] = .disconnected; return }
        states[name] = proc.terminationStatus == 0 ? .disconnected : .failed("tsh 종료 (exit \(proc.terminationStatus)) · 로그 확인")
    }

    private func stop(_ name: String) {
        guard let p = procs[name] else { states[name] = .disconnected; return }
        intentionalStop.insert(name)
        p.terminate()
    }

    func disconnect(_ t: TeleportTunnel) { wanted.remove(t.name); stop(t.name) }

    func connectAll() async {
        guard !DemoFixtures.isOn else { return }
        guard await ensureLoggedIn() else { return }
        await withTaskGroup(of: Void.self) { g in
            for t in config.tunnels where state(t) != .connected { g.addTask { @MainActor in await self.connect(t) } }
        }
    }

    /// ATM 시작 시: 지난번에 켜 둔 터널을 다시 연결한다 (로그인이 필요하면 자동 로그인).
    func restoreWanted(tabEnabled: Bool) async {
        guard !DemoFixtures.isOn else { return }
        let saved = pendingRestore; pendingRestore = []
        guard tabEnabled, isConfigured, tshPath != nil else { return }
        let names = TeleportAutoConnect.namesToRestore(persisted: saved, configured: config.tunnels.map(\.name),
                                                       enabled: Settings.shared.teleportAutoConnect)
        guard !names.isEmpty else { return }
        await withTaskGroup(of: Void.self) { g in
            for t in config.tunnels where names.contains(t.name) && state(t) != .connected {
                g.addTask { @MainActor in await self.connect(t) }
            }
        }
    }

    // MARK: - 자동 유지

    /// 주기마다: 켜 둔 터널이 응답하는지(프로세스 + 포트 리슨) 보고, 아니면 (필요하면 재로그인 후) 다시 연결한다.
    /// 실패해도 포기하지 않고 간격을 늘려(최대 5분) 계속 시도한다.
    private func watchdog() async {
        // 로그인이 너무 오래 걸리면(잠자기 등으로 멈춘 경우) 중단시킨다. 실패로 처리되어 백오프 후 다시 시도한다.
        if loginTask != nil, let s = loginStarted, Date().timeIntervalSince(s) > Self.loginStuckSeconds {
            DiagLog.append("teleport watchdog: login stuck \(Int(Date().timeIntervalSince(s)))s, cancel")
            loginCancel?.cancel()
            return
        }
        guard isConfigured, tshPath != nil, !wanted.isEmpty, !watchdogBusy, loginTask == nil else { return }
        watchdogBusy = true; defer { watchdogBusy = false }
        // 사용자가 연결 중인 터널은 건드리지 않는다.
        let names = config.tunnels.map(\.name).filter { wanted.contains($0) && states[$0] != .connecting }
        let running = Set(names.filter { procs[$0]?.isRunning == true })
        let healthy = Set(config.tunnels.filter { running.contains($0.name) && TeleportTsh.isListening(port: $0.port) }.map(\.name))
        for n in healthy { failures[n] = 0; retryAt[n] = nil }
        let p = TeleportWatchdogPolicy.decide(wanted: names, running: running, healthy: healthy,
                                              retryAt: retryAt, loggedIn: loggedIn)
        for (n, left) in p.waiting {
            states[n] = .failed("재연결 대기 · \(TeleportWatchdogPolicy.waitText(left))")
        }
        if p.relogin {
            DiagLog.append("teleport watchdog: relogin (wanted=\(p.restart.joined(separator: ",")))")
            if !(await ensureLoggedIn(force: true, kind: "watchdog")) {
                DiagLog.append("teleport watchdog: relogin failed: \(message ?? "?")")
                for n in p.restart { fail(n) }
                return
            }
        }
        if !p.restart.isEmpty { DiagLog.append("teleport watchdog: restart \(p.restart.joined(separator: ","))") }
        for n in p.restart {
            guard wanted.contains(n), let t = config.tunnels.first(where: { $0.name == n }) else { continue }
            if procs[n] != nil {
                stop(n)
                for _ in 0..<20 where procs[n] != nil { try? await Task.sleep(nanoseconds: 100_000_000) }
            }
            await open(t)
            if states[n] == .connected { failures[n] = 0; retryAt[n] = nil } else { fail(n) }
        }
    }

    private func fail(_ n: String) {
        failures[n, default: 0] += 1
        let wait = TeleportWatchdogPolicy.backoff(failures: failures[n]!, interval: TimeInterval(Settings.shared.teleportCheckSeconds))
        retryAt[n] = Date().addingTimeInterval(wait)
        DiagLog.append("teleport watchdog: \(n) failure #\(failures[n]!), next try in \(Int(wait))s")
    }

    /// 터널 종료 + `tsh db logout` 각각 + `tsh logout` (Python 도구와 같은 순서).
    func disconnectAll() async {
        guard !DemoFixtures.isOn else { return }
        let names = config.tunnels.map(\.name)
        wanted.removeAll()
        for n in procs.keys { stop(n) }
        guard let tsh = tshPath else { return }
        busy = "끊는 중…"
        await Task.detached { Self.logout(tsh: tsh, names: names, timeout: 10) }.value
        busy = nil
        validUntil = nil
    }

    /// 종료 시 동기 호출. 이 실행에서 건드린 게 없으면 아무것도 안 한다.
    func shutdown() {
        guard touched else { return }
        for p in procs.values { p.terminate() }
        for p in procs.values where p.isRunning { usleep(100_000) }
        if let tsh = tshPath { Self.logout(tsh: tsh, names: config.tunnels.map(\.name), timeout: 3) }
    }

    nonisolated private static func logout(tsh: String, names: [String], timeout: TimeInterval) {
        DispatchQueue.concurrentPerform(iterations: names.count) { i in
            _ = ProcessRunner.run(executable: tsh, arguments: ["db", "logout", names[i]], timeout: timeout)
        }
        _ = ProcessRunner.run(executable: tsh, arguments: ["logout"], timeout: timeout)
    }
}

/// 로그인 중(백그라운드)에 실제로 쓴 OTP 구간을 넘겨받는 상자.
private final class OTPBox: @unchecked Sendable { var counter: Int64? }
