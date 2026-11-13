import Foundation

/// 검증할 테스트 환경. PR(운영)은 설정에서 켜야 고를 수 있고, 조회만 하라고 지시한다.
public enum E2EEnv: String, Codable, CaseIterable, Identifiable {
    case dv = "DV", st = "ST", st2 = "ST2", pr = "PR"

    public var id: String { rawValue }
    public var forcesReadOnly: Bool { self == .pr }

    /// 환경 칩·설정에 보일 환경. PR 은 allowPR 일 때만.
    public static func selectable(allowPR: Bool) -> [E2EEnv] {
        allCases.filter { $0 != .pr || allowPR }
    }
}

public enum E2EJobStatus: String, Codable {
    case queued, running, done, failed, cancelled

    public var isActive: Bool { self == .queued || self == .running }

    public var label: String {
        switch self {
        case .queued: return "대기"
        case .running: return "실행 중"
        case .done: return "완료"
        case .failed: return "실패"
        case .cancelled: return "취소됨"
        }
    }
}

public enum E2EVerdict: String, Codable, CaseIterable {
    case pass = "PASS", fail = "FAIL", blocked = "BLOCKED", skipped = "SKIPPED"

    /// 판정 수를 늘어놓는 순서 (나쁜 것부터).
    public static let displayOrder: [E2EVerdict] = [.fail, .blocked, .pass, .skipped]

