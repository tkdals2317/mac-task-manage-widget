import Darwin
import Foundation

/// Aside 계정에 로그인돼 있지 않은 이유.
public enum AsideSignOutReason: Equatable {
    /// Aside 계정으로 로그인한 적이 없다
    case never
    /// 로그인이 풀렸다
    case noSession
    /// 로그인이 멈췄다. Aside 가 적은 이유 (token_revoked·device_mismatch 등, 모르면 "")
    case paused(String)
}

/// `aside account status` 가 알려 주는 계정 상태. Aside 브라우저와 CLI 가 같은 계정을 쓰고,
/// 로그인은 Aside 브라우저의 설정 > 계정에서 한다 (`aside login` 은 원격 호스트용이라 이 Mac 에서 돌릴 땐 필요 없다).
public enum AsideAccountStatus: Equatable {
    /// email 이 없으면 이름. plan 은 free·pro 등 (모르면 "").
    case signedIn(email: String, accountId: Int, plan: String)
    /// who 는 이메일·이름 (모르면 "").
    case signedOut(who: String, reason: AsideSignOutReason)
    /// 확인 실패 (명령 오류·시간 초과·모르는 출력). 사용자에게 보여줄 한 줄.
    case unknown(String)
}

/// `aside account list` 의 계정 하나.
public struct AsideAccount: Equatable, Identifiable {
    public let id: Int
    /// 이메일, 없으면 이름
    public let title: String
    public let signedIn: Bool

    public init(id: Int, title: String, signedIn: Bool) {
        self.id = id
        self.title = title
        self.signedIn = signedIn
    }
}

/// Aside 준비 상태를 한 번 살펴본 결과. 모델을 쓰지 않고 CLI 명령과 파일만으로 아는 것.
public struct AsideProbe: Equatable {
    public var path: String
    public var source: String
    /// 모르면 ""
    public var version: String
    /// Aside 가 마지막으로 확인해 둔 최신 CLI 버전 (모르면 "")
    public var latestVersion: String
    /// `aside exec` 가 guard 권한 옵션을 아는지. 모르는 구버전이면 검증을 돌릴 수 없다.
    public var runnable: Bool
    public var account: AsideAccountStatus
    /// 지금 계정 말고 Aside 에 있는 다른 계정
    public var otherAccounts: [AsideAccount]
    /// Aside 브라우저 창(프로필)이 열려 있는지. 확인하지 못했으면 nil.
    public var windowOpen: Bool?

    public init(path: String, source: String = "", version: String = "", latestVersion: String = "", runnable: Bool = true,
                account: AsideAccountStatus, otherAccounts: [AsideAccount] = [], windowOpen: Bool? = nil) {
        self.path = path
        self.source = source
        self.version = version
        self.latestVersion = latestVersion
        self.runnable = runnable
        self.account = account
        self.otherAccounts = otherAccounts
        self.windowOpen = windowOpen
    }

    public var updateAvailable: Bool { AsideCLI.isNewer(latestVersion, than: version) }
}

/// Aside CLI 를 찾고 부르는 방법. 스파이크(Aside CLI 1.26)에서 확인한 동작 기준:
/// - guard 권한에서는 CLI 작업 폴더와 상관없이 에이전트가 계정 폴더(`~/.aside/u/<id>/`) 안에서만 승인 없이 읽고 쓴다.
///   그래서 full-access 대신 guard 로 돌리고, 요청·결과는 그 아래 실행용 폴더(`workDir`)를 거친다.
/// - 실행 결과와 상관없이 exit 0 일 수 있어 성공 판단은 result.json 으로만 한다.
/// - CLI 에 SIGTERM 을 보내면 세션도 aborted 로 멈춘다. `--timeout` 은 CLI 만 멈추고 세션은 계속 돌아서 쓰지 않는다.
public enum AsideCLI {
    public static let installCommand = "curl -fsSL https://releases.aside.com/install.sh | bash"
    /// Aside 브라우저 앱. 로그인 페이지를 사용자에게 열어 줄 때 쓴다.
    public static let browserBundleId = "at.studio.AsideBrowser"

