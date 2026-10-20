import Foundation

public enum PRProvider: String, Codable, Sendable { case github, bitbucket }
public enum ReviewState: String, Codable, Sendable { case approved, changesRequested, pending, commented }

public struct PRReviewer: Codable, Equatable, Sendable {
    public var name: String
    public var state: ReviewState
    public var at: Date?
    public init(name: String, state: ReviewState, at: Date? = nil) {
        self.name = name; self.state = state; self.at = at
    }
}

/// 내 PR 에 다른 사람이 남긴 댓글·리뷰 한 건 (id 는 제공자 안에서 유일).
public struct PRActivity: Codable, Equatable, Sendable {
    public var id: String
    public var author: String
    public init(id: String, author: String) { self.id = id; self.author = author }
}

public struct PullRequest: Codable, Identifiable, Equatable, Sendable {
    /// "github:owner/repo#12" / "bitbucket:ws/slug#34"
    public var id: String
    public var provider: PRProvider
    /// 화면에 보이는 짧은 저장소 이름 (예: "task-widget")
    public var repo: String
    public var number: Int
    public var title: String
    public var url: String
    public var author: String
    public var isDraft: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var lastCommitAt: Date?
    public var sourceBranch: String
    public var targetBranch: String
    /// 모르면 nil (Bitbucket 목록은 주지 않는다)
    public var additions: Int?
    public var deletions: Int?
    public var changedFiles: Int?
    public var reviewers: [PRReviewer]
    public var commentCount: Int?
    /// 내가 마지막으로 리뷰·승인한 시각 ("리뷰함 · 새 커밋" 판단용)
    public var myReviewAt: Date?
    /// 나한테 리뷰가 요청된 PR 인가. GitHub 의 "내가 리뷰함" 검색에서만 나온 PR 은 false (알림·배지에서 제외).
    public var reviewRequested: Bool
    /// 내 PR 에 다른 사람이 최근 남긴 댓글·COMMENTED 리뷰 (내가 쓴 것 제외). 모르면 빈 배열.
    public var recentActivity: [PRActivity]

    public init(id: String, provider: PRProvider, repo: String, number: Int, title: String, url: String,
                author: String, isDraft: Bool = false, createdAt: Date, updatedAt: Date, lastCommitAt: Date? = nil,
                sourceBranch: String = "", targetBranch: String = "",
                additions: Int? = nil, deletions: Int? = nil, changedFiles: Int? = nil,
                reviewers: [PRReviewer] = [], commentCount: Int? = nil, myReviewAt: Date? = nil,
                reviewRequested: Bool = true, recentActivity: [PRActivity] = []) {
        self.id = id; self.provider = provider; self.repo = repo; self.number = number; self.title = title; self.url = url
        self.author = author; self.isDraft = isDraft; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.lastCommitAt = lastCommitAt; self.sourceBranch = sourceBranch; self.targetBranch = targetBranch
        self.additions = additions; self.deletions = deletions; self.changedFiles = changedFiles
        self.reviewers = reviewers; self.commentCount = commentCount; self.myReviewAt = myReviewAt
        self.reviewRequested = reviewRequested
        self.recentActivity = recentActivity
    }
}

public enum PRApproval: Equatable, Sendable {
    case approved(Int, Int), changesRequested, waiting(Int, Int), noReviewers
}

/// 내 PR 하나의 직전 상태 (알림 비교용).
public struct PRMineState: Codable, Equatable, Sendable {
    public var approvers: Set<String>
    public var changers: Set<String>
    /// 이미 본 댓글·리뷰 id (최근 것부터, 최대 50)
    public var activity: [String]
    public var commentCount: Int?
    public init(approvers: Set<String> = [], changers: Set<String> = [], activity: [String] = [], commentCount: Int? = nil) {
        self.approvers = approvers; self.changers = changers; self.activity = activity; self.commentCount = commentCount
    }
}

/// 알림 판단에 쓰는 직전 목록의 요약. 전체 PR 을 저장하지 않는다.
public struct PRSnapshot: Codable, Equatable, Sendable {
    /// 나한테 요청된 PR 만
    public var reviewRequestIDs: Set<String>
    public var mine: [String: PRMineState]
    /// 이미 한 번 성공적으로 받아 본 제공자 ("github"/"bitbucket"). 처음 켠 제공자는 알림 없이 기준만 잡는다.
    public var providers: Set<String>
    public init(reviewRequestIDs: Set<String> = [], mine: [String: PRMineState] = [:], providers: Set<String> = []) {
        self.reviewRequestIDs = reviewRequestIDs; self.mine = mine; self.providers = providers
    }
}

