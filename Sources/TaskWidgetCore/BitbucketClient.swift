import Foundation

public enum BitbucketSecrets {
    /// 키체인 service. account 는 이메일.
    public static let service = "com.lsm0506.TaskWidget.bitbucket"
}

public struct BBUser: Equatable, Sendable {
    public let uuid: String
    public let displayName: String
    public let accountId: String?
}
public struct BBWorkspace: Equatable, Identifiable, Sendable {
    public let slug: String
    public let name: String
    public var id: String { slug }
}
public struct BBRepo: Equatable, Identifiable, Sendable {
    public let slug: String
    public let name: String
    public let updatedOn: Date?
    public var id: String { slug }
}

/// Bitbucket Cloud REST 2.0. 아직 실제 계정으로 검증하지 못했다 (엔드포인트는 `Endpoint` 한 곳에 모아 둔다).
/// 실패하면 HTTP 상태와 경로만 app.log 에 남긴다 (헤더·토큰은 남기지 않는다).
public struct BitbucketClient: Sendable {
    public let email: String
    let token: String
    let session: URLSession

    public init(email: String, token: String, session: URLSession = .shared) {
        self.email = email
        self.token = token
        self.session = session
    }

    // MARK: - 엔드포인트 (한 곳)

    enum Endpoint {
        static let base = "https://api.bitbucket.org/2.0"
        static let participantFields = "+values.participants,+values.reviewers"
        static let user = "/user"
        static let workspaces = "/user/workspaces"
        /// 위가 안 되는 계정을 위한 예전 경로
        static let workspacesLegacy = "/user/permissions/workspaces"
        static func mine(_ ws: String, _ uuid: String) -> String { "/workspaces/\(ws)/pullrequests/\(uuid)" }
        static func repoPRs(_ ws: String, _ slug: String) -> String { "/repositories/\(ws)/\(slug)/pullrequests" }
        static func repos(_ ws: String) -> String { "/repositories/\(ws)" }
        static func approve(_ ws: String, _ slug: String, _ id: Int) -> String { "/repositories/\(ws)/\(slug)/pullrequests/\(id)/approve" }
        static func comments(_ ws: String, _ slug: String, _ id: Int) -> String { "/repositories/\(ws)/\(slug)/pullrequests/\(id)/comments" }
    }

