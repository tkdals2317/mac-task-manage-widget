import Darwin
import Foundation

public struct TeleportError: Error, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public struct TeleportDB: Equatable {
    public let name: String
    public let isProd: Bool
}

public enum TeleportTsh {
    // MARK: - 위치 찾기

    /// 로그인 셸에서 `command -v tsh` (GUI 앱은 셸 PATH 를 못 받는다).
    public static func loginShellLookup() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let r = ProcessRunner.run(executable: shell, arguments: ["-lc", "command -v tsh"], timeout: 5)
        guard !r.timedOut, r.status == 0 else { return nil }
        return r.stdout.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }

    /// 설정 경로 → 로그인 셸 → /usr/local/bin → /opt/homebrew/bin.
    public static func locate(configured: String, shellLookup: () -> String? = TeleportTsh.loginShellLookup) -> String? {
        if !configured.isEmpty, ClaudeRunner.isExe(configured) { return configured }
        if let p = shellLookup(), p.hasPrefix("/"), ClaudeRunner.isExe(p) { return p }
        return ["/usr/local/bin/tsh", "/opt/homebrew/bin/tsh"].first(where: ClaudeRunner.isExe)
    }

    // MARK: - 파싱

    /// `tsh db ls --format=json`. 이름 없는 항목은 건너뛰고 이름순. 운영 = 이름에 prd/prod 또는 env 라벨.
    public static func parseDBList(json: Data) -> [TeleportDB] {
        guard let arr = (try? JSONSerialization.jsonObject(with: json)) as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        var out: [TeleportDB] = []
        for item in arr {
            guard let meta = item["metadata"] as? [String: Any], let name = meta["name"] as? String,
                  !name.isEmpty, seen.insert(name).inserted else { continue }
            let env = ((meta["labels"] as? [String: Any])?["env"] as? String)?.lowercased() ?? ""
            let lower = name.lowercased()
            let prod = lower.contains("prd") || lower.contains("prod") || ["prd", "prod", "production"].contains(env)
            out.append(TeleportDB(name: name, isProd: prod))
        }
        return out.sorted { $0.name < $1.name }
    }

    /// `tsh status --format=json` → 활성 프로필의 만료 시각. 로그인 안 됨/모르는 형식이면 nil.
    public static func parseSessionExpiry(json: Data) -> Date? {
        guard let o = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let active = o["active"] as? [String: Any], let s = active["valid_until"] as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    public static func remainingText(until: Date, now: Date = Date()) -> String {
        let m = Int(until.timeIntervalSince(now) / 60)
        if m <= 0 { return "만료됨" }
        return m >= 60 ? "\(m / 60)시간 \(m % 60)분 남음" : "\(m)분 남음"
    }

    // MARK: - 포트

    /// 127.0.0.1:port 에 TCP 연결이 되는가 (로컬이라 즉시 성공/거절).
    /// 이전 ATM 실행이 남긴 같은 터널(`tsh proxy db --tunnel <name>`) 이 port 를 잡고 있으면 그 PID 들.
    /// 다른 프로그램이 쓰는 포트는 돌려주지 않는다.
    public static func leftoverTunnelPIDs(port: Int, name: String) -> [Int32] {
        let r = ProcessRunner.run(executable: "/usr/sbin/lsof", arguments: ["-t", "-iTCP:\(port)", "-sTCP:LISTEN"], timeout: 5)
        return r.stdout.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }.filter { pid in
            let ps = ProcessRunner.run(executable: "/bin/ps", arguments: ["-o", "command=", "-p", String(pid)], timeout: 5)
            return isTunnelCommand(ps.stdout, name: name)
        }
    }

    static func isTunnelCommand(_ cmd: String, name: String) -> Bool {
        let parts = cmd.split(separator: " ").map(String.init)
        guard let exe = parts.first, exe.hasSuffix("tsh"), parts.contains("proxy"), parts.contains("db"),
              let i = parts.firstIndex(of: "--tunnel"), i + 1 < parts.count else { return false }
        return parts[i + 1] == name
    }

    public static func isListening(port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(truncatingIfNeeded: port)).bigEndian
        addr.sin_addr = in_addr(s_addr: UInt32(0x7f000001).bigEndian)
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
    }
}

/// `tsh login` 을 PTY 안에서 돌리고 프롬프트에 답한다 (Python pexpect 와 같은 순서).
/// 이미 로그인돼 있으면 프롬프트 없이 EOF → 성공.
public struct TeleportLogin {
    public var executable: String
    public var arguments: [String]
    public var timeout: TimeInterval
    /// 추가 환경 변수 (예: TELEPORT_HOME — 현재 세션을 건드리지 않고 비밀번호/OTP 만 검증할 때).
    public var extraEnvironment: [String: String] = [:]