public enum PRNotice: Equatable, Sendable {
    case newReviewRequest(PullRequest)
    /// 승인한 사람 한 명. count/total = 이 승인까지 반영한 승인 수 / 리뷰어 수. complete = 이 승인으로 모두 승인됨.
    case approved(PullRequest, by: String, count: Int, total: Int, complete: Bool)
    case changesRequested(PullRequest, by: String)
    /// 새 댓글·리뷰. authors 는 중복 없이 등장 순서, count 는 새 건수.
    case comments(PullRequest, authors: [String], count: Int)

    public var pr: PullRequest {
        switch self {
        case .newReviewRequest(let p), .approved(let p, _, _, _, _), .changesRequested(let p, _), .comments(let p, _, _): return p
        }
    }

    public var title: String {
        switch self {
        case .newReviewRequest: return "리뷰 요청"
        case .approved(_, _, let n, let m, let done): return done ? "PR 승인 완료 · 머지할 수 있어요" : "PR 승인 (\(n)/\(m))"
        case .changesRequested: return "PR 변경 요청"
        case .comments: return "PR 새 댓글·리뷰"
        }
    }

    public var body: String {
        let tail = "\(pr.repo) · \(pr.title)"
        switch self {
        case .newReviewRequest: return tail
        case .approved(_, let by, _, _, _): return "\(by) 님이 승인 · \(tail)"
        case .changesRequested(_, let by): return "\(by) 님이 변경 요청 · \(tail)"
        case .comments(_, let authors, let count):
            let first = authors.first ?? "(알 수 없음)"
            if authors.count > 1 { return "\(first) 외 \(authors.count - 1)명 · 댓글 \(count)개 · \(tail)" }
            return count > 1 ? "\(first) 님이 댓글 \(count)개 · \(tail)" : "\(first) 님이 댓글 · \(tail)"
        }
    }
}

public enum PRLogic {
    public static func approval(_ pr: PullRequest) -> PRApproval {
        if pr.reviewers.contains(where: { $0.state == .changesRequested }) { return .changesRequested }
        let m = pr.reviewers.count
        if m == 0 { return .noReviewers }
        let n = pr.reviewers.filter { $0.state == .approved }.count
        return n == m ? .approved(n, m) : .waiting(n, m)
    }

    /// 내가 리뷰한 뒤 커밋이 더 올라왔는가.
    public static func hasNewCommitsSinceMyReview(_ pr: PullRequest) -> Bool {
        guard let mine = pr.myReviewAt, let last = pr.lastCommitAt else { return false }
        return last > mine
    }

    /// 아직 리뷰 안 한 것 먼저, 그 안에서는 오래된 것부터.
    public static func sortReviewRequests(_ prs: [PullRequest]) -> [PullRequest] {
        prs.sorted {
            let a = $0.myReviewAt != nil, b = $1.myReviewAt != nil
            if a != b { return !a }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }

    private static func rank(_ pr: PullRequest) -> Int {
        switch approval(pr) {
        case .changesRequested: return 0
        case .approved: return 1
        case .waiting, .noReviewers: return 2
        }
    }

    /// 변경 요청 → 승인 → 대기 순, 같으면 최근 갱신 먼저.
    public static func sortMine(_ prs: [PullRequest]) -> [PullRequest] {
        prs.sorted {
            let a = rank($0), b = rank($1)
            if a != b { return a < b }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public static func isStale(_ pr: PullRequest, now: Date, days: Int) -> Bool {
        now.timeIntervalSince(pr.createdAt) >= Double(days) * 86400
    }

    /// "N일째 대기" 에 쓰는 일수 (올린 지 지난 날).
    public static func waitDays(_ pr: PullRequest, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(pr.createdAt) / 86400))
    }

    public static func relative(_ date: Date, now: Date) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 3600 { return "\(max(1, Int(s / 60)))분 전" }
        if s < 86400 { return "\(Int(s / 3600))시간 전" }
        return "\(Int(s / 86400))일 전"
    }

    /// id 앞의 제공자 ("github:o/r#1" → .github).
    public static func provider(of id: String) -> PRProvider? {
        PRProvider(rawValue: String(id.prefix(while: { $0 != ":" })))
    }