    /// 대소문자·공백이 달라도 받아들인다. 모르는 값이면 nil.
    public init?(lenient raw: String?) {
        guard let raw else { return nil }
        self.init(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    /// 시나리오 판정 → 이슈 판정. FAIL 이 있으면 FAIL, 없고 BLOCKED 가 있으면 BLOCKED, 전부 SKIPPED 면 SKIPPED, 그 외 PASS. 비면 nil.
    public static func combine(_ verdicts: [E2EVerdict]) -> E2EVerdict? {
        guard !verdicts.isEmpty else { return nil }
        if verdicts.contains(.fail) { return .fail }
        if verdicts.contains(.blocked) { return .blocked }
        if verdicts.allSatisfy({ $0 == .skipped }) { return .skipped }
        return .pass
    }
}

public struct E2EIssueRef: Codable, Equatable, Identifiable {
    public var key: String
    public var url: String
    public var title: String
    /// ATM 이 Jira API 로 받아 둔 이슈 내용 파일 (job 폴더 기준 상대 경로). 없으면 Aside 가 브라우저로 연다.
    public var detailFile: String?

    public var id: String { key }

    public init(key: String, url: String, title: String, detailFile: String? = nil) {
        self.key = key
        self.url = url
        self.title = title
        self.detailFile = detailFile
    }

    /// 눌러서 열어도 되는 이슈 주소. ATM 이 Jira 주소로 만든 http(s) 만 받는다 (result.json 의 url 은 쓰지 않는다).
    public var webURL: URL? { E2EWebURL.parse(url) }
}

/// 눌러서 열어도 되는 웹 주소. http(s) 이고 호스트가 있을 때만.
public enum E2EWebURL {
    public static func parse(_ raw: String) -> URL? {
        guard let u = URL(string: raw), let scheme = u.scheme?.lowercased(), scheme == "https" || scheme == "http",
              u.host?.isEmpty == false else { return nil }
        return u
    }
}

/// 환경 로그인에 막힌 이유 (result.json 의 loginBlocked). 사용자가 Aside 에서 무엇을 하면 되는지 고르는 데 쓴다.
public enum E2ELoginBlock: String, CaseIterable {
    case vaultNotSetUp = "VAULT_NOT_SETUP", vaultLocked = "VAULT_LOCKED", noSavedLogin = "NO_SAVED_LOGIN"
    case wrongAccount = "WRONG_ACCOUNT", rejected = "LOGIN_REJECTED", twoFactor = "TWO_FACTOR", other = "OTHER"

    /// 비었거나 NONE·false 면 nil, 모르는 값은 other.
    public init?(lenient raw: String) {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !v.isEmpty, !["NONE", "NULL", "FALSE"].contains(v) else { return nil }
        self = Self(rawValue: v) ?? .other
    }

    public var reason: String {
        switch self {
        case .vaultNotSetUp: return "Aside Vault(비밀번호 관리자)를 아직 만들지 않았어요."
        case .vaultLocked: return "Aside Vault 가 잠겨 있어 저장된 로그인을 꺼내지 못했어요."
        case .noSavedLogin: return "Aside Vault 에 이 환경의 로그인이 없어요."
        case .wrongAccount: return "Aside Vault 에 저장된 로그인이 설정한 테스트 계정과 달라요."
        case .rejected: return "저장된 로그인으로 시도했지만 사이트가 받아 주지 않았어요 (비밀번호 변경·만료, 계정 잠김 등)."
        case .twoFactor: return "2단계 인증 코드가 필요한데 Aside 가 넣을 수 없었어요."
        case .other: return "자동 로그인이 끝까지 되지 않았어요 (SSO 등)."
        }
    }

    /// 사용자가 할 일 (마지막은 늘 다시 실행). account 는 "테스트 계정(qa)" 처럼 보여줄 이름.
    public func steps(account: String) -> [String] {
        switch self {
        case .vaultNotSetUp:
            return ["Aside 에서 로그인 페이지를 열어요",
                    "\(account)으로 직접 로그인해요",
                    "로그인 정보를 저장할지 물으면 Aside Vault 를 만들고 저장해요",
                    "다시 실행해요"]
        case .vaultLocked:
            return ["Aside 에서 로그인 페이지를 열어요",
                    "아이디 칸의 자동 채우기에서 Vault 잠금을 풀어요",
                    "다시 실행해요"]
        case .noSavedLogin:
            return ["Aside 에서 로그인 페이지를 열어요",
                    "\(account)으로 직접 로그인해요",
                    "로그인 정보를 저장할지 물으면 Aside Vault 에 저장해요",
                    "다시 실행해요"]
        case .wrongAccount:
            return ["Aside 에서 로그인 페이지를 열어 \(account)으로 직접 로그인하고 Aside Vault 에 저장해요",
                    "저장돼 있는 계정으로 검증하려면 설정 > E2E 의 계정 ID 를 그 계정으로 바꾸거나 비워요",
                    "다시 실행해요"]
        case .rejected:
            return ["Aside 에서 로그인 페이지를 열어 \(account)으로 직접 로그인해 봐요",
                    "비밀번호가 바뀌었으면 새 비밀번호로 로그인하고 Aside Vault 의 저장된 로그인을 바꿔요",
                    "계정이 잠겼으면 잠금을 먼저 풀어요 (여러 번 다시 실행하면 더 오래 잠길 수 있어요)",
                    "다시 실행해요"]
        case .twoFactor:
            return ["Aside 에서 로그인 페이지를 열어 \(account)으로 직접 로그인하고 인증까지 마쳐요",
                    "인증기(OTP)를 Aside Vault 의 그 로그인에 등록해 두면 다음부터 Aside 가 코드를 넣어요",
                    "로그인이 남아 있는 동안 다시 실행해요"]
        case .other:
            return ["Aside 에서 로그인 페이지를 열어 \(account)으로 직접 로그인해 두면 다음 실행이 그 로그인을 이어 써요",
                    "다시 실행해요"]
        }
    }
}

/// Aside 에 넘기는 요청(request.json). 에이전트가 알아야 할 것만 담는다.
public struct E2ERequest: Codable, Equatable {
    public var jobId: String
    public var env: E2EEnv
    public var baseUrl: String
    public var username: String
    public var readOnly: Bool
    public var notes: String
    public var issues: [E2EIssueRef]

    public init(_ job: E2EJob) {
        jobId = job.id
        env = job.env
        baseUrl = job.baseUrl
        username = job.username
        readOnly = job.readOnly
        notes = job.notes
        issues = job.issues
    }
}

/// job.json 의 ATM 쪽 모델. Aside 는 이 파일을 보지 않고 E2ERequest 를 받는다.
public struct E2EJob: Codable, Equatable, Identifiable {
    public var id: String
    public var env: E2EEnv
    public var baseUrl: String
    public var username: String
    public var readOnly: Bool
    public var issues: [E2EIssueRef]
    public var notes: String
    public var requestedBy: String
    public var status: E2EJobStatus
    public var createdAt: Date
    public var finishedAt: Date?
    public var error: String?
    public var sessionId: String?
    /// aside --model 로 넘긴 모델. nil 이면 Aside 기본.
    public var model: String?
    /// 결과를 Jira 댓글로 남긴 이슈 키 → 남긴 시각(ISO8601). 같은 결과를 실수로 두 번 남기지 않게 보여준다.
    public var jiraComments: [String: String] = [:]

    public init(id: String, env: E2EEnv, baseUrl: String, username: String, issues: [E2EIssueRef],
                notes: String = "", requestedBy: String = "", status: E2EJobStatus = .queued, createdAt: Date = Date(),
                finishedAt: Date? = nil, error: String? = nil, sessionId: String? = nil, model: String? = nil) {
        self.id = id
        self.env = env
        self.baseUrl = baseUrl
        self.username = username
        self.readOnly = env.forcesReadOnly
        self.issues = issues
        self.notes = notes
        self.requestedBy = requestedBy
        self.status = status
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.error = error
        self.sessionId = sessionId
        self.model = model
    }

    enum CodingKeys: String, CodingKey {
        case id, env, baseUrl, username, readOnly, issues, notes, requestedBy, status, createdAt, finishedAt, error, sessionId, model
        case jiraComments
    }

    /// 손으로 고쳤거나 이전 버전이 쓴 job.json 도 읽도록 모양이 조금 달라도 받아들인다.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        env = E2EEnv(rawValue: c.lenientString(.env).uppercased()) ?? .dv
        baseUrl = c.lenientString(.baseUrl)
        username = c.lenientString(.username)
        readOnly = (try? c.decodeIfPresent(Bool.self, forKey: .readOnly)) ?? env.forcesReadOnly
        issues = (try? c.decodeIfPresent([E2EIssueRef].self, forKey: .issues)) ?? []
        notes = c.lenientString(.notes)
        requestedBy = c.lenientString(.requestedBy)
        status = Self.status(c.lenientString(.status))
        createdAt = E2EDate.parse(c.lenientString(.createdAt)) ?? E2EJobID.date(id) ?? .distantPast
        finishedAt = E2EDate.parse(c.lenientString(.finishedAt))
        error = c.lenientString(.error).nilIfEmpty
        sessionId = c.lenientString(.sessionId).nilIfEmpty
        model = c.lenientString(.model).nilIfEmpty
        jiraComments = (try? c.decodeIfPresent([String: String].self, forKey: .jiraComments)) ?? [:]
        if env.forcesReadOnly { readOnly = true }
    }

    static func status(_ raw: String) -> E2EJobStatus {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let v = E2EJobStatus(rawValue: s) { return v }
        switch s {
        case "completed", "complete", "success": return .done
        case "canceled": return .cancelled
        default: return .failed
        }
    }

    /// 판정 뱃지·이력용 이슈 키 목록.
    public var issueKeys: [String] { issues.map(\.key) }
}

public struct E2EScenario: Equatable, Decodable {
    public var name: String
    public var steps: [String]
    public var expected: String
    public var actual: String
    public var verdict: E2EVerdict?
    public var screenshots: [String]

