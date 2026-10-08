import Foundation

/// 로그 파일 덧붙이기 (크기 상한 포함). 비밀 값은 절대 넘기지 않는다.
public enum DiagLog {
    public static let maxBytes = 512 * 1024
    public static let keepBytes = 256 * 1024
    private static let lock = NSLock()

    /// ISO 8601, 로컬 시간대 (예: 2026-10-08T14:03:09+09:00).
    public static func timestamp(_ d: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        return f.string(from: d)
    }

    /// `<시각> <줄>` 한 줄을 logs/<file> 에 덧붙인다.
    public static func append(_ line: String, file: String = "app.log", dir: URL = Paths.logsDir, now: Date = Date()) {
        appendRaw("\(timestamp(now)) \(line)\n", file: file, dir: dir)
    }

    public static func appendRaw(_ text: String, file: String, dir: URL = Paths.logsDir) {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(file)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data((text.hasSuffix("\n") ? text : text + "\n").utf8))
        let size = (try? h.offset()) ?? 0
        try? h.close()
        if Int(size) > maxBytes, let d = try? Data(contentsOf: url) {
            try? trimmed(d).write(to: url, options: .atomic)
        }
    }

    /// max 를 넘으면 마지막 keep 바이트만 남긴다 (잘린 첫 줄은 버린다).
    public static func trimmed(_ data: Data, max: Int = maxBytes, keep: Int = keepBytes) -> Data {
        guard data.count > max else { return data }
        let tail = Data(data.suffix(keep))
        guard let nl = tail.firstIndex(of: 0x0A) else { return tail }
        return Data(tail[(nl + 1)...])
    }
}

public struct LoginReport {
    public var transcript: String
    public var exitStatus: Int32
    public var durationMs: Int
    public var timedOut: Bool
}

/// PTY 대화 기록. 읽은 것(`<`)과 보낸 것(`>`)을 시각과 함께 남기되 비밀 값은 가린다.
public enum DiagTranscript {
    public struct Event: Equatable {
        public var ms: Int
        public var outbound: Bool
        public var text: String
        public init(ms: Int, outbound: Bool, text: String) { self.ms = ms; self.outbound = outbound; self.text = text }
    }