    static func knownPaths(home: String) -> [String] {
        ["\(home)/.local/bin/aside", "\(home)/.aside/cli/Aside CLI.app/Contents/MacOS/aside",
         "/opt/homebrew/bin/aside", "/usr/local/bin/aside"]
    }

    /// 설정 경로 → 로그인 셸 → 기본 위치 순. 실행 가능한 첫 번째.
    public static func locateWithSource(configured: String,
                                        home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                        shellLookup: () -> String? = { ClaudeRunner.loginShellLookup(command: "aside") })
        -> (path: String, source: String)? {
        let c = configured.trimmingCharacters(in: .whitespaces)
        if !c.isEmpty, ClaudeRunner.isExe(c) { return (c, "설정 경로") }
        if let p = shellLookup(), p.hasPrefix("/"), ClaudeRunner.isExe(p) { return (p, "로그인 셸") }
        if let p = knownPaths(home: home.path).first(where: ClaudeRunner.isExe) { return (p, "기본 위치") }
        return nil
    }

    public static let browserDownloadURL = "https://aside.com/download"

    /// CLI 를 설치하고 계정 상태를 보여 주는 스크립트 (.command 로 연다). 설치한 셸에는 아직 PATH 가 없어 설치 위치를 먼저 본다.
    public static func installScript(installCommand: String = installCommand) -> String {
        """
        #!/bin/zsh
        clear
        echo "ATM · Aside CLI 설치"
        echo
        \(installCommand) || { echo; echo "설치에 실패했어요. 위 메시지를 확인해 주세요."; exit 1; }
        A="$HOME/.local/bin/aside"
        [ -x "$A" ] || A="$(command -v aside)"
        [ -n "$A" ] || { echo; echo "설치한 aside 를 찾지 못했어요. ATM 설정 > E2E 에 aside 경로를 넣어 주세요."; exit 1; }
        echo
        echo "설치했어요. 지금 Aside 계정 상태:"
        "$A" account status
        echo
        echo "signed in 이 아니면 Aside 브라우저의 설정 > 계정에서 Aside 계정으로 로그인해 주세요."
        echo "ATM 이 알아서 다시 확인해요. 이 창은 닫아도 돼요."
        """
    }

    /// CLI 를 최신으로 올리는 스크립트. `aside update` 가 없거나 실패하면 설치 명령으로 다시 설치한다.
    public static func updateScript(executable: String, installCommand: String = installCommand) -> String {
        let exe = Updater.shellQuote(executable)
        return """
        #!/bin/zsh
        clear
        echo "ATM · Aside CLI 업데이트"
        echo
        \(exe) update || {
          echo
          echo "aside update 가 되지 않아 설치 명령으로 다시 설치해요."
          \(installCommand) || { echo; echo "업데이트에 실패했어요. 위 메시지를 확인해 주세요."; exit 1; }
        }
        echo
        echo "지금 버전: $(\(exe) --version 2>/dev/null)"
        echo "Aside 브라우저도 최신 버전인지 확인해 주세요. ATM 이 알아서 다시 확인해요. 이 창은 닫아도 돼요."
        """
    }

    /// `aside exec` 인자. 셸을 거치지 않고 배열로 넘긴다. model 이 비면 Aside 설정의 기본 모델.
    /// 사용자의 Aside 기본 권한이 full-access 여도 guard 로 돌도록 권한을 늘 적는다.
    public static func execArguments(prompt: String, model: String = "") -> [String] {
        let m = model.trimmingCharacters(in: .whitespaces)
        return ["exec", "--permission", "guard"] + (m.isEmpty ? [] : ["--model", m]) + [prompt]
    }

