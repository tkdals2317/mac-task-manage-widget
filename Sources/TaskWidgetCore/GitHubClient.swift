import Foundation

public enum PRError: Error, Equatable, Sendable {
    case unauthorized
    /// 요청 한도. retryAfter(초)는 모르면 nil.
    case rateLimited(TimeInterval?, String)
    case http(Int)
    case network(String)
    case decode(String)
    case message(String)

    /// 응답 코드·헤더로 오류 종류를 가린다. 한도 초과(429, Retry-After, 남은 한도 0)는 인증 실패와 구분한다.
    public static func classify(code: Int, remaining: String?, retryAfter: String?, reset: String?,
                                provider: String, now: Date = Date()) -> PRError {
        if code == 429 || retryAfter != nil || (code == 403 && remaining == "0") {
            var wait = retryAfter.flatMap(TimeInterval.init)
            if wait == nil, let r = reset.flatMap(TimeInterval.init) { wait = max(0, r - now.timeIntervalSince1970) }
            return .rateLimited(wait, "\(provider) 요청 한도 초과 — 잠시 후 다시 시도")
        }
        return code == 401 || code == 403 ? .unauthorized : .http(code)
    }

    static func classify(_ resp: HTTPURLResponse?, provider: String) -> PRError {
        classify(code: resp?.statusCode ?? 0, remaining: resp?.value(forHTTPHeaderField: "x-ratelimit-remaining"),
                 retryAfter: resp?.value(forHTTPHeaderField: "retry-after"),
                 reset: resp?.value(forHTTPHeaderField: "x-ratelimit-reset"), provider: provider)
    }

    public var userMessage: String {
        switch self {
        case .unauthorized: return "인증 실패 (401/403)"
        case .rateLimited(_, let m): return m
        case .http(let c): return "HTTP \(c)"
        case .network(let m): return "네트워크: \(m)"
        case .decode(let m): return "응답 해석 실패: \(m)"
        case .message(let m): return m
        }
    }
}