    /// "github:owner/repo#12" → (owner, repo, 12)
    public static func githubParts(_ id: String) -> (owner: String, repo: String, number: Int)? {
        guard let (path, n) = idParts(id, prefix: "github:") else { return nil }
        let p = path.split(separator: "/").map(String.init)
        return p.count == 2 ? (p[0], p[1], n) : nil
    }

    /// "bitbucket:ws/slug#34" → (ws, slug, 34)
    public static func bitbucketParts(_ id: String) -> (workspace: String, slug: String, number: Int)? {
        guard let (path, n) = idParts(id, prefix: "bitbucket:") else { return nil }
        let p = path.split(separator: "/").map(String.init)
        return p.count == 2 ? (p[0], p[1], n) : nil
    }

    private static func idParts(_ id: String, prefix: String) -> (String, Int)? {
        guard id.hasPrefix(prefix), let hash = id.lastIndex(of: "#"),
              let n = Int(id[id.index(after: hash)...]) else { return nil }
        return (String(id[id.index(id.startIndex, offsetBy: prefix.count)..<hash]), n)
    }

    /// 내가(me) 이 PR 을 승인했는가.
    public static func approvedBy(_ pr: PullRequest, me: String?) -> Bool {
        guard let me else { return false }
        return pr.reviewers.contains { $0.name == me && $0.state == .approved }
    }

    /// 승인 직후 화면에 바로 반영하려고 내 승인을 로컬 PR 에 적는다 (다음 새로고침이 실제 값으로 덮어쓴다).
    public static func markApproved(_ pr: PullRequest, by me: String, at: Date) -> PullRequest {
        var p = pr
        if let i = p.reviewers.firstIndex(where: { $0.name == me }) { p.reviewers[i].state = .approved; p.reviewers[i].at = at }
        else { p.reviewers.append(PRReviewer(name: me, state: .approved, at: at)) }
        p.myReviewAt = at
        return p
    }

    /// 승인 취소: 내 리뷰어 상태를 대기로 되돌린다.
    public static func markUnapproved(_ pr: PullRequest, by me: String) -> PullRequest {
        var p = pr
        if let i = p.reviewers.firstIndex(where: { $0.name == me }) { p.reviewers[i].state = .pending; p.reviewers[i].at = nil }
        p.myReviewAt = nil
        return p
    }

    /// "github:o/r#1" → "github:o/r" (저장소 숨김의 키)
    public static func repoKey(_ id: String) -> String {
        String(id.prefix(while: { $0 != "#" }))
    }

    /// 리뷰 요청 필터의 한 가지 값 (상태·저장소·사람)과 그 값의 PR 개수.
    public struct Facet: Equatable, Sendable {
        public var key: String
        public var label: String
        /// 저장소 값만. 같은 이름 저장소를 구분하는 표시에 쓴다.
        public var provider: PRProvider?
        public var count: Int
    }
    public enum FacetKind: Sendable { case status, repo, author }

    /// 내 리뷰 진행 상태. 칩에는 짧은 이름(short), 팝오버에는 label 을 쓴다.
    public enum ReviewStatus: String, CaseIterable, Sendable {
        case unreviewed, newCommits, reviewed
        public var label: String {
            switch self {
            case .unreviewed: return "아직 리뷰 안 함"
            case .newCommits: return "리뷰함 · 새 커밋"
            case .reviewed: return "리뷰함"
            }
        }
        public var short: String {
            switch self {
            case .unreviewed: return "안 함"
            case .newCommits: return "새 커밋"
            case .reviewed: return "리뷰함"
            }
        }
    }

    /// Bitbucket 은 lastCommitAt 이 없을 수 있어 새 커밋을 못 알아채고 "리뷰함" 이 된다.
    public static func reviewStatus(_ pr: PullRequest) -> ReviewStatus {
        if pr.myReviewAt == nil { return .unreviewed }
        return hasNewCommitsSinceMyReview(pr) ? .newCommits : .reviewed
    }

    /// 고른 상태(rawValue)·저장소(repoKey)·사람(author) 으로 거른다. 빈 집합은 "전체". 세 차원은 AND.
    public static func filterReviews(_ prs: [PullRequest], states: Set<String> = [], repos: Set<String>, authors: Set<String>) -> [PullRequest] {
        prs.filter {
            (states.isEmpty || states.contains(reviewStatus($0).rawValue))
                && (repos.isEmpty || repos.contains(repoKey($0.id)))
                && (authors.isEmpty || authors.contains($0.author))
        }
    }

