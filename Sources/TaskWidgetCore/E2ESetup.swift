import Foundation

/// 준비 항목에서 누를 수 있는 동작. 실제 동작은 앱(E2EModel)이 한다.
public enum E2ESetupFix: Equatable {
    case downloadBrowser
    case installCLI
    case updateCLI
    case openAside
    /// 검증에 쓸 Aside 계정을 바꾼다
    case switchAccount(id: Int, title: String)
    case openSettings
    /// 고른 환경을 Aside 브라우저에서 연다 (직접 로그인하고 Vault 에 저장하는 용도)
    case openEnvironment

    public var label: String {
        switch self {
        case .downloadBrowser: return "Aside 다운로드"
        case .installCLI: return "터미널에서 설치"
        case .updateCLI: return "터미널에서 업데이트"
        case .openAside: return "Aside 열기"
        case .switchAccount(_, let title): return "\(title) 계정으로 바꾸기"
        case .openSettings: return "설정 열기"
        case .openEnvironment: return "Aside 에서 열기"
        }
    }

    public var icon: String {
        switch self {
        case .downloadBrowser: return "arrow.down.circle"
        case .installCLI, .updateCLI: return "terminal"
        case .openAside: return "macwindow"
        case .switchAccount: return "person.crop.circle"
        case .openSettings: return "gearshape"
        case .openEnvironment: return "arrow.up.right.square"
        }
    }
}

/// 고른 환경의 지난 검증에서 로그인이 어땠는지. Vault 상태는 실행 전에 알 수 없어 지난 결과로 안내한다.
public enum E2ELoginHistory: Equatable {
    case none
    case ok
    case blocked(E2ELoginBlock)

    /// 같은 환경·주소로 끝난 가장 최근 검증을 본다. finished 는 최신순.
    public static func latest(env: E2EEnv, baseUrl: String, finished: [(job: E2EJob, result: E2EResult)]) -> E2ELoginHistory {
        guard let last = finished.first(where: { $0.job.env == env && $0.job.baseUrl == baseUrl }) else { return .none }
        if let block = last.result.loginBlocked { return .blocked(block) }
        // 전부 BLOCKED 면 로그인까지 갔는지 알 수 없다
        let reached = last.result.issues.contains { $0.verdict != nil && $0.verdict != .blocked }
        return reached ? .ok : .none
    }
}

/// 준비 점검의 한 줄.
public struct E2ESetupItem: Equatable, Identifiable {
    public enum Kind: String { case browser, cli, account, window, envURL, envLogin }
    /// todo: 실행을 막는다. warn·info: 실행은 되지만 봐야 한다. waiting: 앞 단계가 끝나야 알 수 있다.
    public enum State { case ok, todo, warn, info, waiting }

    public let kind: Kind
    public var state: State
    public var title: String
    public var detail: String
    public var steps: [String]
    public var note: String
    public var fixes: [E2ESetupFix]

    public init(kind: Kind, state: State, title: String, detail: String, steps: [String] = [], note: String = "",
                fixes: [E2ESetupFix] = []) {
        self.kind = kind
        self.state = state
        self.title = title
        self.detail = detail
        self.steps = steps
        self.note = note
        self.fixes = fixes
    }

    public var id: Kind { kind }
    public var needsAttention: Bool { state == .todo || state == .warn || state == .info }
}

public struct E2ESetupInput {
    public var browserInstalled: Bool
    public var browserVersion: String
    /// Aside CLI 를 못 찾았으면 nil
    public var probe: AsideProbe?
    /// 환경 항목을 볼 환경. nil 이면 Aside 항목만.
    public var env: E2EEnv?
    public var envURL: String
    public var envUser: String
    public var lastLogin: E2ELoginHistory

    public init(browserInstalled: Bool, browserVersion: String = "", probe: AsideProbe?, env: E2EEnv? = nil,
                envURL: String = "", envUser: String = "", lastLogin: E2ELoginHistory = .none) {
        self.browserInstalled = browserInstalled
        self.browserVersion = browserVersion
        self.probe = probe
        self.env = env
        self.envURL = envURL
        self.envUser = envUser
        self.lastLogin = lastLogin
    }
}