    static func url(_ path: String, _ items: [URLQueryItem] = []) -> URL? {
        guard var c = URLComponents(string: Endpoint.base) else { return nil }
        c.path += path   // 중괄호 uuid 는 URLComponents 가 퍼센트 인코딩한다
        if !items.isEmpty {
            c.queryItems = items
            // URLComponents 는 '+' 를 인코딩하지 않아 서버가 공백으로 읽는다 (fields=+values… 보호)
            c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        return c.url
    }

    // MARK: - 호출

    public func me() async throws -> BBUser {
        try Self.decodeUser(try await get(Self.url(Endpoint.user)!))
    }

    public func workspaces() async throws -> [BBWorkspace] {
        do { return try await workspaces(at: Endpoint.workspaces) }
        catch let e as PRError {
            if case .rateLimited = e { throw e }
            if case .network = e { throw e }
            return try await workspaces(at: Endpoint.workspacesLegacy)
        }
    }

    private func workspaces(at path: String) async throws -> [BBWorkspace] {
        var out: [BBWorkspace] = []
        var next: URL? = Self.url(path, [.init(name: "pagelen", value: "100")])
        var pages = 0
        while let u = next, pages < 10 {
            let (ws, n) = try Self.decodeWorkspaces(try await get(u))
            out += ws
            next = n.flatMap(Self.safeNext)
            pages += 1
        }
        return out
    }

    /// next 는 서버가 준 주소라도 https 의 api.bitbucket.org 일 때만 따라간다 (토큰이 다른 곳으로 나가지 않게).
    static func safeNext(_ s: String) -> URL? {
        guard let u = URL(string: s), u.scheme == "https", u.host?.lowercased() == "api.bitbucket.org" else { return nil }
        return u
    }

    private func prQuery(_ q: String?, extra: [URLQueryItem] = []) -> [URLQueryItem] {
        var items: [URLQueryItem] = [.init(name: "pagelen", value: "50"), .init(name: "fields", value: Endpoint.participantFields)]
        if let q { items.append(.init(name: "q", value: q)) }
        return items + extra
    }

    /// 내가 올린 열린 PR. 워크스페이스 단위 경로가 404 면 선택한 저장소별 조회로 대신한다 (usedFallback = true).
    /// skipWorkspaceEndpoint: 이전에 404 였던 워크스페이스는 처음부터 대체 경로로 간다.
    public func mine(workspace: String, uuid: String, repos: [String], skipWorkspaceEndpoint: Bool = false)
        async throws -> (prs: [PullRequest], usedFallback: Bool) {
        if !skipWorkspaceEndpoint {
            let items = prQuery(nil, extra: [.init(name: "state", value: "OPEN")])
            do {
                let data = try await get(Self.url(Endpoint.mine(workspace, uuid), items)!)
                return (try Self.decodePullRequests(data, me: uuid).prs, false)
            } catch PRError.http(404) {}
        }
        let q = "author.uuid=\"\(uuid)\" AND state=\"OPEN\""
        let me = self
        // 인증·한도 오류는 삼키지 않고 위로 올린다. 그 밖의 저장소별 실패만 건너뛴다.
        let results = await Self.mapConcurrent(repos, limit: 6) { slug -> Result<[PullRequest], PRError> in
            do {
                let data = try await me.get(Self.url(Endpoint.repoPRs(workspace, slug), me.prQuery(q))!)
                return .success(try Self.decodePullRequests(data, me: uuid).prs)
            } catch let e as PRError { return .failure(e) } catch { return .failure(.network(error.localizedDescription)) }
        }
        var prs: [PullRequest] = []
        for r in results {
            switch r {
            case .success(let p): prs += p
            case .failure(.unauthorized): throw PRError.unauthorized
            case .failure(.rateLimited(let a, let m)): throw PRError.rateLimited(a, m)
            case .failure: continue
            }
        }
        return (prs, true)
    }

    /// 선택한 저장소들에서 내가 리뷰어로 지정된 열린 PR. 일반 실패는 저장소별로 모아 돌려주고(failed = 못 읽은 slug),
    /// 인증 실패·한도 초과는 전체 오류로 던진다. 404(삭제·이름 변경·권한 회수)는 gone 으로 따로 돌려준다.
    public func reviewRequests(workspace: String, repos: [String], uuid: String) async throws
        -> (prs: [PullRequest], errors: [String], failed: Set<String>, gone: Set<String>) {
        let q = "state=\"OPEN\" AND reviewers.uuid=\"\(uuid)\""
        let me = self
        let results = await Self.mapConcurrent(repos, limit: 6) { slug -> (slug: String, prs: [PullRequest], error: PRError?) in
            do {
                let data = try await me.get(Self.url(Endpoint.repoPRs(workspace, slug), me.prQuery(q))!)
                return (slug, try Self.decodePullRequests(data, me: uuid).prs, nil)
            } catch let e as PRError { return (slug, [], e) } catch { return (slug, [], .network(error.localizedDescription)) }
        }
        var prs: [PullRequest] = [], errors: [String] = [], failed = Set<String>(), gone = Set<String>()
        for r in results {
            switch r.error {
            case nil: prs += r.prs
            case .some(.unauthorized): throw PRError.unauthorized
            case .some(.rateLimited(let a, let m)): throw PRError.rateLimited(a, m)
            case .some(.http(404)): gone.insert(r.slug)   // 사라진 저장소는 이전 목록을 남기지 않는다
            case .some(let e): errors.append("\(r.slug): \(e.userMessage)"); failed.insert(r.slug)
            }
        }
        return (prs, errors, failed, gone)
    }

    /// 내 PR 의 최근 댓글 20개 중 내가 쓰지 않은 것. comment_count 가 늘었을 때만 부른다.
    public func recentComments(workspace: String, slug: String, id: Int, me: String) async throws -> [PRActivity] {
        let items: [URLQueryItem] = [.init(name: "sort", value: "-created_on"), .init(name: "pagelen", value: "20")]
        return try Self.decodeComments(try await get(Self.url(Endpoint.comments(workspace, slug, id), items)!), me: me)
    }

    public func repositories(workspace: String) async throws -> [BBRepo] {
        var out: [BBRepo] = []
        // role=member 는 직접 멤버로 추가된 저장소만 준다. 그룹·프로젝트 권한으로 보이는 저장소까지 받으려면 빼야 한다.
        var next: URL? = Self.url(Endpoint.repos(workspace), [
            .init(name: "pagelen", value: "100"), .init(name: "sort", value: "-updated_on"),
            .init(name: "fields", value: "values.slug,values.name,values.updated_on,next"),
        ])
        var pages = 0
        while let u = next, pages < 10 {
            let (repos, n) = try Self.decodeRepositories(try await get(u))
            out += repos
            next = n.flatMap(Self.safeNext)
            pages += 1
        }
        return out
    }

    /// since 이후 갱신된 PR 중 내가 리뷰어였던 것이 있는 저장소. progress(끝낸 수, 전체).
    public func recentReviewedRepos(workspace: String, slugs: [String], uuid: String, since: Date,
                                    progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async -> [String] {
        let iso = ISO8601DateFormatter().string(from: since)
        let q = "reviewers.uuid=\"\(uuid)\" AND updated_on>\(iso)"
        let counter = Counter()
        let me = self
        let results = await Self.mapConcurrent(slugs, limit: 6) { slug -> String? in
            let items: [URLQueryItem] = [.init(name: "pagelen", value: "1"), .init(name: "q", value: q),
                .init(name: "state", value: "OPEN"), .init(name: "state", value: "MERGED"), .init(name: "state", value: "DECLINED"),
                .init(name: "fields", value: "values.id")]
            var hit = false
            if let data = try? await me.get(Self.url(Endpoint.repoPRs(workspace, slug), items)!) { hit = (try? Self.hasValues(data)) ?? false }
            progress(counter.increment(), slugs.count)
            return hit ? slug : nil
        }
        return results.compactMap { $0 }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func increment() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    }

    // MARK: - 네트워크

    /// 승인(POST)·승인 취소(DELETE) 요청을 만들기만 한다.
    func approveRequest(workspace: String, slug: String, id: Int, undo: Bool) -> URLRequest {
        var req = URLRequest(url: Self.url(Endpoint.approve(workspace, slug, id))!)
        req.httpMethod = undo ? "DELETE" : "POST"
        req.timeoutInterval = 20
        req.setValue("Basic " + Data("\(email):\(token)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    /// 사용자가 확인 팝오버에서 누른 경우에만 부른다. 401/403 은 토큰에 쓰기 권한이 없다는 뜻(noWritePermission).
    public func approve(workspace: String, slug: String, id: Int) async throws { try await write(workspace, slug, id, undo: false) }
    public func unapprove(workspace: String, slug: String, id: Int) async throws { try await write(workspace, slug, id, undo: true) }

    private func write(_ ws: String, _ slug: String, _ id: Int, undo: Bool) async throws {
        let req = approveRequest(workspace: ws, slug: slug, id: id, undo: undo)
        let resp: URLResponse
        do { (_, resp) = try await session.data(for: req) } catch { throw PRError.network(error.localizedDescription) }
        let http = resp as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        DiagLog.append("bitbucket \(req.httpMethod ?? "") \(req.url?.path ?? "") -> HTTP \(code)")
        guard (200...299).contains(code) else { throw PRError.bitbucketWriteError(code: code, retryAfter: http?.value(forHTTPHeaderField: "retry-after")) }
    }

    func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("Basic " + Data("\(email):\(token)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch {
            if (error as? URLError)?.code != .cancelled { DiagLog.append("bitbucket GET \(url.path) network error: \((error as? URLError)?.code.rawValue ?? 0)") }
            throw PRError.network(error.localizedDescription)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            DiagLog.append("bitbucket GET \(url.path) -> HTTP \(code)")
            throw PRError.classify(resp as? HTTPURLResponse, provider: "Bitbucket")
        }
        return data
    }

    /// 동시에 limit 개까지만 돌린다. 결과는 입력 순서.
    static func mapConcurrent<T: Sendable, R: Sendable>(_ items: [T], limit: Int, _ f: @escaping @Sendable (T) async -> R) async -> [R] {
        await withTaskGroup(of: (Int, R).self) { group in
            var results = [R?](repeating: nil, count: items.count)
            var next = 0
            func add() {
                guard next < items.count else { return }
                let i = next, item = items[i]
                next += 1
                group.addTask { (i, await f(item)) }
            }
            for _ in 0..<min(limit, items.count) { add() }
            while let (i, r) = await group.next() {
                results[i] = r
                add()
            }
            return results.compactMap { $0 }
        }
    }

    // MARK: - 해석 (순수)

    struct UserDTO: Decodable { let uuid: String?; let display_name: String?; let account_id: String? }

    static func decodeUser(_ data: Data) throws -> BBUser {
        let u: UserDTO
        do { u = try JSONDecoder().decode(UserDTO.self, from: data) } catch { throw PRError.decode("\(error)") }
        guard let uuid = u.uuid else { throw PRError.decode("uuid 없음") }
        return BBUser(uuid: uuid, displayName: u.display_name ?? "", accountId: u.account_id)
    }

    /// `/user/workspaces` ({slug, name}) 와 예전 `/user/permissions/workspaces` ({workspace: {slug, name}}) 둘 다 읽는다.
    static func decodeWorkspaces(_ data: Data) throws -> (workspaces: [BBWorkspace], next: String?) {
        struct W: Decodable { let slug: String?; let name: String? }
        struct V: Decodable { let slug: String?; let name: String?; let workspace: W? }
        struct R: Decodable { let values: [V]; let next: String? }
        do {
            let r = try JSONDecoder().decode(R.self, from: data)
            let ws = r.values.compactMap { v -> BBWorkspace? in
                guard let slug = v.workspace?.slug ?? v.slug else { return nil }
                return BBWorkspace(slug: slug, name: v.workspace?.name ?? v.name ?? slug)
            }
            return (ws, r.next)
        } catch { throw PRError.decode("\(error)") }
    }

    static func decodeRepositories(_ data: Data) throws -> (repos: [BBRepo], next: String?) {
        struct R: Decodable { struct V: Decodable { let slug: String; let name: String?; let updated_on: String? }; let values: [V]; let next: String? }
        do {
            let r = try JSONDecoder().decode(R.self, from: data)
            return (r.values.map { BBRepo(slug: $0.slug, name: $0.name ?? $0.slug, updatedOn: PRLogic.parseDate($0.updated_on)) }, r.next)
        } catch { throw PRError.decode("\(error)") }
    }

    static func decodeComments(_ data: Data, me: String) throws -> [PRActivity] {
        struct U: Decodable { let uuid: String?; let display_name: String?; let nickname: String? }
        struct C: Decodable { let id: Int; let user: U?; let deleted: Bool? }
        struct R: Decodable { let values: [C] }
        do {
            return try JSONDecoder().decode(R.self, from: data).values.compactMap { c in
                guard c.deleted != true, c.user?.uuid != me else { return nil }
                return PRActivity(id: "bb:\(c.id)", author: c.user?.display_name ?? c.user?.nickname ?? "(알 수 없음)")
            }
        } catch { throw PRError.decode("\(error)") }
    }

    static func hasValues(_ data: Data) throws -> Bool {
        struct Empty: Decodable {}
        struct R: Decodable { let values: [Empty] }
        do { return !(try JSONDecoder().decode(R.self, from: data).values.isEmpty) } catch { throw PRError.decode("\(error)") }
    }

    struct PRPage: Decodable {
        struct Person: Decodable { let uuid: String?; let display_name: String?; let nickname: String? }
        struct Participant: Decodable {
            let user: Person?; let role: String?; let approved: Bool?; let state: String?; let participated_on: String?
        }
        struct Branch: Decodable {
            struct B: Decodable { let name: String? }
            struct R: Decodable { let full_name: String?; let name: String? }
            let branch: B?; let repository: R?
        }
        struct Links: Decodable { struct H: Decodable { let href: String? }; let html: H? }
        struct PR: Decodable {
            let id: Int
            let title: String?
            let draft: Bool?
            let comment_count: Int?
            let created_on: String?
            let updated_on: String?
            let author: Person?
            let source: Branch?
            let destination: Branch?
            let links: Links?
            let participants: [Participant]?
            let reviewers: [Person]?
        }
        let values: [PR]
        let next: String?
    }

    /// participants 의 REVIEWER + reviewers 중 아직 아무 반응 없는 사람(대기).
    /// 내 반응 시각(myReviewAt)은 내가 승인/변경 요청을 했을 때의 participated_on.
    static func decodePullRequests(_ data: Data, me: String) throws -> (prs: [PullRequest], next: String?) {
        let page: PRPage
        do { page = try JSONDecoder().decode(PRPage.self, from: data) } catch { throw PRError.decode("\(error)") }
        let prs = page.values.compactMap { v -> PullRequest? in
            guard let created = PRLogic.parseDate(v.created_on), let dest = v.destination?.repository?.full_name else { return nil }
            var reviewers: [PRReviewer] = []
            var myReviewAt: Date?
            var reacted = Set<String>()
            for p in v.participants ?? [] where p.role == "REVIEWER" {
                let name = p.user?.display_name ?? p.user?.nickname ?? "(알 수 없음)"
                let at = PRLogic.parseDate(p.participated_on)
                let state: ReviewState = p.state == "changes_requested" ? .changesRequested : (p.approved == true ? .approved : .pending)
                reviewers.append(PRReviewer(name: name, state: state, at: state == .pending ? nil : at))
                if let u = p.user?.uuid { reacted.insert(u) }
                if p.user?.uuid == me, state != .pending, let at { myReviewAt = at }
            }
            for r in v.reviewers ?? [] where !(r.uuid.map(reacted.contains) ?? false) {
                reviewers.append(PRReviewer(name: r.display_name ?? r.nickname ?? "(알 수 없음)", state: .pending))
            }
            let slug = dest.split(separator: "/").last.map(String.init) ?? dest
            return PullRequest(
                id: "bitbucket:\(dest)#\(v.id)", provider: .bitbucket, repo: v.destination?.repository?.name ?? slug, number: v.id,
                title: v.title ?? "", url: v.links?.html?.href ?? "https://bitbucket.org/\(dest)/pull-requests/\(v.id)",
                author: v.author?.display_name ?? v.author?.nickname ?? "(알 수 없음)", isDraft: v.draft ?? false,
                createdAt: created, updatedAt: PRLogic.parseDate(v.updated_on) ?? created, lastCommitAt: nil,
                sourceBranch: v.source?.branch?.name ?? "", targetBranch: v.destination?.branch?.name ?? "",
                reviewers: reviewers, commentCount: v.comment_count, myReviewAt: myReviewAt)
        }
        return (prs, page.next)
    }
}