    public init(executable: String, arguments: [String], timeout: TimeInterval = 60) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
    }

    public init(tsh: String, proxy: String, user: String, timeout: TimeInterval = 60) {
        self.init(executable: tsh, arguments: ["login", "--proxy", proxy, "--user", user], timeout: timeout)
    }

    static let sendDelayMicros: useconds_t = 300_000

    /// 출력에 섞인 터미널 질의에 대한 답. OSC 10/11(전경/배경색), DSR(커서 위치), DA(장치 속성).
    static func terminalReplies(to output: String) -> [String] {
        var r: [String] = []
        if output.contains("\u{1B}]10;?") { r.append("\u{1B}]10;rgb:0000/0000/0000\u{1B}\\") }
        if output.contains("\u{1B}]11;?") { r.append("\u{1B}]11;rgb:ffff/ffff/ffff\u{1B}\\") }
        if output.contains("\u{1B}[6n") { r.append("\u{1B}[1;1R") }
        if output.contains("\u{1B}[c") || output.contains("\u{1B}[0c") { r.append("\u{1B}[?1;2c") }
        return r
    }

    /// 프롬프트별 문구 후보. 보안키·Touch ID 도 등록된 계정은 OTP 를 다른 문구로 묻는다.
    private static let prompts: [[String]] = [
        ["Press [ENTER] to continue"],
        ["Enter password"],
        ["Enter your OTP token", "enter a code from a OTP device", "Enter an OTP code"],
    ]

    /// `otp` 는 OTP 프롬프트가 나온 시점에 불린다(30초 경계에 걸리지 않게).
    public func run(password: String, otp: () -> String) -> Result<Void, TeleportError> {
        var master: Int32 = -1, slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { return .failure(TeleportError("PTY 를 만들지 못했어요")) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm"
        env.merge(extraEnvironment) { $1 }
        p.environment = env
        let h = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        p.standardInput = h; p.standardOutput = h; p.standardError = h
        do { try p.run() } catch {
            close(master); close(slave)
            return .failure(TeleportError("tsh 실행 실패: \(error.localizedDescription)"))
        }
        close(slave)   // 부모 쪽 slave 를 닫아야 자식 종료 시 master 에 EOF 가 온다

        var secrets = [password]
        var buf = "", all = ""
        var sent = [Int](repeating: 0, count: Self.prompts.count)
        var failure: String?
        let deadline = Date().addingTimeInterval(timeout)
        var bytes = [UInt8](repeating: 0, count: 4096)
        loop: while true {
            if Date() > deadline {
                // 기다리던 프롬프트가 아닌 문구에서 멈췄을 수 있다. 마지막 출력을 보여준다(비밀값은 가림).
                let last = Self.tail(all, redacting: secrets, status: -1).components(separatedBy: ": ").dropFirst().joined(separator: ": ")
                failure = "시간 초과 (\(Int(timeout))초)" + (last.isEmpty ? "" : " · 마지막 출력: \(last)")
                break
            }
            var pfd = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            let r = poll(&pfd, 1, 200)
            if r < 0 { if errno == EINTR { continue }; break }
            if r == 0 { if !p.isRunning { break }; continue }
            let n = read(master, &bytes, bytes.count)
            if n <= 0 { break }
            let s = String(decoding: bytes[0..<n], as: UTF8.self)
            buf += s; all += s
            // 최신 tsh 는 터미널에 배경색(OSC 11)·커서 위치(DSR) 를 묻고 답을 기다린다. 실제 터미널처럼 답해 준다.
            // 답하지 않으면 tsh 가 멈추거나, 뒤에 보내는 Enter/비밀번호를 그 답으로 읽어 버린다.
            for reply in Self.terminalReplies(to: s) {
                _ = Array(reply.utf8).withUnsafeBufferPointer { write(master, $0.baseAddress, $0.count) }
            }
            for (i, alts) in Self.prompts.enumerated() where alts.contains(where: { buf.localizedCaseInsensitiveContains($0) }) {
                sent[i] += 1
                if sent[i] > 1 { failure = "같은 프롬프트가 다시 나왔어요 (비밀번호/OTP 거절?)"; break loop }
                let answer: String
                switch i {
                case 0: answer = ""
                case 1: answer = password
                default: answer = otp(); secrets.append(answer)
                }
                // tsh 는 프롬프트를 찍은 뒤에 입력 모드(에코 끄기)를 바꾼다. 그 전에 보내면 앞 글자가 버려질 수 있어
                // 잠깐 기다렸다 보낸다 (pexpect 의 delaybeforesend 와 같은 이유).
                usleep(Self.sendDelayMicros)
                _ = Array((answer + "\n").utf8).withUnsafeBufferPointer { write(master, $0.baseAddress, $0.count) }
                buf = ""
                break
            }
        }
        if failure != nil, p.isRunning { p.terminate() }
        p.waitUntilExit()
        close(master)
        if failure == nil, p.terminationStatus == 0 { return .success(()) }
        return .failure(TeleportError(failure ?? Self.tail(all, redacting: secrets, status: p.terminationStatus)))
    }

    /// 마지막 비어있지 않은 3줄. ANSI 이스케이프 제거, 비밀 값은 *** 로.
    static func tail(_ output: String, redacting secrets: [String], status: Int32) -> String {
        var t = output.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        for s in secrets where !s.isEmpty { t = t.replacingOccurrences(of: s, with: "***") }
        let lines = t.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // 로그인 공지 배너가 길어서, ERROR 줄이 있으면 그 줄만 보여준다.
        let errLine = t.range(of: "ERROR:[^\\r\\n]*", options: [.regularExpression, .backwards]).map { String(t[$0]).trimmingCharacters(in: .whitespaces) }
        let shown = errLine.map { [$0] } ?? Array(lines.suffix(3))
        return "tsh 로그인 실패 (exit \(status))" + (shown.isEmpty ? "" : ": " + shown.joined(separator: " / "))
    }
}
