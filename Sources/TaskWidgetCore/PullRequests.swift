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

    public init(id: String, provider: PRProvider, repo: String, number: Int, title: String, url: String,
                author: String, isDraft: Bool = false, createdAt: Date, updatedAt: Date, lastCommitAt: Date? = nil,
                sourceBranch: String = "", targetBranch: String = "",
                additions: Int? = nil, deletions: Int? = nil, changedFiles: Int? = nil,
                reviewers: [PRReviewer] = [], commentCount: Int? = nil, myReviewAt: Date? = nil,
                reviewRequested: Bool = true) {
        self.id = id; self.provider = provider; self.repo = repo; self.number = number; self.title = title; self.url = url
        self.author = author; self.isDraft = isDraft; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.lastCommitAt = lastCommitAt; self.sourceBranch = sourceBranch; self.targetBranch = targetBranch
        self.additions = additions; self.deletions = deletions; self.changedFiles = changedFiles
        self.reviewers = reviewers; self.commentCount = commentCount; self.myReviewAt = myReviewAt
        self.reviewRequested = reviewRequested
    }
}

public enum PRApproval: Equatable, Sendable {
    case approved(Int, Int), changesRequested, waiting(Int, Int), noReviewers
}

/// 알림 판단에 쓰는 직전 목록의 요약. 전체 PR 을 저장하지 않는다.
public struct PRSnapshot: Codable, Equatable, Sendable {
    /// 나한테 요청된 PR 만
    public var reviewRequestIDs: Set<String>
    /// id → "approved" / "changes" / "waiting"
    public var mineApproval: [String: String]
    /// 이미 한 번 성공적으로 받아 본 제공자 ("github"/"bitbucket"). 처음 켠 제공자는 알림 없이 기준만 잡는다.
    public var providers: Set<String>
    public init(reviewRequestIDs: Set<String> = [], mineApproval: [String: String] = [:], providers: Set<String> = []) {
        self.reviewRequestIDs = reviewRequestIDs; self.mineApproval = mineApproval; self.providers = providers
    }
}

public enum PRNotice: Equatable, Sendable {
    case newReviewRequest(PullRequest)
    case approved(PullRequest)
    case changesRequested(PullRequest)
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

    public static func code(_ a: PRApproval) -> String {
        switch a {
        case .approved: return "approved"
        case .changesRequested: return "changes"
        case .waiting, .noReviewers: return "waiting"
        }
    }

    /// id 앞의 제공자 ("github:o/r#1" → .github).
    public static func provider(of id: String) -> PRProvider? {
        PRProvider(rawValue: String(id.prefix(while: { $0 != ":" })))
    }

    /// "github:o/r#1" → "github:o/r" (저장소 숨김의 키)
    public static func repoKey(_ id: String) -> String {
        String(id.prefix(while: { $0 != "#" }))
    }

    public static func snapshot(reviewRequests: [PullRequest], mine: [PullRequest]) -> PRSnapshot {
        PRSnapshot(reviewRequestIDs: Set(reviewRequests.filter(\.reviewRequested).map(\.id)),
                   mineApproval: Dictionary(mine.map { ($0.id, code(approval($0))) }, uniquingKeysWith: { a, _ in a }))
    }

    /// 이번에 성공한 제공자의 항목은 fresh 로 바꾸고, 실패·꺼짐·건너뜀 제공자는 직전 항목을 그대로 둔다
    /// (일부만 받은 결과로 기준이 줄었다가 다음에 "새 항목" 알림이 반복되는 것을 막는다).
    public static func mergedSnapshot(old: PRSnapshot?, fresh: PRSnapshot, succeeded: Set<PRProvider>) -> PRSnapshot {
        func ok(_ id: String) -> Bool { provider(of: id).map(succeeded.contains) ?? false }
        var ids = fresh.reviewRequestIDs.filter(ok)
        var mine = fresh.mineApproval.filter { ok($0.key) }
        if let old {
            ids.formUnion(old.reviewRequestIDs.filter { !ok($0) })
            for (k, v) in old.mineApproval where !ok(k) { mine[k] = v }
        }
        return PRSnapshot(reviewRequestIDs: ids, mineApproval: mine,
                          providers: (old?.providers ?? []).union(succeeded.map(\.rawValue)))
    }

    /// 본 목록(seen)에서 이번에 성공한 제공자의 사라진 항목만 지운다. 못 받은 제공자 항목은 유지.
    public static func trimSeen(_ seen: Set<String>, present: Set<String>, succeeded: Set<PRProvider>) -> Set<String> {
        seen.filter { id in provider(of: id).map(succeeded.contains) == true ? present.contains(id) : true }
    }

    /// 직전 요약과 비교해 알릴 것. 첫 실행(old == nil)과, old 에 아직 없던 제공자(처음 켠 것)는 알리지 않는다.
    /// 새 리뷰 요청은 "나한테 요청된" PR 만. 내 PR 은 직전에도 있던 것의 상태가 바뀐 경우만 알린다.
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
            guard let was = old.mineApproval[pr.id], let now = new.mineApproval[pr.id], was != now else { continue }
            if now == "approved" { out.append(.approved(pr)) }
            else if now == "changes" { out.append(.changesRequested(pr)) }
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
