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

    public init(executable: String, arguments: [String], timeout: TimeInterval = 60) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
    }

    public init(tsh: String, proxy: String, user: String, timeout: TimeInterval = 60) {
        self.init(executable: tsh, arguments: ["login", "--proxy", proxy, "--user", user], timeout: timeout)
    }

    private static let prompts = ["Press [ENTER] to continue", "Enter password", "Enter your OTP token"]

    /// `otp` 는 OTP 프롬프트가 나온 시점에 불린다(30초 경계에 걸리지 않게).
    public func run(password: String, otp: () -> String) -> Result<Void, TeleportError> {
        var master: Int32 = -1, slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { return .failure(TeleportError("PTY 를 만들지 못했어요")) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm"
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
            if Date() > deadline { failure = "시간 초과 (\(Int(timeout))초)"; break }
            var pfd = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            let r = poll(&pfd, 1, 200)
            if r < 0 { if errno == EINTR { continue }; break }
            if r == 0 { if !p.isRunning { break }; continue }
            let n = read(master, &bytes, bytes.count)
            if n <= 0 { break }
            let s = String(decoding: bytes[0..<n], as: UTF8.self)
            buf += s; all += s
            for (i, prompt) in Self.prompts.enumerated() where buf.contains(prompt) {
                sent[i] += 1
                if sent[i] > 1 { failure = "같은 프롬프트가 다시 나왔어요 (비밀번호/OTP 거절?)"; break loop }
                let answer: String
                switch i {
                case 0: answer = ""
                case 1: answer = password
                default: answer = otp(); secrets.append(answer)
                }
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