    /// job 하나의 실행용 폴더. guard 에서 Aside 가 읽고 쓸 수 있는 계정 폴더 아래에 둔다.
    public static func workDir(accountId: Int, jobId: String,
                               home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".aside/u/\(accountId)/atm-e2e/\(jobId)", isDirectory: true)
    }

    /// 계정마다 있는 실행용 폴더의 상위 (`~/.aside/u/*/atm-e2e`). 있는 것만.
    public static func workRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let fm = FileManager.default
        let u = home.appendingPathComponent(".aside/u", isDirectory: true)
        return ((try? fm.contentsOfDirectory(atPath: u.path)) ?? []).sorted()
            .map { u.appendingPathComponent($0).appendingPathComponent("atm-e2e", isDirectory: true) }
            .filter { fm.fileExists(atPath: $0.path) }
    }

    /// Aside 앱이 받아 둔 모델 목록 캐시. 공식 CLI 명령이 없어 내부 파일을 읽는다 (모양이 바뀌면 빈 목록).
    public static func modelsFile(accountId: Int, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".aside/u/\(accountId)/cache/models.json")
    }

    public static func parseModels(_ data: Data) -> [AsideModel] {
        struct Entry: Decodable { let value: Catalog? }
        struct Catalog: Decodable { let models: [Model]? }
        struct Model: Decodable { let id: String; let name: String?; let minPlan: String? }
        guard let all = try? JSONDecoder().decode([String: Entry].self, from: data),
              let models = all["[\"models\",\"aside-catalog\"]"]?.value?.models else { return [] }
        return models.filter { !$0.id.isEmpty }.map { AsideModel(id: $0.id, name: $0.name ?? $0.id, minPlan: $0.minPlan ?? "") }
    }

    public static func models(accountId: Int, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AsideModel] {
        let cache = (try? Data(contentsOf: modelsFile(accountId: accountId, home: home)))
        let connected = (try? Data(contentsOf: home.appendingPathComponent(".aside/u/\(accountId)/models.json")))
            .map { parseConnectedModels($0, names: cache.map(modelNames) ?? [:]) } ?? []
        return (cache.map(parseModels) ?? []) + connected
    }

    /// 캐시의 모든 카탈로그에서 id → 이름.
    static func modelNames(_ data: Data) -> [String: String] {
        struct Entry: Decodable { let value: Catalog? }
        struct Catalog: Decodable { let models: [Model]? }
        struct Model: Decodable { let id: String; let name: String? }
        let all = (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
        var out: [String: String] = [:]
        for e in all.values { for m in e.value?.models ?? [] where out[m.id] == nil { out[m.id] = m.name } }
        return out
    }

    /// 사용자가 Aside 에 연동한 provider(claude-code 등)의 모델. --model 에 넣을 id 는 "provider/모델".
    public static func parseConnectedModels(_ data: Data, names: [String: String] = [:]) -> [AsideModel] {
        struct Catalog: Decodable {
            struct Scope: Decodable { let modelIds: [String]? }
            let modelIds: [String]?
            let scopes: [String: Scope]?
        }
        struct Provider: Decodable { let accountModelCatalog: Catalog? }
        struct File: Decodable { let providers: [String: Provider]? }
        guard let f = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        var out: [AsideModel] = []
        for (provider, p) in (f.providers ?? [:]).sorted(by: { $0.key < $1.key }) {
            let c = p.accountModelCatalog
            var ids = c?.modelIds ?? []
            for s in (c?.scopes ?? [:]).values { ids += s.modelIds ?? [] }
            var seen = Set<String>()
            for id in ids where !id.isEmpty && seen.insert(id).inserted {
                out.append(AsideModel(id: "\(provider)/\(id)", name: "\(names[id] ?? id) · \(provider)", minPlan: "", provider: provider))
            }
        }
        return out
    }

    /// GUI 앱은 셸 환경을 못 받으므로 PATH 를 채우고, 묻는 창·색·업데이트 알림을 끈다.
    public static func environment(executable: String, base: [String: String] = ProcessInfo.processInfo.environment,
                                   home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> [String: String] {
        var env = base
        let binDir = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        env["PATH"] = "\(binDir):\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + (base["PATH"] ?? "/usr/bin:/bin")
        env["CI"] = "1"
        env["NO_COLOR"] = "1"
        env["NO_UPDATE_NOTIFIER"] = "1"
        return env
    }

    /// stderr 의 `created new session: <id>` 에서 세션 id.
    public static func sessionId(in line: String) -> String? {
        guard let r = line.range(of: "created new session:") else { return nil }
        let id = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return id.isEmpty || id.contains(" ") ? nil : id
    }

    /// Aside 가 JSON 으로 주는 계정 하나. 로그인 판단은 Aside CLI 의 기준을 따른다
    /// (cloud 계정이고 세션이 있으며 멈추지 않았을 때만 로그인).
    private struct AccountJSON: Decodable {
        let id: Int?; let email: String?; let name: String?; let provider: String?; let mode: String?
        let authStatus: String?; let authPausedReason: String?; let hasSession: Bool?; let subscriptionPlan: String?

        var title: String { email ?? name ?? "" }

        var status: AsideAccountStatus {
            let auth = authStatus?.lowercased()
            if auth == "active" && hasSession != false && mode?.lowercased() != "local" {
                return .signedIn(email: title, accountId: id ?? 0, plan: subscriptionPlan ?? "")
            }
            if auth == "paused" { return .signedOut(who: title, reason: .paused(authPausedReason ?? "")) }
            let known = !(email ?? "").isEmpty || !["", "anonymous"].contains(provider?.lowercased() ?? "")
            return .signedOut(who: title, reason: known ? .noSession : .never)
        }
    }

    /// `aside account status --json` 결과 해석. 로그인돼 있으면 이메일(없으면 이름).
    public static func parseAccountStatus(stdout: String, exitCode: Int32) -> AsideAccountStatus {
        struct Wrap: Decodable { let account: AccountJSON? }
        let lower = stdout.lowercased()
        guard let data = stdout.data(using: .utf8), let w = try? JSONDecoder().decode(Wrap.self, from: data) else {
            if lower.contains("not signed in") || lower.contains("aside login") { return .signedOut(who: "", reason: .never) }
            let last = stdout.split(separator: "\n").last.map(String.init) ?? ""
            return .unknown(exitCode == 0 ? "알 수 없는 응답: \(last.prefix(120))" : "aside 오류 (exit \(exitCode)) \(last.prefix(120))")
        }
        return w.account?.status ?? .signedOut(who: "", reason: .never)
    }

    /// `aside account list --json` 결과에서 지금 계정 말고 다른 계정. 모르는 모양이면 빈 목록.
    public static func parseOtherAccounts(_ stdout: String) -> [AsideAccount] {
        struct List: Decodable { let currentAccountId: Int?; let accounts: [AccountJSON]? }
        guard let data = stdout.data(using: .utf8), let l = try? JSONDecoder().decode(List.self, from: data) else { return [] }
        return (l.accounts ?? []).compactMap { a in
            guard let id = a.id, id != l.currentAccountId else { return nil }
            var signedIn = false
            if case .signedIn = a.status { signedIn = true }
            return AsideAccount(id: id, title: a.title.isEmpty ? "u\(id)" : a.title, signedIn: signedIn)
        }
    }

    /// `aside host profiles` 결과에서 Aside 브라우저 창(프로필)이 하나라도 연결돼 있는지. 모르는 출력이면 nil.
    /// 앱이 켜져 있어도 창을 모두 닫으면 연결이 끊기고, 그 상태로 실행하면 "not connected to the daemon" 으로 실패한다.
    public static func parseWindowOpen(_ output: String) -> Bool? {
        struct Wrap: Decodable {
            struct Profile: Decodable { let connected: Bool? }
            let profiles: [Profile]?
        }
        if let data = output.data(using: .utf8), let w = try? JSONDecoder().decode(Wrap.self, from: data), let p = w.profiles {
            return p.contains { $0.connected == true }
        }
        let states = output.split(whereSeparator: \.isNewline).compactMap { line -> Bool? in
            switch line.split(whereSeparator: \.isWhitespace).last?.lowercased() {
            case "connected": return true
            case "disconnected": return false
            default: return nil
            }
        }
        if !states.isEmpty { return states.contains(true) }
        return output.lowercased().contains("no browser profiles") ? false : nil
    }

    /// 점으로 나눈 숫자 버전 비교 (1.26.1107.24). 둘 중 하나라도 숫자가 아니면 false.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int]? {
            let p = v.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").map { Int($0) }
            return p.isEmpty || p.contains(nil) ? nil : p.compactMap { $0 }
        }
        guard let a = parts(candidate), let b = parts(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Aside CLI 가 마지막으로 확인해 둔 최신 버전 (`~/.aside/cli/update-check.json`). 없으면 "".
    public static func latestVersion(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        struct Check: Decodable { let latestVersion: String? }
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".aside/cli/update-check.json")) else { return "" }
        return (try? JSONDecoder().decode(Check.self, from: data))?.latestVersion ?? ""
    }

    public static let updateHint = "Aside CLI 가 오래됐어요 · '터미널에서 업데이트'로 올린 뒤 다시 실행"

    /// 구버전 CLI 가 모르는 옵션·명령을 받았을 때의 출력인지.
    static func isUnknownOption(_ output: String) -> Bool {
        let t = output.lowercased()
        return t.contains("unknown option") || t.contains("unknown command")
    }

    /// `aside account status` 일반 출력 해석 (`--json` 이 없는 구버전용).
    /// 예: `* u0  me@example.com  signed in  profiles: Profile 0`. `*` 가 지금 계정이고, 없으면 첫 계정.
    public static func parsePlainAccountStatus(_ output: String) -> AsideAccountStatus {
        let rows = output.split(whereSeparator: \.isNewline).map { line -> (current: Bool, tokens: [Substring]) in
            var t = line.split(whereSeparator: \.isWhitespace)
            let current = t.first == "*"
            if current { t.removeFirst() }
            return (current, t)
        }.filter { r in
            guard let first = r.tokens.first, first.hasPrefix("u"), r.tokens.count >= 3 else { return false }
            return Int(first.dropFirst()) != nil
        }
        let lower = output.lowercased()
        guard let row = rows.first(where: { $0.current }) ?? rows.first else {
            if lower.contains("not signed in") || lower.contains("aside login") { return .signedOut(who: "", reason: .never) }
            return .unknown(updateHint)
        }
        let who = String(row.tokens[1])
        let state = row.tokens.dropFirst(2).joined(separator: " ").lowercased()
        if state.contains("paused") { return .signedOut(who: who, reason: .paused("")) }
        if state.contains("not signed in") || state.contains("signed out") { return .signedOut(who: who, reason: .noSession) }
        guard state.hasPrefix("signed in"), let id = Int(row.tokens[0].dropFirst()) else { return .unknown(updateHint) }
        return .signedIn(email: who, accountId: id, plan: "")
    }

    /// aside 를 한 번 부른다. 시간 초과면 nil. stdout 이 비면 stderr.
    private static func run(_ executable: String, _ args: [String], timeout: TimeInterval = 15) -> (text: String, status: Int32)? {
        let r = ProcessRunner.run(executable: executable, arguments: args, environment: environment(executable: executable), timeout: timeout)
        if r.timedOut { return nil }
        let out = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return (out.isEmpty ? r.stderr.trimmingCharacters(in: .whitespacesAndNewlines) : out, r.status)
    }

    public static func accountStatus(executable: String) -> AsideAccountStatus {
        let timeout = AsideAccountStatus.unknown("aside 응답 없음 (15초)")
        guard let r = run(executable, ["account", "status", "--json"]) else { return timeout }
        // 구버전 CLI 는 --json 이 없어 일반 출력으로 다시 본다.
        guard isUnknownOption(r.text) else { return parseAccountStatus(stdout: r.text, exitCode: r.status) }
        guard let plain = run(executable, ["account", "status"]) else { return timeout }
        return parsePlainAccountStatus(plain.text)
    }

    /// Aside 브라우저 창이 열려 있는지 (`aside host profiles`). 확인하지 못하면 nil.
    public static func windowOpen(executable: String) -> Bool? {
        guard let r = run(executable, ["host", "profiles", "--json"]) else { return nil }
        if !isUnknownOption(r.text) { return parseWindowOpen(r.text) }
        return run(executable, ["host", "profiles"]).flatMap { isUnknownOption($0.text) ? nil : parseWindowOpen($0.text) }
    }

    /// 찾은 aside 로 준비 상태를 한 번에 살펴본다 (버전·실행 가능 여부·계정·다른 계정·창).
    public static func probe(executable: String, source: String = "",
                             home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AsideProbe {
        let version = run(executable, ["--version"]).flatMap { $0.status == 0 ? $0.text.split(whereSeparator: \.isNewline).first : nil }
        // 도움말을 못 읽었으면 막지 않는다 (실행해서 실패하면 그때 알려 준다).
        let help = run(executable, ["exec", "--help"])
        let runnable = help.map { $0.status != 0 || $0.text.contains("--permission") } ?? true
        let account = accountStatus(executable: executable)
        var probe = AsideProbe(path: executable, source: source, version: version.map(String.init) ?? "",
                               latestVersion: latestVersion(home: home), runnable: runnable, account: account)
        if case .unknown = account { return probe }
        probe.otherAccounts = run(executable, ["account", "list", "--json"]).map { parseOtherAccounts($0.text) } ?? []
        if case .signedIn = account { probe.windowOpen = windowOpen(executable: executable) }
        return probe
    }

    /// 검증에 쓸 Aside 계정을 바꾼다 (`aside account use u<id>`). 실패하면 보여줄 한 줄.
    public static func useAccount(executable: String, id: Int) -> String? {
        guard let r = run(executable, ["account", "use", "u\(id)"]) else { return "aside 응답 없음 (15초)" }
        return r.status == 0 ? nil : "계정을 바꾸지 못했어요 · \(r.text.split(whereSeparator: \.isNewline).last.map(String.init) ?? "exit \(r.status)")"
    }

    /// SIGKILL 까지 가서 세션이 남았을 수 있을 때 세션을 멈춘다.
    public static func stopSession(executable: String, id: String) {
        _ = ProcessRunner.run(executable: executable, arguments: ["session", "stop", id],
                              environment: environment(executable: executable), timeout: 15)
    }

    /// ATM 이 죽은 뒤 남은 aside 프로세스를 멈춘다. aside 가 아니면(pid 재사용) 건드리지 않는다.
    @discardableResult
    public static func terminateLeftover(_ pid: Int32) -> Bool {
        guard isAsideProcess(pid) else { return false }
        E2ERunner.signalTree(pid, SIGTERM)
        return true
    }

    /// pid 가 아직 살아 있는 aside 프로세스인지 (pid 재사용으로 남의 프로세스를 죽이지 않게 실행 파일 이름을 본다).
    public static func isAsideProcess(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return false }
        return URL(fileURLWithPath: String(cString: buf)).lastPathComponent == "aside"
    }
}

