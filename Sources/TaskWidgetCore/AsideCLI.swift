import Darwin
import Foundation

public enum AsideAccountStatus: Equatable {
    /// email 이 없으면 이름. plan 은 free·pro 등 (모르면 "").
    case signedIn(email: String, accountId: Int, plan: String)
    case signedOut
    /// 확인 실패 (명령 오류·시간 초과·모르는 출력). 사용자에게 보여줄 한 줄.
    case unknown(String)
}

/// Aside CLI 를 찾고 부르는 방법. 스파이크(Aside CLI 1.26)에서 확인한 동작 기준:
/// - 기본(guard) 권한은 job 폴더 읽기/쓰기를 막아 `--permission full-access` 가 필요하다.
/// - 실행 결과와 상관없이 exit 0 일 수 있어 성공 판단은 result.json 으로만 한다.
/// - CLI 에 SIGTERM 을 보내면 세션도 aborted 로 멈춘다. `--timeout` 은 CLI 만 멈추고 세션은 계속 돌아서 쓰지 않는다.
public enum AsideCLI {
    public static let installCommand = "curl -fsSL https://releases.aside.com/install.sh | bash"
    public static let loginCommand = "aside login --email \"<이메일>\""

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

    /// `aside exec` 인자. 셸을 거치지 않고 배열로 넘긴다. model 이 비면 Aside 설정의 기본 모델.
    public static func execArguments(prompt: String, model: String = "") -> [String] {
        let m = model.trimmingCharacters(in: .whitespaces)
        return ["exec", "--permission", "full-access"] + (m.isEmpty ? [] : ["--model", m]) + [prompt]
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

    /// `aside account status --json` 결과 해석. 로그인돼 있으면 이메일(없으면 이름).
    public static func parseAccountStatus(stdout: String, exitCode: Int32) -> AsideAccountStatus {
        struct Wrap: Decodable { let account: Account? }
        struct Account: Decodable {
            let id: Int?; let email: String?; let name: String?; let authStatus: String?; let hasSession: Bool?; let subscriptionPlan: String?
        }
        let lower = stdout.lowercased()
        guard let data = stdout.data(using: .utf8), let w = try? JSONDecoder().decode(Wrap.self, from: data) else {
            if lower.contains("not signed in") || lower.contains("aside login") { return .signedOut }
            let last = stdout.split(separator: "\n").last.map(String.init) ?? ""
            return .unknown(exitCode == 0 ? "알 수 없는 응답: \(last.prefix(120))" : "aside 오류 (exit \(exitCode)) \(last.prefix(120))")
        }
        guard let a = w.account else { return .signedOut }
        if a.authStatus?.lowercased() == "active" && a.hasSession != false {
            return .signedIn(email: a.email ?? a.name ?? "", accountId: a.id ?? 0, plan: a.subscriptionPlan ?? "")
        }
        return .signedOut
    }

    public static func accountStatus(executable: String) -> AsideAccountStatus {
        let r = ProcessRunner.run(executable: executable, arguments: ["account", "status", "--json"],
                                  environment: environment(executable: executable), timeout: 15)
        if r.timedOut { return .unknown("aside 응답 없음 (15초) · Aside 앱이 켜져 있는지 확인") }
        let out = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return parseAccountStatus(stdout: out.isEmpty ? r.stderr : out, exitCode: r.status)
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

/// aside 출력에서 흔한 실패 원인을 알아본다.
public enum E2EFailureHint {
    public static func hint(for output: String) -> String? {
        let t = output.lowercased()
        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }
        if has("is not available for this account", "choose an available model") {
            return "고른 모델을 이 Aside 계정에서 쓸 수 없어요 · E2E 탭 실행 버튼 옆에서 다른 모델을 고르세요"
        }
        if has("not signed in", "aside login", "sign in to", "unauthorized", "session expired", "login required") {
            return "Aside CLI 로그인이 필요해요 · 터미널에서 aside login 후 Aside 설정 > 계정 > 기기에서 승인"
        }
        if has("operation not permitted", "path escapes", "blocked by policy", "permission denied") {
            return "Aside 가 job 폴더에 접근하지 못했어요 · run.log 를 확인해 주세요"
        }
        if has("econnrefused", "daemon", "is aside running", "could not connect", "failed to connect") {
            return "Aside 앱에 연결하지 못했어요 · Aside 를 켠 뒤 다시 실행"
        }
        return nil
    }

    /// result.json 이 없을 때 보여줄 한 줄.
    public static func missingResult(exitCode: Int32, output: String) -> String {
        if let h = hint(for: output) { return h }
        let last = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? ""
        return "결과 파일(result.json)이 없어요 (exit \(exitCode))" + (last.isEmpty ? "" : " · \(last.prefix(160))")
    }
}