/// gh CLI 위치 찾기와 토큰 읽기. 토큰은 메모리에서만 쓰고 로그·저장하지 않는다.
public enum GhCLI {
    /// 로그인 셸에서 `command -v gh`. GUI 앱은 셸 PATH 를 못 받는다.
    public static func loginShellLookup() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let r = ProcessRunner.run(executable: shell, arguments: ["-lc", "command -v gh"], timeout: 5)
        guard !r.timedOut, r.status == 0 else { return nil }
        return r.stdout.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
    }

    public static func locate(shellLookup: () -> String? = GhCLI.loginShellLookup) -> String? {
        func isExe(_ p: String) -> Bool { FileManager.default.isExecutableFile(atPath: p) }
        if let p = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first(where: isExe) { return p }
        if let p = shellLookup(), p.hasPrefix("/"), isExe(p) { return p }
        return nil
    }

    /// `gh auth token`. 로그인이 안 돼 있거나 비어 있으면 nil.
    public static func token(path: String) -> String? {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env["GH_PROMPT_DISABLED"] = "1"
        let r = ProcessRunner.run(executable: path, arguments: ["auth", "token"], environment: env, timeout: 10)
        guard !r.timedOut, r.status == 0 else { return nil }
        let t = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

public struct GitHubClient: Sendable {
    public let token: String
    let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    static let fields = """
    number title url isDraft createdAt updatedAt additions deletions changedFiles headRefName baseRefName \
    repository { nameWithOwner name } author { login } comments { totalCount } \
    commits(last: 1) { nodes { commit { committedDate } } } \
    reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } ... on Team { name } } } } \
    latestOpinionatedReviews(first: 20) { nodes { author { login } state submittedAt } }
    """

    static func search(_ q: String) -> String {
        "search(query: \"\(q)\", type: ISSUE, first: 50) { nodes { ... on PullRequest { \(fields) } } }"
    }

    public static let query = """
    query { viewer { login } \
    requested: \(search("is:pr is:open review-requested:@me archived:false")) \
    reviewed: \(search("is:pr is:open reviewed-by:@me -author:@me archived:false")) \
    mine: \(search("is:pr is:open author:@me archived:false")) }
    """

    public struct Fetched: Equatable, Sendable {
        public let login: String
        public let reviewRequests: [PullRequest]
        public let mine: [PullRequest]
    }

    public func fetch() async throws -> Fetched {
        let data = try await post(Self.query)
        let login = try Self.viewerLogin(data)
        let r = try Self.decode(data, me: login)
        return Fetched(login: login, reviewRequests: r.reviewRequests, mine: r.mine)
    }

    /// 토큰이 통하는지와 로그인 이름만 확인.
    public func fetchLogin() async throws -> String {
        try Self.viewerLogin(try await post("query { viewer { login } }"))
    }

    private func post(_ query: String) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ATM", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { throw PRError.network(error.localizedDescription) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else { throw PRError.classify(resp as? HTTPURLResponse, provider: "GitHub") }
        return data
    }

    // MARK: - 해석 (순수)

    struct Envelope: Decodable {
        struct Login: Decodable { let login: String }
        struct Search: Decodable { let nodes: [Node?]? }
        struct Node: Decodable {
            struct Repo: Decodable { let nameWithOwner: String; let name: String }
            struct Author: Decodable { let login: String? }
            struct Count: Decodable { let totalCount: Int }
            struct Commits: Decodable {
                struct N: Decodable { struct C: Decodable { let committedDate: String? }; let commit: C? }
                let nodes: [N?]?
            }
            struct Requests: Decodable {
                struct N: Decodable {
                    struct R: Decodable { let login: String?; let name: String? }
                    let requestedReviewer: R?
                }
                let nodes: [N?]?
            }
            struct Reviews: Decodable {
                struct N: Decodable { let author: Author?; let state: String; let submittedAt: String? }
                let nodes: [N?]?
            }
            let number: Int?
            let title: String?
            let url: String?
            let isDraft: Bool?
            let createdAt: String?
            let updatedAt: String?
            let additions: Int?
            let deletions: Int?
            let changedFiles: Int?
            let headRefName: String?
            let baseRefName: String?
            let repository: Repo?
            let author: Author?
            let comments: Count?
            let commits: Commits?
            let reviewRequests: Requests?
            let latestOpinionatedReviews: Reviews?
        }
        struct DataBox: Decodable {
            let viewer: Login?
            let requested: Search?
            let reviewed: Search?
            let mine: Search?
        }
        struct GQLError: Decodable { let message: String }
        let data: DataBox?
        let errors: [GQLError]?
    }

    static func viewerLogin(_ data: Data) throws -> String {
        let e = try envelope(data)
        guard let l = e.data?.viewer?.login else { throw PRError.decode("viewer 없음") }
        return l
    }

    static func envelope(_ data: Data) throws -> Envelope {
        let e: Envelope
        do { e = try JSONDecoder().decode(Envelope.self, from: data) } catch { throw PRError.decode("\(error)") }
        if e.data == nil, let m = e.errors?.first?.message { throw PRError.message(m) }
        return e
    }

    /// 리뷰 요청 = (나에게 요청됨 ∪ 내가 리뷰함) 중복 제거. 내 PR 은 따로.
    public static func decode(_ data: Data, me: String) throws -> (reviewRequests: [PullRequest], mine: [PullRequest]) {
        let e = try envelope(data)
        func prs(_ s: Envelope.Search?, requested: Bool) -> [PullRequest] {
            (s?.nodes ?? []).compactMap { $0 }.compactMap { pr($0, me: me) }.map { var p = $0; p.reviewRequested = requested; return p }
        }
        // 요청된 것을 먼저 두어, 양쪽에 다 나오면 requested 쪽이 남는다.
        var seen = Set<String>()
        let rr = (prs(e.data?.requested, requested: true) + prs(e.data?.reviewed, requested: false)).filter { seen.insert($0.id).inserted }
        return (rr, prs(e.data?.mine, requested: true))
    }

    static func pr(_ n: Envelope.Node, me: String) -> PullRequest? {
        guard let number = n.number, let url = n.url, let repo = n.repository,
              let created = PRLogic.parseDate(n.createdAt) else { return nil }
        var reviewers: [PRReviewer] = []
        var myReviewAt: Date?
        for r in (n.latestOpinionatedReviews?.nodes ?? []).compactMap({ $0 }) {
            let name = r.author?.login ?? "(알 수 없음)"
            let state: ReviewState
            switch r.state {
            case "APPROVED": state = .approved
            case "CHANGES_REQUESTED": state = .changesRequested
            case "COMMENTED": state = .commented
            default: continue
            }
            let at = PRLogic.parseDate(r.submittedAt)
            reviewers.append(PRReviewer(name: name, state: state, at: at))
            if name == me, let at { myReviewAt = max(myReviewAt ?? at, at) }
        }
        for r in (n.reviewRequests?.nodes ?? []).compactMap({ $0 }) {
            guard let name = r.requestedReviewer?.login ?? r.requestedReviewer?.name,
                  !reviewers.contains(where: { $0.name == name }) else { continue }
            reviewers.append(PRReviewer(name: name, state: .pending, at: nil))
        }
        let commit = n.commits?.nodes?.compactMap { $0 }.last?.commit?.committedDate
        return PullRequest(
            id: "github:\(repo.nameWithOwner)#\(number)", provider: .github, repo: repo.name, number: number,
            title: n.title ?? "", url: url, author: n.author?.login ?? "(알 수 없음)", isDraft: n.isDraft ?? false,
            createdAt: created, updatedAt: PRLogic.parseDate(n.updatedAt) ?? created,
            lastCommitAt: PRLogic.parseDate(commit),
            sourceBranch: n.headRefName ?? "", targetBranch: n.baseRefName ?? "",
            additions: n.additions, deletions: n.deletions, changedFiles: n.changedFiles,
            reviewers: reviewers, commentCount: n.comments?.totalCount, myReviewAt: myReviewAt)
    }
}