    /// 제어 문자를 눈에 보이게. 줄바꿈(\n)만 그대로 둔다.
    public static func visible(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            switch u.value {
            case 0x0A: out.unicodeScalars.append(u)
            case 0x1B: out += "\\e"
            case 0x0D: out += "\\r"
            case 0..<0x20, 0x7F: out += String(format: "\\x%02X", u.value)
            default: out.unicodeScalars.append(u)
            }
        }
        return out
    }

    /// 방향별로 이어 붙인 뒤 비밀 값을 찾아 `***` 로 바꾼다 (청크 경계에 걸려도 가려짐).
    public static func redact(_ events: [Event], secrets: [String]) -> [Event] {
        let pats = secrets.filter { !$0.isEmpty }.map { Array($0.unicodeScalars) }
        var out = events
        for dir in [false, true] {
            let idx = events.indices.filter { events[$0].outbound == dir }
            var all: [Unicode.Scalar] = [], owner: [Int] = []
            for i in idx { for u in events[i].text.unicodeScalars { all.append(u); owner.append(i) } }
            var mask = [Bool](repeating: false, count: all.count)
            for p in pats where all.count >= p.count {
                for j in 0...(all.count - p.count) where all[j..<(j + p.count)].elementsEqual(p) {
                    for k in j..<(j + p.count) { mask[k] = true }
                }
            }
            var texts: [Int: String] = [:]
            for k in all.indices {
                if mask[k] { if k == 0 || !mask[k - 1] { texts[owner[k], default: ""] += "***" } }
                else { texts[owner[k], default: ""].unicodeScalars.append(all[k]) }
            }
            for i in idx { out[i].text = texts[i] ?? "" }
        }
        return out
    }

    /// `[ 1234ms] < 텍스트` — 줄마다 접두어를 붙인다.
    public static func render(_ events: [Event], secrets: [String]) -> String {
        var lines: [String] = []
        for e in redact(events, secrets: secrets) {
            var parts = visible(e.text).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if parts.count > 1, parts.last == "" { parts.removeLast() }
            for p in parts {
                lines.append(String(format: "[%6dms] ", e.ms) + (e.outbound ? "> " : "< ") + p)
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// teleport-login.log 한 블록.
public enum TeleportLoginLog {
    public static func block(kind: String, user: String, proxy: String, tsh: String, version: String,
                             report: LoginReport, result: Result<Void, TeleportError>, now: Date = Date()) -> String {
        let res: String
        switch result {
        case .success: res = "ok"
        case .failure(let e): res = "fail \(e.message)"
        }
        return "=== \(DiagLog.timestamp(now)) login (\(kind)) user=\(user) proxy=\(proxy) tsh=\(tsh) (\(version)) ===\n"
            + (report.transcript.isEmpty ? "" : report.transcript + "\n")
            + "--- result: \(res) exit=\(report.exitStatus) \(report.durationMs)ms\(report.timedOut ? " timeout" : "")\n"
    }

    public static func append(kind: String, user: String, proxy: String, tsh: String,
                              report: LoginReport, result: Result<Void, TeleportError>) {
        DiagLog.appendRaw(block(kind: kind, user: user, proxy: proxy, tsh: tsh, version: TeleportTsh.versionLine(tsh),
                                report: report, result: result), file: "teleport-login.log")
    }
}

public enum DiagnosticsExport {
    public static let defaultsDomain = "com.lsm0506.TaskWidget"
    static let sensitiveWords = ["token", "secret", "password", "otp"]

    /// `a@company.com` → `***@company.com`.
    public static func maskEmail(_ e: String) -> String {
        guard let at = e.lastIndex(of: "@") else { return e.isEmpty ? "(없음)" : "***" }
        return "***" + e[at...]
    }

    /// `defaults read` 출력에서 이름에 token/secret/password/otp 가 든 키(여러 줄 값 포함)를 지우고, 이메일은 가린다.
    public static func redactDefaults(_ text: String) -> String {
        let entry = try! NSRegularExpression(pattern: #"^(\s*)"?([^"=\s]+)"?\s*=\s*(.*)$"#)
        var out: [String] = []
        var skipUntil: String?   // 여러 줄 값의 닫는 줄
        for line in text.components(separatedBy: "\n") {
            if let end = skipUntil {
                if line.trimmingCharacters(in: .whitespaces) == end { skipUntil = nil }
                continue
            }
            let ns = line as NSString
            if let m = entry.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let key = ns.substring(with: m.range(at: 2)).lowercased()
                if sensitiveWords.contains(where: key.contains) {
                    let v = ns.substring(with: m.range(at: 3))
                    if v.hasPrefix("(") { skipUntil = ");" } else if v.hasPrefix("{") { skipUntil = "};" }
                    continue
                }
            }
            out.append(line.replacingOccurrences(of: #"[A-Za-z0-9._%+\-]+@"#, with: "***@", options: .regularExpression))
        }
        return out.joined(separator: "\n")
    }

    public struct InfoInput {
        public var build: BuildInfo
        public var settings: Settings
        public var teleport: TeleportConfig
        public var tshPath: String?
        public var claudePath: String?
        public var hasJiraToken: Bool
        public var hasTeleportSecrets: Bool
        public init(build: BuildInfo, settings: Settings, teleport: TeleportConfig, tshPath: String?, claudePath: String?,
                    hasJiraToken: Bool, hasTeleportSecrets: Bool) {
            self.build = build; self.settings = settings; self.teleport = teleport; self.tshPath = tshPath
            self.claudePath = claudePath; self.hasJiraToken = hasJiraToken; self.hasTeleportSecrets = hasTeleportSecrets
        }
    }

    /// 첫 줄만. 실패하면 "(확인 실패)".
    public static func commandLine(_ exe: String, _ args: [String], timeout: TimeInterval = 5) -> String {
        let r = ProcessRunner.run(executable: exe, arguments: args, timeout: timeout)
        let first = (r.stdout.isEmpty ? r.stderr : r.stdout).split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return r.timedOut || (r.status != 0 && first.isEmpty) || first.isEmpty ? "(확인 실패)" : first.trimmingCharacters(in: .whitespaces)
    }

    public static func infoText(_ i: InfoInput, now: Date = Date(),
                                run: (String, [String]) -> String = { commandLine($0, $1) }) -> String {
        let b = i.build, s = i.settings, t = i.teleport
        func yn(_ v: Bool) -> String { v ? "yes" : "no" }
        var l: [String] = []
        l.append("생성: \(DiagLog.timestamp(now))")
        l.append("ATM: \(b.version) (빌드 \(b.buildNumber), 커밋 \(b.commit), dirty=\(b.dirty), 빌드 날짜 \(b.buildDate))")
        l.append("sourceDir: \(b.sourceDir.isEmpty ? "(없음)" : b.sourceDir)")
        l.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        l.append("hardware: \(run("/usr/sbin/sysctl", ["-n", "hw.model"])) / arch \(run("/usr/bin/uname", ["-m"]))")
        if let p = i.tshPath { l.append("tsh: \(p) (\(run(p, ["version"])))") } else { l.append("tsh: (없음)") }
        if let p = i.claudePath { l.append("claude: \(p) (\(run(p, ["--version"])))") } else { l.append("claude: (없음)") }
        l.append("secretStorage: \(s.secretStorage)")
        l.append("enabledTabs: \(s.enabledTabs)")
        l.append("teleport: proxy=\(t.proxy) user=\(t.user)")
        for x in t.tunnels { l.append("  tunnel \(x.name) port=\(x.port) dbUser=\(x.dbUser)") }
        l.append("jira: \(s.jiraBaseURL.isEmpty ? "(주소 없음)" : s.jiraBaseURL) email=\(maskEmail(s.jiraEmail))")
        l.append("jira token 있음: \(yn(i.hasJiraToken))")
        l.append("teleport 비밀 정보 있음: \(yn(i.hasTeleportSecrets))")
        return l.joined(separator: "\n") + "\n"
    }

    /// 내보낼 폴더를 채운다. 반환: 상대 경로 목록. secrets.json·todos·worklog·summaries·activity 는 어떤 경우에도 담지 않는다.
    @discardableResult
    public static func stage(into root: URL, dataDir: URL, logsDir: URL, info: String, defaults: String) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("logs"), withIntermediateDirectories: true)
        var files: [String] = []
        for n in ((try? fm.contentsOfDirectory(atPath: logsDir.path)) ?? []).sorted() where n != "secrets.json" {
            var isDir: ObjCBool = false
            let src = logsDir.appendingPathComponent(n)
            guard fm.fileExists(atPath: src.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            try fm.copyItem(at: src, to: root.appendingPathComponent("logs/\(n)"))
            files.append("logs/\(n)")
        }
        try info.write(to: root.appendingPathComponent("info.txt"), atomically: true, encoding: .utf8)
        try redactDefaults(defaults).write(to: root.appendingPathComponent("defaults.txt"), atomically: true, encoding: .utf8)
        files += ["info.txt", "defaults.txt"]
        let tele = dataDir.appendingPathComponent("teleport.json")
        if fm.fileExists(atPath: tele.path) {
            try fm.copyItem(at: tele, to: root.appendingPathComponent("teleport.json"))
            files.append("teleport.json")
        }
        return files
    }

    /// `<destDir>/ATM-diagnostics-<yyyyMMdd-HHmm>.zip` 을 만든다 (ditto, 임시 폴더 사용).
    public static func export(to destDir: URL, dataDir: URL = Paths.dataDir, logsDir: URL = Paths.logsDir,
                              info: String, defaults: String, now: Date = Date()) throws -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmm"; f.locale = Locale(identifier: "en_US_POSIX")
        let name = "ATM-diagnostics-\(f.string(from: now))"   // 압축 해제 도구마다 한글 이름이 깨져 영문으로
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("atm-diag-\(UUID().uuidString)")
        let root = tmp.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try stage(into: root, dataDir: dataDir, logsDir: logsDir, info: info, defaults: defaults)
        let zip = destDir.appendingPathComponent("\(name).zip")
        try? FileManager.default.removeItem(at: zip)
        let r = ProcessRunner.run(executable: "/usr/bin/ditto", arguments: ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", root.path, zip.path], timeout: 60)
        guard r.status == 0 else { throw TeleportError("zip 만들기 실패: \(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))") }
        return zip
    }
}