/// 검증을 돌리기까지 필요한 준비를 순서대로 본다: Aside 브라우저 → CLI → Aside 계정 → 창 → 환경 주소 → 환경 로그인.
public enum E2ESetup {
    public static func items(_ i: E2ESetupInput) -> [E2ESetupItem] {
        var out = [browser(i), cli(i), account(i)]
        if let w = window(i) { out.append(w) }
        if let env = i.env { out.append(environment(env, i)) }
        return out
    }

    /// 실행을 막는 첫 항목.
    public static func blocker(_ items: [E2ESetupItem]) -> E2ESetupItem? {
        items.first { $0.state == .todo }
    }

    private static func waiting(_ kind: E2ESetupItem.Kind, _ title: String) -> E2ESetupItem {
        E2ESetupItem(kind: kind, state: .waiting, title: title, detail: "앞 단계를 마치면 확인해요")
    }

    private static func browser(_ i: E2ESetupInput) -> E2ESetupItem {
        let title = "Aside 브라우저"
        if i.browserInstalled {
            return E2ESetupItem(kind: .browser, state: .ok, title: title,
                                detail: i.browserVersion.isEmpty ? "설치됨" : "설치됨 · \(i.browserVersion)")
        }
        // CLI 가 있으면 브라우저는 다른 위치에 설치된 것으로 보고 막지 않는다
        if i.probe != nil {
            return E2ESetupItem(kind: .browser, state: .ok, title: title, detail: "앱 위치는 찾지 못했어요")
        }
        return E2ESetupItem(kind: .browser, state: .todo, title: title, detail: "Aside 브라우저가 없어요",
                            steps: ["'Aside 다운로드'로 내려받아 설치해요",
                                    "Aside 를 열고 Aside 계정으로 로그인해요",
                                    "'다시 확인'을 눌러요"],
                            fixes: [.downloadBrowser])
    }

    private static func cli(_ i: E2ESetupInput) -> E2ESetupItem {
        let title = "Aside CLI"
        guard let p = i.probe else {
            guard i.browserInstalled else { return waiting(.cli, title) }
            return E2ESetupItem(kind: .cli, state: .todo, title: title, detail: "Aside CLI 가 없어요",
                                steps: ["'터미널에서 설치'를 누르면 공식 설치 명령이 터미널에서 돌아요",
                                        "설치가 끝나면 ATM 이 알아서 다시 확인해요"],
                                fixes: [.installCLI])
        }
        let version = p.version.isEmpty ? "설치됨" : p.version
        if !p.runnable {
            return E2ESetupItem(kind: .cli, state: .todo, title: title, detail: "Aside CLI(\(version))가 오래돼 검증을 돌릴 수 없어요",
                                steps: ["'터미널에서 업데이트'로 최신으로 올려요",
                                        "Aside 브라우저도 최신 버전으로 올려요",
                                        "끝나면 ATM 이 알아서 다시 확인해요"],
                                fixes: [.updateCLI])
        }
        if p.updateAvailable {
            return E2ESetupItem(kind: .cli, state: .ok, title: title, detail: "\(version) · 새 버전 \(p.latestVersion) 있음",
                                note: "검증이 이유 없이 실패하면 CLI 와 Aside 브라우저를 둘 다 최신으로 올려 보세요.",
                                fixes: [.updateCLI])
        }
        return E2ESetupItem(kind: .cli, state: .ok, title: title, detail: version)
    }

