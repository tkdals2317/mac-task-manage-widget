import Foundation

/// 직무(설정 도우미 첫 단계). 저장값은 rawValue.
public enum UserRole: String, CaseIterable, Sendable {
    case developer, planner, custom

    public var title: String {
        switch self {
        case .developer: return "개발자"
        case .planner: return "기획자"
        case .custom: return "직접 고를게요"
        }
    }
    /// 설정 > 창·일반 의 짧은 이름
    public var shortTitle: String { self == .custom ? "직접" : title }
}

/// 할 일 탭 Jira 목록 기준. `keep` 은 저장된 사용자 JQL 을 건드리지 않는 값.
public enum JiraListScope: String, CaseIterable, Sendable {
    case assignee, reporter, both, keep
}

public enum SetupStep: String, Sendable {
    case role, storage, atlassian, notes, pr, prRepos, e2e, claude, teleport, finish

    public var title: String {
        switch self {
        case .role: return "직무"
        case .storage: return "저장 위치"
        case .atlassian: return "Atlassian"
        case .notes: return "노트"
        case .pr: return "PR"
        case .prRepos: return "PR 저장소"
        case .e2e: return "E2E"
        case .claude: return "Claude"
        case .teleport: return "Teleport"
        case .finish: return "마무리"
        }
    }
}

/// 직무가 정하는 값 묶음.
public struct RolePlan: Equatable, Sendable {
    public var tabs: Set<String>
    public var jira: JiraListScope
    /// "assignee" | "reporter"
    public var e2eScope: String
    public init(tabs: Set<String>, jira: JiraListScope, e2eScope: String) {
        self.tabs = tabs; self.jira = jira; self.e2eScope = e2eScope
    }
}

/// 직무별 기본값과 JQL 매핑, 설정 도우미 단계 계산 (순수 로직).
public enum RolePreset {
    /// 앱 탭 순서.
    public static let tabOrder = ["tasks", "summary", "notes", "pr", "e2e", "teleport"]

    public static let bothJQL = "(assignee = currentUser() OR reporter = currentUser()) AND statusCategory != Done ORDER BY updated DESC"

    public static func preset(for role: UserRole) -> RolePlan {
        switch role {
        case .developer: return RolePlan(tabs: ["tasks", "summary", "notes", "pr", "teleport"], jira: .assignee, e2eScope: "assignee")
        case .planner: return RolePlan(tabs: ["tasks", "notes", "e2e"], jira: .reporter, e2eScope: "reporter")
        case .custom: return RolePlan(tabs: [], jira: .assignee, e2eScope: "assignee")
        }
    }

    /// 범위 → 저장할 JQL (담당 = 빈 값 = 기본). `keep` 은 nil (건드리지 않음).
    public static func jql(for scope: JiraListScope) -> String? {
        switch scope {
        case .assignee: return ""
        case .reporter: return JiraClient.reporterJQL
        case .both: return bothJQL
        case .keep: return nil
        }
    }

    /// 저장된 JQL → 범위. 아무것도 아니면(직접 쓴 JQL) `keep`.
    public static func scope(forJQL raw: String) -> JiraListScope {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == JiraClient.defaultJQL { return .assignee }
        if t == JiraClient.reporterJQL { return .reporter }
        if t == bothJQL { return .both }
        return .keep
    }

    /// 탭 집합 → `enabledTabs` 저장 문자열 (앱 탭 순서).
    public static func tabsString(_ tabs: Set<String>) -> String {
        tabOrder.filter { tabs.contains($0) }.joined(separator: ",")
    }

    /// 선택한 탭이 하나라도 있는지 (없으면 다음으로 못 간다).
    public static func isValid(tabs: Set<String>) -> Bool { !tabs.isDisjoint(with: tabOrder) }

    /// Atlassian(Jira·Confluence) 계정이 필요한지: 할 일 · E2E · 노트.
    public static func needsAtlassian(_ tabs: Set<String>) -> Bool {
        tabs.contains("tasks") || tabs.contains("e2e") || tabs.contains("notes")
    }

    /// 선택한 탭에 해당하는 단계 목록 (role 로 시작, finish 로 끝). prRepos 는 Bitbucket 연결 확인 뒤에만.
    public static func steps(tabs: Set<String>, showPRRepos: Bool = false) -> [SetupStep] {
        var s: [SetupStep] = [.role]
        let atl = needsAtlassian(tabs)
        if atl || tabs.contains("teleport") || tabs.contains("pr") { s.append(.storage) }
        if atl { s.append(.atlassian) }
        if tabs.contains("notes") { s.append(.notes) }
        if tabs.contains("pr") {
            s.append(.pr)
            if showPRRepos { s.append(.prRepos) }
        }
        if tabs.contains("e2e") { s.append(.e2e) }
        if tabs.contains("summary") { s.append(.claude) }
        if tabs.contains("teleport") { s.append(.teleport) }
        s.append(.finish)
        return s
    }

    /// "다음: 저장 위치 → Atlassian → … → 마무리". 4개를 넘으면 가운데를 줄인다.
    public static func previewLine(_ steps: [SetupStep]) -> String {
        let rest = steps.dropFirst().map(\.title)
        let shown = rest.count > 4 ? Array(rest.prefix(2)) + ["…", rest[rest.count - 1]] : Array(rest)
        return "다음: " + shown.joined(separator: " → ")
    }

    /// 계획을 설정에 적용한다. `keep` 이면 JQL 은 그대로.
    public static func apply(_ plan: RolePlan, to s: Settings) {
        if isValid(tabs: plan.tabs) { s.enabledTabs = tabsString(plan.tabs) }
        if let q = jql(for: plan.jira) { s.jiraJQL = q }
        s.e2eIssueScope = plan.e2eScope == "reporter" ? "reporter" : "assignee"
    }
}