    public init(name: String, steps: [String] = [], expected: String = "", actual: String = "",
                verdict: E2EVerdict?, screenshots: [String] = []) {
        self.name = name
        self.steps = steps
        self.expected = expected
        self.actual = actual
        self.verdict = verdict
        self.screenshots = screenshots
    }

    enum CodingKeys: String, CodingKey { case name, steps, expected, actual, verdict, screenshots, screenshot }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenientString(.name)
        steps = c.lenientStrings(.steps)
        expected = c.lenientString(.expected)
        actual = c.lenientString(.actual)
        verdict = E2EVerdict(lenient: c.lenientString(.verdict))
        // 팩의 보드는 screenshot(단수)도 받는다.
        let many = c.lenientStrings(.screenshots)
        screenshots = many.isEmpty ? c.lenientStrings(.screenshot) : many
    }
}

public struct E2EIssueResult: Equatable, Decodable {
    public var key: String
    public var title: String
    public var url: String
    /// Aside 가 적은 이슈 판정. 시나리오가 있으면 `verdict` 는 시나리오에서 다시 계산한다.
    public var reportedVerdict: E2EVerdict?
    public var assumptions: [String]
    public var scenarios: [E2EScenario]
    public var notes: String

    public init(key: String, title: String = "", url: String = "", reportedVerdict: E2EVerdict? = nil,
                assumptions: [String] = [], scenarios: [E2EScenario] = [], notes: String = "") {
        self.key = key
        self.title = title
        self.url = url
        self.reportedVerdict = reportedVerdict
        self.assumptions = assumptions
        self.scenarios = scenarios
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey { case key, title, url, verdict, assumptions, scenarios, notes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.lenientString(.key).uppercased()
        title = c.lenientString(.title)
        url = c.lenientString(.url)
        reportedVerdict = E2EVerdict(lenient: c.lenientString(.verdict))
        assumptions = c.lenientStrings(.assumptions)
        scenarios = (try? c.decodeIfPresent([E2EScenario].self, forKey: .scenarios)) ?? []
        notes = c.lenientStrings(.notes).joined(separator: "\n")
    }

    public var verdict: E2EVerdict? {
        E2EVerdict.combine(scenarios.compactMap(\.verdict)) ?? reportedVerdict
    }
}

/// result.json (Aside 가 작성). 누락 필드는 기본값으로 채운다.
public struct E2EResult: Equatable, Decodable {
    public var status: String
    public var startedAt: String
    public var finishedAt: String
    public var summary: String
    /// 환경 로그인에 막혔을 때만 있다.
    public var loginBlocked: E2ELoginBlock?
    public var issues: [E2EIssueResult]