    private static func account(_ i: E2ESetupInput) -> E2ESetupItem {
        let title = "Aside 계정"
        guard let p = i.probe else { return waiting(.account, title) }
        let others = p.otherAccounts.filter(\.signedIn)
        let switches = others.map { E2ESetupFix.switchAccount(id: $0.id, title: $0.title) }
        switch p.account {
        case .signedIn(let email, let id, _):
            var item = E2ESetupItem(kind: .account, state: .ok, title: title, detail: "\(email.isEmpty ? "로그인됨" : email) (u\(id))")
            if !p.otherAccounts.isEmpty {
                item.note = "Aside 에 계정이 \(p.otherAccounts.count + 1)개 있어요. 검증은 위 계정으로 돌고, 테스트 환경 로그인도 이 계정의 Vault 에 있어야 해요."
                item.fixes = switches
            }
            return item
        case .signedOut(let who, let reason):
            let name = who.isEmpty ? "Aside 계정" : "Aside 계정(\(who))"
            let detail: String
            switch reason {
            case .never: detail = "Aside 브라우저에 Aside 계정으로 로그인해야 해요"
            case .noSession: detail = "\(name) 로그인이 풀렸어요"
            case .paused(let why): detail = "\(name) 로그인이 멈췄어요" + pausedNote(why)
            }
            var item = E2ESetupItem(kind: .account, state: .todo, title: title, detail: detail,
                                    steps: ["'Aside 열기'를 눌러요",
                                            "Aside 설정(⌘,) > 계정에서 Aside 계정으로 로그인해요",
                                            "로그인하면 ATM 이 알아서 다시 확인해요 (터미널의 aside login 은 필요 없어요)"],
                                    fixes: [.openAside] + switches)
            if !others.isEmpty {
                item.note = "다른 계정(\(others.map(\.title).joined(separator: ", ")))은 로그인돼 있어요. 그 계정으로 검증하려면 계정을 바꿔요."
            }
            return item
        case .unknown(let message):
            return E2ESetupItem(kind: .account, state: .todo, title: title, detail: "Aside 상태를 확인하지 못했어요 · \(message)",
                                steps: ["'Aside 열기'로 Aside 를 켜고 '다시 확인'을 눌러요",
                                        "계속 안 되면 '터미널에서 업데이트'로 CLI 를 올려요"],
                                fixes: [.openAside, .updateCLI])
        }
    }

    private static func pausedNote(_ why: String) -> String {
        switch why {
        case "device_mismatch": return " (기기 정보가 달라졌어요)"
        case "token_revoked": return " (로그인이 해제됐어요)"
        default: return ""
        }
    }

    /// 창이 닫혀 있어도 실행할 때 ATM 이 Aside 를 열기 때문에 막지는 않는다.
    private static func window(_ i: E2ESetupInput) -> E2ESetupItem? {
        guard let p = i.probe, case .signedIn = p.account, let open = p.windowOpen else { return nil }
        let title = "Aside 창"
        if open { return E2ESetupItem(kind: .window, state: .ok, title: title, detail: "열려 있어요") }
        return E2ESetupItem(kind: .window, state: .warn, title: title, detail: "Aside 창이 닫혀 있어요 · 실행하면 ATM 이 Aside 를 열어요",
                            fixes: [.openAside])
    }

    private static func environment(_ env: E2EEnv, _ i: E2ESetupInput) -> E2ESetupItem {
        let name = env.rawValue
        guard !i.envURL.trimmingCharacters(in: .whitespaces).isEmpty else {
            return E2ESetupItem(kind: .envURL, state: .todo, title: "\(name) 환경 주소", detail: "\(name) 환경 주소가 없어요",
                                steps: ["설정 > E2E 의 환경에 \(name) 주소를 넣어요"], fixes: [.openSettings])
        }
        let account = i.envUser.isEmpty ? "테스트 계정" : "테스트 계정(\(i.envUser))"
        let title = "\(name) 로그인"
        switch i.lastLogin {
        case .ok:
            return E2ESetupItem(kind: .envLogin, state: .ok, title: title, detail: "지난 검증에서 자동으로 로그인됐어요")
        case .blocked(let block):
            return E2ESetupItem(kind: .envLogin, state: .warn, title: title, detail: "지난 검증에서 막혔어요 · \(block.reason)",
                                steps: block.steps(account: account), fixes: [.openEnvironment])
        case .none:
            return E2ESetupItem(kind: .envLogin, state: .info, title: title, detail: "처음이면 테스트 계정 로그인을 Aside 에 저장해 두세요",
                                steps: ["'Aside 에서 열기'로 \(name) 환경을 열어 \(account)으로 직접 로그인해요",
                                        "로그인 정보를 저장할지 물으면 Aside Vault 에 저장해요 (Vault 가 없으면 이때 만들어요)",
                                        "Vault 잠금을 풀어 둔 채로 실행해요"],
                                note: "비밀번호는 Aside 에서 직접 입력해요. ATM 과 Aside 에이전트는 비밀번호를 보지 않아요.",
                                fixes: [.openEnvironment])
        }
    }
}
