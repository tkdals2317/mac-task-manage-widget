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
    @Published private(set) var states: [String: TunnelState] = [:]
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
    /// 사용자가 켜 둔 터널. 프로세스가 예기치 않게 죽어도 유지되고, 사용자가 끄거나 자동 재연결을 포기하면 빠진다.
    private var wanted = Set<String>() {
        didSet { UserDefaults.standard.set(wanted.sorted(), forKey: SettingsKey.teleportWanted) }   // 종료(shutdown)는 건드리지 않는다: 다음 실행에서 복원
    }
    /// 지난 실행에서 켜 두었던 터널. 시작 시 한 번 복원한다.
    private var pendingRestore: [String]
    private var failures: [String: Int] = [:]
    private var watchdogBusy = false
    private var timer: Timer?
    /// 이 실행 중 터널을 띄웠거나 로그인한 적이 있나. 종료 시 남의 tsh 세션을 건드리지 않기 위한 표식.
    private var touched = false

    init() {
        config = TeleportConfig.load()
        hasSecrets = TeleportSecrets.load() != nil
        pendingRestore = UserDefaults.standard.stringArray(forKey: SettingsKey.teleportWanted) ?? []
        locateTsh()
    }

    var isConfigured: Bool { !config.user.isEmpty && !config.tunnels.isEmpty && hasSecrets }
    var loggedIn: Bool { validUntil.map { $0 > Date() } ?? false }

    func state(_ t: TeleportTunnel) -> TunnelState { states[t.name] ?? .disconnected }

    func locateTsh() {
        tshPath = TeleportTsh.locate(configured: Settings.shared.tshPath)
    }

    func reloadConfig() {
        config = TeleportConfig.load()
        hasSecrets = TeleportSecrets.load() != nil
    }

    func setupFinished(_ c: TeleportConfig) {
        config = c
        hasSecrets = TeleportSecrets.load() != nil
        setupRequested = false
        for t in c.tunnels where states[t.name] == nil { states[t.name] = .disconnected }
        Task { await refreshStatus() }
    }

    func start() {
        Task { await refreshStatus() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self, self.tshPath != nil, self.config.user != "" {
                    Task { await self.refreshStatus(); await self.watchdog() }
                }
            }
        }
    }

    // MARK: - 로그인 상태

    func refreshStatus() async {
        guard let tsh = tshPath else { validUntil = nil; return }
        let r = await Task.detached { ProcessRunner.run(executable: tsh, arguments: ["status", "--format=json"], timeout: 10) }.value
        validUntil = r.status == 0 ? TeleportTsh.parseSessionExpiry(json: Data(r.stdout.utf8)) : nil
    }

    /// 저장된 비밀번호/OTP 키로 로그인. 이미 유효하면 아무것도 안 한다.
    @discardableResult
    func ensureLoggedIn(force: Bool = false) async -> Bool {
        if let t = loginTask { return await t.value }
        let t = Task { await self.performLogin(force: force) }
        loginTask = t
        let ok = await t.value
        loginTask = nil
        return ok
    }

    private func performLogin(force: Bool) async -> Bool {
        guard let tsh = tshPath else { message = "tsh 가 설치되어 있지 않아요"; return false }
        if !force {
            await refreshStatus()
            if loggedIn { return true }
        }
        guard let sec = TeleportSecrets.load(), let totp = TOTP(input: sec.otpSecret), !config.user.isEmpty else {
            message = "Teleport 설정이 필요해요"; return false
        }
        busy = "로그인 중…"; message = nil
        defer { busy = nil }
        let login = TeleportLogin(tsh: tsh, proxy: config.proxy, user: config.user)
        let res = await Task.detached { login.run(password: sec.password, otp: { totp.code() }) }.value
        switch res {
        case .success:
            touched = true
            lastLogin = Date()
            UserDefaults.standard.set(lastLogin, forKey: Self.lastLoginKey)
            await refreshStatus()
            return loggedIn
        case .failure(let e):
            message = e.message
            return false
        }
    }

    // MARK: - 터널

    /// 사용자가 켠 터널. 이후 watchdog 이 살아 있게 유지한다.
    func connect(_ t: TeleportTunnel) async {
        wanted.insert(t.name); failures[t.name] = 0
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
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.exited(name, proc) }
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
        guard await ensureLoggedIn() else { return }
        await withTaskGroup(of: Void.self) { g in
            for t in config.tunnels where state(t) != .connected { g.addTask { @MainActor in await self.connect(t) } }
        }
    }

    /// ATM 시작 시: 지난번에 켜 둔 터널을 다시 연결한다 (로그인이 필요하면 자동 로그인).
    func restoreWanted(tabEnabled: Bool) async {
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

    /// 1분마다: 켜 둔 터널이 실제로 응답하는지 보고, 아니면 (필요하면 재로그인 후) 다시 연결한다.
    private func watchdog() async {
        guard isConfigured, tshPath != nil, !wanted.isEmpty, !watchdogBusy, loginTask == nil else { return }
        watchdogBusy = true; defer { watchdogBusy = false }
        // 사용자가 연결 중인 터널은 건드리지 않는다.
        let names = config.tunnels.map(\.name).filter { wanted.contains($0) && states[$0] != .connecting }
        func plan() -> TeleportWatchdogPolicy {
            .decide(wanted: names,
                    running: Set(names.filter { procs[$0]?.isRunning == true }),
                    listening: Set(config.tunnels.filter { names.contains($0.name) && TeleportTsh.isListening(port: $0.port) }.map(\.name)),
                    failures: failures, loggedIn: loggedIn)
        }
        let p = plan()
        if p.relogin, !(await ensureLoggedIn(force: true)) {
            for n in names { fail(n) }
            return
        }
        // 재로그인했으면 plan 이 이미 모든 켜 둔 터널을 재시작 대상으로 잡았다.
        p.giveUp.forEach { giveUp($0) }
        for n in p.restart {
            guard wanted.contains(n), let t = config.tunnels.first(where: { $0.name == n }) else { continue }
            if procs[n] != nil {
                stop(n)
                for _ in 0..<20 where procs[n] != nil { try? await Task.sleep(nanoseconds: 100_000_000) }
            }
            await open(t)
            if states[n] == .connected { failures[n] = 0 } else { fail(n) }
        }
    }

    private func fail(_ n: String) {
        failures[n, default: 0] += 1
        if failures[n]! >= TeleportWatchdogPolicy.maxFailures { giveUp(n) }
    }

    private func giveUp(_ n: String) {
        wanted.remove(n)
        stop(n)
        states[n] = .failed("자동 재연결 \(TeleportWatchdogPolicy.maxFailures)회 실패 · 토글로 다시 시도")
    }

    /// 터널 종료 + `tsh db logout` 각각 + `tsh logout` (Python 도구와 같은 순서).
    func disconnectAll() async {
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