    public init(status: String = "done", startedAt: String = "", finishedAt: String = "", summary: String = "",
                loginBlocked: E2ELoginBlock? = nil, issues: [E2EIssueResult]) {
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.summary = summary
        self.loginBlocked = loginBlocked
        self.issues = issues
    }

    enum CodingKeys: String, CodingKey { case status, startedAt, finishedAt, summary, loginBlocked, issues }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = c.lenientString(.status)
        startedAt = c.lenientString(.startedAt)
        finishedAt = c.lenientString(.finishedAt)
        summary = c.lenientString(.summary)
        loginBlocked = E2ELoginBlock(lenient: c.lenientString(.loginBlocked))
        issues = try c.decode([E2EIssueResult].self, forKey: .issues)
    }

    public static func decode(_ data: Data) throws -> E2EResult {
        try JSONDecoder().decode(E2EResult.self, from: data)
    }

    /// 판정별 이슈 수 (판정을 알 수 없는 이슈는 세지 않는다).
    public var counts: [E2EVerdict: Int] {
        issues.reduce(into: [:]) { acc, i in if let v = i.verdict { acc[v, default: 0] += 1 } }
    }
}

/// 판정 뱃지용: 이슈 키 → 가장 최근 완료 job 의 판정.
public enum E2ELatestVerdicts {
    public static func build(_ entries: [(job: E2EJob, result: E2EResult)]) -> [String: (verdict: E2EVerdict, jobId: String)] {
        var out: [String: (verdict: E2EVerdict, jobId: String)] = [:]
        for e in entries.sorted(by: { $0.job.createdAt < $1.job.createdAt }) {
            for i in e.result.issues {
                guard let v = i.verdict else { continue }
                out[i.key] = (v, e.job.id)
            }
        }
        return out
    }
}