public struct AsideModel: Equatable, Identifiable {
    public let id: String
    public let name: String
    public let minPlan: String
    /// "aside" = Aside 가 제공하는 모델, 그 외 = 사용자가 연동한 provider
    public let provider: String

    public init(id: String, name: String, minPlan: String, provider: String = "aside") {
        self.id = id
        self.name = name
        self.minPlan = minPlan
        self.provider = provider
    }

    /// free 가 아닌 요금제가 필요한 모델.
    public var needsPaidPlan: Bool { !minPlan.isEmpty && minPlan.lowercased() != "free" }
}

/// aside 출력에서 알아본 흔한 실패 원인. job.error 에는 `message` 가 그대로 남고, 결과 화면이 그 문장으로 할 일을 다시 찾는다.
public enum E2EFailureKind: CaseIterable {
    case cliOutdated, versionMismatch, modelUnavailable, signedOut, folderBlocked, windowClosed, asideDown

    public static func detect(in output: String) -> E2EFailureKind? {
        let t = output.lowercased()
        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }
        if AsideCLI.isUnknownOption(t) { return .cliOutdated }
        if has("no procedure found on path", "-procedure on path") { return .versionMismatch }
        if has("is not available for this account", "choose an available model") { return .modelUnavailable }
        if has("not signed in", "aside login", "sign in to", "sign in again", "needs sign-in", "requires sign-in",
               "unauthorized", "session expired", "login required") { return .signedOut }
        if has("operation not permitted", "path escapes", "blocked by policy", "permission denied") { return .folderBlocked }
        if has("is not connected to the daemon", "no browser profiles are connected", "start aside browser") { return .windowClosed }
        if has("econnrefused", "daemon", "is aside running", "could not connect", "failed to connect") { return .asideDown }
        return nil
    }

    public var message: String {
        switch self {
        case .cliOutdated: return AsideCLI.updateHint
        case .versionMismatch: return "Aside 브라우저와 CLI 버전이 서로 맞지 않아요 · 둘 다 최신으로 올린 뒤 다시 실행"
        case .modelUnavailable: return "고른 모델을 이 Aside 계정에서 쓸 수 없어요 · E2E 탭 실행 버튼 옆에서 다른 모델을 고르세요"
        case .signedOut: return "Aside 계정 로그인이 풀렸어요 · Aside 설정 > 계정에서 다시 로그인한 뒤 다시 실행"
        case .folderBlocked: return "Aside 가 실행용 폴더에 접근하지 못했어요 · run.log 를 확인해 주세요"
        case .windowClosed: return "Aside 브라우저 창이 닫혀 있었어요 · Aside 를 연 뒤 다시 실행"
        case .asideDown: return "Aside 앱에 연결하지 못했어요 · Aside 를 켠 뒤 다시 실행"
        }
    }

    /// 사용자가 할 일 (마지막은 늘 다시 실행).
    public var steps: [String] {
        switch self {
        case .cliOutdated:
            return ["'터미널에서 업데이트'로 Aside CLI 를 최신으로 올려요", "다시 실행해요"]
        case .versionMismatch:
            return ["'터미널에서 업데이트'로 Aside CLI 를 최신으로 올려요",
                    "Aside 브라우저도 최신 버전으로 올린 뒤 다시 켜요", "다시 실행해요"]
        case .modelUnavailable:
            return ["E2E 탭 실행 버튼 옆 메뉴에서 쓸 수 있는 모델(또는 Aside 기본 모델)을 골라요", "다시 실행해요"]
        case .signedOut:
            return ["'Aside 열기'를 눌러요", "Aside 설정(⌘,) > 계정에서 Aside 계정으로 다시 로그인해요", "다시 실행해요"]
        case .folderBlocked:
            return ["위의 '로그'로 run.log 에서 막힌 경로를 확인해요", "다시 실행해요"]
        case .windowClosed:
            return ["'Aside 열기'로 Aside 브라우저 창을 띄워요 (앱이 켜져 있어도 창이 없으면 실행하지 못해요)", "다시 실행해요"]
        case .asideDown:
            return ["'Aside 열기'로 Aside 를 켜요", "계속 안 되면 Aside 를 완전히 종료했다가 다시 켜요", "다시 실행해요"]
        }
    }

    public var fix: E2ESetupFix? {
        switch self {
        case .cliOutdated, .versionMismatch: return .updateCLI
        case .signedOut, .windowClosed, .asideDown: return .openAside
        case .modelUnavailable, .folderBlocked: return nil
        }
    }
}

public enum E2EFailureHint {
    public static func hint(for output: String) -> String? {
        E2EFailureKind.detect(in: output)?.message
    }

    /// result.json 이 없을 때 보여줄 한 줄.
    public static func missingResult(exitCode: Int32, output: String) -> String {
        if let h = hint(for: output) { return h }
        let last = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? ""
        return "결과 파일(result.json)이 없어요 (exit \(exitCode))" + (last.isEmpty ? "" : " · \(last.prefix(160))")
    }
}