    /// 팝오버에 보일 값과 개수. 개수는 다른 차원의 선택만 적용하고 이 차원의 선택은 무시해서,
    /// 하나 골랐다고 나머지 값이 사라지지 않게 한다. 상태는 고정 순서, 나머지는 개수 내림차순.
    /// 목록에 없는 선택값은 0개로 맨 아래에 남겨 풀 수 있게 한다.
    public static func facets(_ prs: [PullRequest], kind: FacetKind, states: Set<String> = [], repos: Set<String>, authors: Set<String>) -> [Facet] {
        let base = filterReviews(prs, states: kind == .status ? [] : states,
                                 repos: kind == .repo ? [] : repos, authors: kind == .author ? [] : authors)
        if kind == .status {
            return ReviewStatus.allCases.map { st in
                Facet(key: st.rawValue, label: st.label, provider: nil, count: base.filter { reviewStatus($0) == st }.count)
            }
        }
        var map: [String: Facet] = [:]
        for pr in base {
            let key = kind == .repo ? repoKey(pr.id) : pr.author
            if map[key] == nil {
                map[key] = Facet(key: key, label: kind == .repo ? pr.repo : pr.author,
                                 provider: kind == .repo ? pr.provider : nil, count: 0)
            }
            map[key]?.count += 1
        }
        let live = map.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        let selected = kind == .repo ? repos : authors
        let gone = selected.subtracting(map.keys).sorted().map { key -> Facet in
            kind == .repo
                ? Facet(key: key, label: String(key.split(separator: "/").last ?? Substring(key)), provider: provider(of: key), count: 0)
                : Facet(key: key, label: key, provider: nil, count: 0)
        }
        return live + gone
    }

    static let activityCap = 50
    /// 직전 상태 was 와 비교해 아직 못 본 다른 사람의 댓글·리뷰. was 가 없으면(처음 보는 PR) 이미 있던 것으로 보고 빈 배열.
    static func newActivity(_ pr: PullRequest, _ was: PRMineState?) -> [PRActivity] {
        guard let was else { return [] }
        let seen = Set(was.activity)
        var ids = Set<String>()
        return pr.recentActivity.filter { !seen.contains($0.id) && ids.insert($0.id).inserted }
    }

    /// 지금 목록의 요약. old 가 있으면 이미 본 댓글 id 를 이어받는다 (이번에 못 가져온 Bitbucket 댓글 id 를 잃지 않게).
    public static func snapshot(reviewRequests: [PullRequest], mine: [PullRequest], old: PRSnapshot? = nil) -> PRSnapshot {
        var states: [String: PRMineState] = [:]
        for pr in mine {
            let o = old?.mine[pr.id]
            let current = pr.recentActivity.map(\.id)
            states[pr.id] = PRMineState(
                approvers: Set(pr.reviewers.filter { $0.state == .approved }.map(\.name)),
                changers: Set(pr.reviewers.filter { $0.state == .changesRequested }.map(\.name)),
                activity: Array((current + (o?.activity ?? []).filter { !current.contains($0) }).prefix(activityCap)),
                commentCount: pr.commentCount ?? o?.commentCount)
        }
        return PRSnapshot(reviewRequestIDs: Set(reviewRequests.filter(\.reviewRequested).map(\.id)), mine: states)
    }

    /// 이번에 성공한 제공자의 항목은 fresh 로 바꾸고, 실패·꺼짐·건너뜀 제공자는 직전 항목을 그대로 둔다
    /// (일부만 받은 결과로 기준이 줄었다가 다음에 "새 항목" 알림이 반복되는 것을 막는다).
    public static func mergedSnapshot(old: PRSnapshot?, fresh: PRSnapshot, succeeded: Set<PRProvider>) -> PRSnapshot {
        func ok(_ id: String) -> Bool { provider(of: id).map(succeeded.contains) ?? false }
        var ids = fresh.reviewRequestIDs.filter(ok)
        var mine = fresh.mine.filter { ok($0.key) }
        if let old {
            ids.formUnion(old.reviewRequestIDs.filter { !ok($0) })
            for (k, v) in old.mine where !ok(k) { mine[k] = v }
        }
        return PRSnapshot(reviewRequestIDs: ids, mine: mine,
                          providers: (old?.providers ?? []).union(succeeded.map(\.rawValue)))
    }