public enum E2EJobID {
    private static func formatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmmss"
        return f
    }

    /// `YYYYMMDDHHmmss-xxxx` (로컬 시각 + 소문자·숫자 4자).
    public static func make(now: Date = Date(), suffix: String? = nil) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let s = suffix ?? String((0..<4).map { _ in chars.randomElement()! })
        return "\(formatter().string(from: now))-\(s)"
    }

    /// 폴더 이름으로 써도 안전한 id 인지 (경로 조작 방지).
    public static func isValid(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    static func date(_ id: String) -> Date? {
        formatter().date(from: String(id.prefix(14)))
    }
}

public enum E2EDate {
    public static func string(_ d: Date) -> String {
        ISO8601DateFormatter().string(from: d)
    }

    /// ISO8601 (소수 초 있어도 됨). 비거나 모르는 모양이면 nil.
    public static func parse(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: t) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: t)
    }
}

/// 사용자가 입력한 이슈 키·링크 → 중복 없는 대문자 키 목록 (입력 순서 유지).
public enum E2EIssueKeys {
    private static let keyPattern = try! NSRegularExpression(pattern: "^[A-Z][A-Z0-9_]+-[0-9]+$")

    public static func parse(_ raw: String) -> [String] {
        let tokens = raw.components(separatedBy: CharacterSet(charactersIn: ",; \t\n\r"))
        var seen = Set<String>(), out: [String] = []
        for t in tokens {
            guard let key = key(from: t), seen.insert(key).inserted else { continue }
            out.append(key)
        }
        return out
    }

    static func key(from token: String) -> String? {
        let t = token.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if t.contains("://"), let comps = URLComponents(string: t) {
            if let q = comps.queryItems?.first(where: { $0.name == "selectedIssue" })?.value, isKey(q.uppercased()) {
                return q.uppercased()
            }
            let parts = comps.path.split(separator: "/").map(String.init)
            if let i = parts.firstIndex(of: "browse"), i + 1 < parts.count, isKey(parts[i + 1].uppercased()) {
                return parts[i + 1].uppercased()
            }
            return nil
        }
        let up = t.uppercased()
        return isKey(up) ? up : nil
    }

    static func isKey(_ s: String) -> Bool {
        keyPattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
}

/// 실행 제한 시간: 이슈당 분 × 이슈 수, 최대값으로 자른다.
public enum E2ERunPolicy {
    public static func timeout(issueCount: Int, minutesPerIssue: Int, maxMinutes: Int) -> TimeInterval {
        let per = max(1, minutesPerIssue), cap = max(per, maxMinutes)
        return TimeInterval(min(per * max(1, issueCount), cap) * 60)
    }
}

extension KeyedDecodingContainer {
    /// 문자열·숫자·불리언·문자열 배열(줄바꿈으로 합침) 중 무엇이든 문자열로. 없거나 다른 모양이면 "".
    func lenientString(_ key: Key) -> String {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let n = try? decodeIfPresent(Double.self, forKey: key) {
            return n == n.rounded() ? String(Int(n)) : String(n)
        }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return String(b) }
        if let a = try? decodeIfPresent([String].self, forKey: key) { return a.joined(separator: "\n") }
        return ""
    }

    /// 문자열 배열, 또는 문자열 하나. 빈 항목은 버린다.
    func lenientStrings(_ key: Key) -> [String] {
        if let a = try? decodeIfPresent([String].self, forKey: key) { return a.filter { !$0.isEmpty } }
        if let s = try? decodeIfPresent(String.self, forKey: key), !s.isEmpty { return [s] }
        return []
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