    /// 본 목록(seen)에서 이번에 성공한 제공자의 사라진 항목만 지운다. 못 받은 제공자 항목은 유지.
    public static func trimSeen(_ seen: Set<String>, present: Set<String>, succeeded: Set<PRProvider>) -> Set<String> {
        seen.filter { id in provider(of: id).map(succeeded.contains) == true ? present.contains(id) : true }
    }

    /// 직전 요약과 비교해 알릴 것. 첫 실행(old == nil)과, old 에 아직 없던 제공자(처음 켠 것)는 알리지 않는다.
    /// - 새 리뷰 요청: "나한테 요청된" PR 만.
    /// - 내 PR: 새 승인자·새 변경 요청자는 한 명씩, 다른 사람의 새 댓글·리뷰는 PR 당 하나로 묶어서.
    ///   직전에 없던 내 PR 은 승인·변경 요청은 빈 상태에서 비교하고, 댓글은 이미 있던 것으로 보고 알리지 않는다.
    /// - 내가 한 행동은 알리지 않는다 (댓글은 가져올 때 내 것을 이미 뺐고, 내 PR 의 리뷰어에는 내가 없다).
    /// reviewRequests/mine 에는 이번에 성공한 제공자의 PR 만 넘긴다.
    public static func notifications(old: PRSnapshot?, new: PRSnapshot,
                                     reviewRequests: [PullRequest], mine: [PullRequest]) -> [PRNotice] {
        guard let old else { return [] }
        var out: [PRNotice] = []
        for pr in reviewRequests where pr.reviewRequested && old.providers.contains(pr.provider.rawValue)
            && new.reviewRequestIDs.contains(pr.id) && !old.reviewRequestIDs.contains(pr.id) {
            out.append(.newReviewRequest(pr))
        }
        for pr in mine where old.providers.contains(pr.provider.rawValue) {
            let was = old.mine[pr.id]
            let total = pr.reviewers.count
            let wasApprovers = was?.approvers ?? []
            let fresh = pr.reviewers.filter { $0.state == .approved && !wasApprovers.contains($0.name) }
            let allDone = approval(pr) == .approved(total, total)
            var n = wasApprovers.count
            for (i, r) in fresh.enumerated() {
                n += 1
                out.append(.approved(pr, by: r.name, count: n, total: total, complete: allDone && i == fresh.count - 1))
            }
            let wasChangers = was?.changers ?? []
            for r in pr.reviewers where r.state == .changesRequested && !wasChangers.contains(r.name) {
                out.append(.changesRequested(pr, by: r.name))
            }
            if let was {
                let new = newActivity(pr, was)
                if !new.isEmpty {
                    var authors: [String] = []
                    for a in new where !authors.contains(a.author) { authors.append(a.author) }
                    out.append(.comments(pr, authors: authors, count: new.count))
                }
            }
        }
        return out
    }

    /// 탭 배지: 아직 못 본 (요청된) 리뷰 요청 + 변경 요청 받은 내 PR.
    public static func badgeCount(reviewRequests: [PullRequest], mine: [PullRequest], seen: Set<String>) -> Int {
        reviewRequests.filter { $0.reviewRequested && !seen.contains($0.id) }.count
            + mine.filter { approval($0) == .changesRequested }.count
    }

    public static func todoTitle(_ pr: PullRequest, isReviewRequest: Bool) -> String {
        (isReviewRequest ? "[PR 리뷰] " : "[PR] ") + pr.title
    }

    /// ISO 8601 (GitHub "…Z", Bitbucket "….123456+00:00"). 소수 초는 버리고 읽는다.
    public static func parseDate(_ s: String?) -> Date? {
        guard var s, !s.isEmpty else { return nil }
        if let dot = s.firstIndex(of: ".") {
            let rest = s[s.index(after: dot)...]
            let tail = rest.drop(while: { $0.isNumber })
            s = String(s[..<dot]) + tail
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// MARK: - Bitbucket 저장소 찾기

public enum BitbucketRemote {
    /// `git@bitbucket.org:ws/slug.git`, `https://user@bitbucket.org/ws/slug.git`, `ssh://git@bitbucket.org/ws/slug`.
    public static func parse(_ remoteURL: String) -> (workspace: String, slug: String)? {
        let s = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = s.range(of: "bitbucket.org", options: .caseInsensitive) else { return nil }
        // 호스트 앞은 시작, "@", "/" 중 하나여야 한다 (notbitbucket.org 같은 것 제외)
        if r.lowerBound != s.startIndex {
            let c = s[s.index(before: r.lowerBound)]
            guard c == "@" || c == "/" else { return nil }
        }
        var path = String(s[r.upperBound...])
        // 포트(ssh://host:7999/...)는 숫자만 오므로 ":" 뒤 숫자 + "/" 는 건너뛴다
        if path.hasPrefix(":") {
            path.removeFirst()
            if let slash = path.firstIndex(of: "/"), path[..<slash].allSatisfy(\.isNumber), !path[..<slash].isEmpty {
                path = String(path[slash...])
            }
        }
        while path.hasPrefix("/") { path.removeFirst() }
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".git") { path.removeLast(4) }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }
}

public enum LocalRepos {
    public static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        ["projects", "Projects", "dev", "workspace", "IdeaProjects", "Developer"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
    }

    /// 같은 폴더를 가리키는 경로를 하나로 줄인다. 기본 APFS 는 대소문자를 안 가려서 ~/projects 와 ~/Projects 가 같은 폴더다.
    public static func uniqueDirs(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { p in
            let u = URL(fileURLWithPath: p)
            let key = (try? u.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier).map { "\($0)" }
                ?? u.standardizedFileURL.path.lowercased()
            return seen.insert(key).inserted
        }
    }

    /// 이 Mac 에 클론된 저장소 중 workspace 에 속한 slug. git 을 실행하지 않고 .git/config 만 읽는다.
    public static func bitbucketSlugs(workspace: String, roots: [URL] = LocalRepos.defaultRoots()) -> [String] {
        let fm = FileManager.default
        var found = Set<String>()
        func subdirs(_ u: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        func check(_ dir: URL) -> Bool {
            guard let url = originURL(of: dir) else { return false }
            if let p = BitbucketRemote.parse(url), p.workspace.caseInsensitiveCompare(workspace) == .orderedSame {
                found.insert(p.slug)
            }
            return true
        }
        for root in roots {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { continue }
            for child in subdirs(root) {
                // 저장소 안은 더 내려가지 않는다. 저장소가 아니면(묶음 폴더) 한 단계 더.
                if hasGit(child) { _ = check(child); continue }
                for grand in subdirs(child) where hasGit(grand) { _ = check(grand) }
            }
        }
        return found.sorted()
    }

    /// 폴더 하나에서 찾은 클론 수 (폴더별 "저장소 N개" 표시용).
    public static func count(workspace: String, root: URL) -> Int {
        bitbucketSlugs(workspace: workspace, roots: [root]).count
    }

    private static func hasGit(_ dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path)
    }

    /// `.git` 이 폴더면 그 안의 config, 파일(`gitdir: …`, 워크트리·서브모듈)이면 가리키는 곳. 워크트리는 commondir 의 config.
    static func originURL(of repo: URL) -> String? {
        let fm = FileManager.default
        let dotGit = repo.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) else { return nil }
        var gitDir = dotGit
        if !isDir.boolValue {
            guard let text = try? String(contentsOf: dotGit, encoding: .utf8),
                  let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
            let p = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            gitDir = URL(fileURLWithPath: p, relativeTo: repo).standardizedFileURL
        }
        var config = gitDir.appendingPathComponent("config")
        if !fm.fileExists(atPath: config.path),
           let common = try? String(contentsOf: gitDir.appendingPathComponent("commondir"), encoding: .utf8) {
            let c = common.trimmingCharacters(in: .whitespacesAndNewlines)
            config = URL(fileURLWithPath: c, relativeTo: gitDir).standardizedFileURL.appendingPathComponent("config")
        }
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return nil }
        return originURL(fromConfig: text)
    }

    /// `[remote "origin"]` 구역의 `url = …`.
    static func originURL(fromConfig text: String) -> String? {
        var inOrigin = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOrigin = line.replacingOccurrences(of: " ", with: "") == "[remote\"origin\"]"
            } else if inOrigin, line.hasPrefix("url"), let eq = line.firstIndex(of: "=") {
                return line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
