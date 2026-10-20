import AppKit
import SwiftUI
import UserNotifications
import TaskWidgetCore

enum GitHubStatus: Equatable {
    /// 아직 확인 안 함
    case off
    case ok(String)
    case ghMissing
    case loggedOut
    case error(String)
}

enum BitbucketStatus: Equatable {
    case off
    case ok(String)
    case notConfigured
    case error(String)
}

/// PR 탭의 데이터. 두 제공자를 따로 받아 한쪽이 실패해도 그쪽의 직전 목록을 유지한다.
@MainActor
final class PRModel: ObservableObject {
    @Published private(set) var reviewRequests: [PullRequest] = []
    @Published private(set) var mine: [PullRequest] = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var loading = false
    @Published private(set) var githubStatus: GitHubStatus = .off
    @Published private(set) var bitbucketStatus: BitbucketStatus = .off
    @Published private(set) var githubError: String?
    @Published private(set) var bitbucketError: String?
    @Published private(set) var seen: Set<String>
    /// 승인·승인 취소 요청 중인 PR id
    @Published private(set) var acting: Set<String> = []
    @Published private(set) var actionError: [String: String] = [:]
    /// Bitbucket 토큰에 쓰기 권한이 없다고 확인됨 (토큰을 바꾸면 해제)
    @Published private(set) var bbNoWrite = UserDefaults.standard.bool(forKey: SettingsKey.prBitbucketNoWrite)

    // 제공자별 원본 (숨긴 저장소·Draft 거르기 전)
    private var ghRR: [PullRequest] = [], ghMine: [PullRequest] = []
    private var bbRR: [PullRequest] = [], bbMine: [PullRequest] = []
    private var bbUser: (email: String, user: BBUser)?
    private var bbToken: (email: String, token: String)?
    private var loop: Task<Void, Never>?
    /// gh 경로 캐시 (다시 확인을 누르거나 없어졌을 때만 다시 찾는다)
    private var ghPath: String?
    /// 한도 초과(429 등)를 받은 제공자는 이 시각까지 요청하지 않는다.
    private var nextAllowed: [PRProvider: Date] = [:]
    private var lastBBRefresh: Date?
    private var pendingRefresh = false
    /// 키체인 읽기가 실패·거부된 뒤에는 백그라운드가 다시 시도하지 않는다 (허용 창이 반복해서 뜨지 않게).
    private var keychainFailed = false
    private static let mine404Key = "prBitbucketMine404"
    private static let repoKeyKey = "prBitbucketRepoKey"

    init() {
        seen = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.prSeenIDs) ?? [])
    }

    /// 탭 배지: 못 본 리뷰 요청 + 변경 요청 받은 내 PR.
    var badge: Int { PRLogic.badgeCount(reviewRequests: reviewRequests, mine: mine, seen: seen) }

    // MARK: - 탭 도입 (한 번)

    /// PR 탭이 생긴 버전으로 처음 올라온 사용자에게 탭을 한 번 켜 준다. 이후 끄면 다시 켜지 않는다.
    /// 처음 설치하는 사람은 설정 도우미에서 고르므로 건드리지 않는다.
    static func introduceTabIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: SettingsKey.prTabIntroduced) else { return }
        let s = Settings.shared
        defer { d.set(true, forKey: SettingsKey.prTabIntroduced) }
        let fm = FileManager.default
        if Onboarding.shouldShow(done: s.onboardingDone, todosExists: fm.fileExists(atPath: Paths.todosFile.path),
                                 jiraEmail: s.jiraEmail, teleportExists: fm.fileExists(atPath: Paths.teleportFile.path),
                                 notesExists: fm.fileExists(atPath: Paths.notesFile.path)) { return }
        let ids = allTabs.map(\.id)
        if !TabConfig.enabled(from: s.enabledTabs, all: ids).contains("pr") {
            s.enabledTabs = TabConfig.toggled("pr", in: s.enabledTabs, all: ids)
        }
    }

    // MARK: - 연결 상태

    var githubEnabled: Bool { Settings.shared.prGitHubEnabled }
    var bitbucketEnabled: Bool { Settings.shared.prBitbucketEnabled }
    /// 켜진 제공자가 하나라도 있는가 (없으면 연결 카드)
    var anyEnabled: Bool { githubEnabled || bitbucketEnabled }

    private func resolveGh(force: Bool) async -> String? {
        if !force, let p = ghPath, FileManager.default.isExecutableFile(atPath: p) { return p }
        ghPath = await Task.detached { GhCLI.locate() }.value
        return ghPath
    }

    /// gh 가 있고 로그인돼 있는지만 확인한다 (토큰은 읽자마자 버린다). force: "다시 확인" 때 gh 위치도 다시 찾는다.
    func probeGitHub(force: Bool = false) async {
        guard let gh = await resolveGh(force: force) else { githubStatus = .ghMissing; return }
        let r = await Task.detached { () -> GitHubStatus in
            guard let t = GhCLI.token(path: gh) else { return .loggedOut }
            do { return .ok(try await GitHubClient(token: t).fetchLogin()) }
            catch { return .error((error as? PRError)?.userMessage ?? error.localizedDescription) }
        }.value
        githubStatus = r
    }

    // MARK: - Bitbucket 토큰 (SecretStore)

    /// interactive == false 는 백그라운드: 캐시만 쓰고, 이전에 읽기가 실패했으면 키체인을 건드리지 않는다.
    func bitbucketToken(for email: String, interactive: Bool = true) async -> String? {
        if let c = bbToken, c.email == email { return c.token }
        if !interactive && keychainFailed { return nil }
        let r = await Task.detached { Result { try SecretStore.current.get(service: BitbucketSecrets.service, account: email) } }.value
        switch r {
        case .success(let t):
            keychainFailed = false
            if let t { bbToken = (email, t) }
            return t
        case .failure:
            keychainFailed = true
            return nil
        }
    }

    func setBitbucketToken(_ token: String, email: String) async throws {
        try await Task.detached { try SecretStore.set(token, service: BitbucketSecrets.service, account: email) }.value
        bbToken = (email, token)
        bbUser = nil
        keychainFailed = false
    }

    /// 저장 위치를 바꾸면 캐시를 버린다.
    func resetCaches() { bbToken = nil; bbUser = nil; keychainFailed = false }

    func bitbucketClient(interactive: Bool = true) async -> BitbucketClient? {
        let email = Settings.shared.prBitbucketEmail.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty, let t = await bitbucketToken(for: email, interactive: interactive) else { return nil }
        return BitbucketClient(email: email, token: t)
    }

    /// 설정의 "연결 확인": 입력한 이메일·토큰으로 me() + workspaces(). 아무것도 저장하지 않는다.
    func testBitbucket(email: String, token: String) async throws -> (user: BBUser, workspaces: [BBWorkspace]) {
        let c = BitbucketClient(email: email, token: token)
        let u = try await c.me()
        let ws = try await c.workspaces()
        return (u, ws)
    }

    /// 연결 확인이 성공한 뒤에만 부른다: 이메일 저장, 새 토큰 저장, 이메일이 바뀌었으면 옛 이메일의 토큰 삭제.
    func commitBitbucket(email: String, token: String?) async throws {
        let s = Settings.shared
        let old = s.prBitbucketEmail
        if let token {
            try await setBitbucketToken(token, email: email)
            setNoWrite(false)   // 새 토큰은 쓰기 권한이 있을 수 있다
        }
        if !old.isEmpty, old != email {
            await Task.detached { SecretStore.delete(service: BitbucketSecrets.service, account: old) }.value
            if bbToken?.email == old { bbToken = nil }
        }
        s.prBitbucketEmail = email
        bbUser = nil
    }

    private func setNoWrite(_ v: Bool) {
        bbNoWrite = v
        UserDefaults.standard.set(v, forKey: SettingsKey.prBitbucketNoWrite)
    }

    // MARK: - 승인 (사용자가 확인 팝오버에서 누른 경우에만 호출된다)

    /// 이 PR 에 대한 "나"의 이름 (reviewers 의 name 과 같은 형태: GitHub 로그인 / Bitbucket 표시 이름).
    func myName(_ p: PRProvider) -> String? {
        switch p {
        case .github: if case .ok(let l) = githubStatus { return l } else { return nil }
        case .bitbucket: if case .ok(let n) = bitbucketStatus { return n } else { return nil }
        }
    }

    func approvedByMe(_ pr: PullRequest) -> Bool { PRLogic.approvedBy(pr, me: myName(pr.provider)) }

    func approve(_ pr: PullRequest) async { await act(pr, undo: false) }
    /// Bitbucket 만 (GitHub 는 되돌리기 없음)
    func unapprove(_ pr: PullRequest) async { await act(pr, undo: true) }

    private func act(_ pr: PullRequest, undo: Bool) async {
        guard !acting.contains(pr.id), !(undo && pr.provider == .github), !(pr.provider == .bitbucket && bbNoWrite && !undo) else { return }
        acting.insert(pr.id); actionError[pr.id] = nil
        defer { acting.remove(pr.id) }
        do {
            switch pr.provider {
            case .github:
                guard let p = PRLogic.githubParts(pr.id) else { throw PRError.message("PR 주소를 해석하지 못했어요") }
                guard let gh = await resolveGh(force: false), let t = await Task.detached(operation: { GhCLI.token(path: gh) }).value
                else { throw PRError.message("gh 로그인이 필요해요") }
                try await GitHubClient(token: t).approve(owner: p.owner, repo: p.repo, number: p.number)
            case .bitbucket:
                guard let p = PRLogic.bitbucketParts(pr.id) else { throw PRError.message("PR 주소를 해석하지 못했어요") }
                guard let c = await bitbucketClient() else { throw PRError.message("Bitbucket 토큰이 필요해요") }
                if undo { try await c.unapprove(workspace: p.workspace, slug: p.slug, id: p.number) }
                else { try await c.approve(workspace: p.workspace, slug: p.slug, id: p.number) }
            }
        } catch {
            if case .noWritePermission = error as? PRError { setNoWrite(true) }
            noteRateLimit(pr.provider, error)
            actionError[pr.id] = (error as? PRError)?.userMessage ?? error.localizedDescription
            return
        }
        // 성공: 화면에 바로 반영하고(내 행동이라 알림은 없다), 곧 실제 값을 다시 받는다.
        if let me = myName(pr.provider) {
            let now = Date()
            func change(_ p: PullRequest) -> PullRequest {
                p.id != pr.id ? p : (undo ? PRLogic.markUnapproved(p, by: me) : PRLogic.markApproved(p, by: me, at: now))
            }
            ghRR = ghRR.map(change); bbRR = bbRR.map(change)
            apply(succeeded: [])
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self?.refresh()
        }
    }

    // MARK: - 새로고침

    /// interactive: 사용자가 직접 부른 것(키체인을 다시 시도해도 됨). background: 패널이 숨겨진 상태의 주기 새로고침.
    func refresh(interactive: Bool = true, background: Bool = false) async {
        // 진행 중에 들어온 요청(토글 등)은 끝난 뒤 한 번 더 돌린다.
        if loading { pendingRefresh = true; return }
        loading = true
        var inter = interactive, bg = background
        repeat {
            pendingRefresh = false
            await runRefresh(interactive: inter, background: bg)
            inter = true; bg = false
        } while pendingRefresh
        loading = false
    }

    private func runRefresh(interactive: Bool, background: Bool) async {
        let s = Settings.shared
        guard s.prGitHubEnabled || s.prBitbucketEnabled else {
            // 둘 다 꺼짐: 목록·상태를 비워 배지도 지운다.
            ghRR = []; ghMine = []; bbRR = []; bbMine = []
            githubStatus = .off; bitbucketStatus = .off; githubError = nil; bitbucketError = nil
            apply(succeeded: [])
            return
        }
        async let gh = refreshGitHub()
        async let bb = refreshBitbucket(interactive: interactive, background: background)
        let (g, b) = await (gh, bb)
        lastRefresh = Date()
        var ok = Set<PRProvider>()
        if g { ok.insert(.github) }
        if b { ok.insert(.bitbucket) }
        apply(succeeded: ok)
    }

    private func noteRateLimit(_ p: PRProvider, _ e: Error) {
        if case .rateLimited(let after, _) = e as? PRError ?? .http(0) { nextAllowed[p] = Date().addingTimeInterval(after ?? 300) }
    }

    /// 성공하면 true (실패·꺼짐·건너뜀은 false: 직전 목록과 기준을 유지한다).
    private func refreshGitHub() async -> Bool {
        guard Settings.shared.prGitHubEnabled else { githubStatus = .off; githubError = nil; ghRR = []; ghMine = []; return false }
        if let t = nextAllowed[.github], t > Date() { return false }
        guard let gh = await resolveGh(force: false) else { githubStatus = .ghMissing; githubError = nil; return false }
        // 토큰은 이번 새로고침 동안만 들고 있다가 버린다.
        let r = await Task.detached { () -> Result<GitHubClient.Fetched, Error> in
            guard let t = GhCLI.token(path: gh) else { return .failure(GHSetupError.loggedOut) }
            do { return .success(try await GitHubClient(token: t).fetch()) } catch { return .failure(error) }
        }.value
        switch r {
        case .success(let f):
            ghRR = f.reviewRequests; ghMine = f.mine
            githubStatus = .ok(f.login); githubError = nil
            return true
        case .failure(GHSetupError.loggedOut):
            githubStatus = .loggedOut; githubError = nil
        case .failure(let e):
            noteRateLimit(.github, e)
            let m = (e as? PRError)?.userMessage ?? e.localizedDescription
            githubError = m
            if case .ok = githubStatus {} else { githubStatus = .error(m) }
            DiagLog.append("github refresh error: \(m)")
        }
        return false
    }

    private enum GHSetupError: Error { case loggedOut }

    private func refreshBitbucket(interactive: Bool, background: Bool) async -> Bool {
        let s = Settings.shared
        guard s.prBitbucketEnabled else { bitbucketStatus = .off; bitbucketError = nil; bbRR = []; bbMine = []; return false }
        if let t = nextAllowed[.bitbucket], t > Date() { return false }
        // 패널이 숨겨져 있을 때는 Bitbucket 을 10분에 한 번만 (요청이 저장소 수만큼 나간다)
        if background, let l = lastBBRefresh, Date().timeIntervalSince(l) < 600 { return false }
        let ws = s.prBitbucketWorkspace
        guard let c = await bitbucketClient(interactive: interactive), !ws.isEmpty else {
            if bitbucketStatus != .notConfigured { bitbucketStatus = .notConfigured }
            return false
        }
        do {
            let user: BBUser
            if let cached = bbUser, cached.email == c.email { user = cached.user } else {
                user = try await c.me()
                bbUser = (c.email, user)
            }
            let repos = s.prBitbucketRepoList
            var known404 = Set(UserDefaults.standard.stringArray(forKey: Self.mine404Key) ?? [])
            let skip = known404.contains(ws)
            async let mine = c.mine(workspace: ws, uuid: user.uuid, repos: repos, skipWorkspaceEndpoint: skip)
            async let rr = c.reviewRequests(workspace: ws, repos: repos, uuid: user.uuid)
            let (m, r) = try await (mine, rr)
            // 워크스페이스 경로가 404 였으면 기억해서 다음부터 바로 대체 경로로 간다.
            if m.usedFallback && !skip { known404.insert(ws); UserDefaults.standard.set(known404.sorted(), forKey: Self.mine404Key) }
            bbMine = await withNewComments(m.prs, client: c, workspace: ws, uuid: user.uuid)
            // 못 읽은 저장소는 직전 PR 을 유지한다 (일시 오류로 목록·기준이 줄지 않게)
            let failed = r.failed.map { "bitbucket:\(ws)/\($0)#" }
            bbRR = r.prs + bbRR.filter { p in failed.contains { p.id.hasPrefix($0) } }
            // 없어진 저장소는 매번 오류를 띄우는 대신 선택 목록에서 조용히 뺀다.
            if !r.gone.isEmpty {
                s.prBitbucketRepoList = s.prBitbucketRepoList.filter { !r.gone.contains($0) }
                DiagLog.append("bitbucket repos removed (404): \(r.gone.sorted().joined(separator: ","))")
            }
            lastBBRefresh = Date()
            bitbucketStatus = .ok(user.displayName)
            bitbucketError = r.errors.isEmpty ? nil : "저장소 \(r.errors.count)개를 못 읽었어요 · \(r.errors[0])"
            if !r.errors.isEmpty { DiagLog.append("bitbucket repo errors: \(r.errors.count)") }
            return true
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return false }
            noteRateLimit(.bitbucket, error)
            let m = (error as? PRError)?.userMessage ?? error.localizedDescription
            if case .unauthorized = error as? PRError { bbToken = nil; bbUser = nil }
            bitbucketError = m
            if case .ok = bitbucketStatus {} else { bitbucketStatus = .error(m) }
            DiagLog.append("bitbucket refresh error: \(m)")
            return false
        }
    }

    private func loadSnapshot() -> PRSnapshot? {
        UserDefaults.standard.data(forKey: SettingsKey.prLastSnapshot).flatMap { try? JSONDecoder().decode(PRSnapshot.self, from: $0) }
    }

    /// Bitbucket 은 목록에 댓글 내용이 없어서, comment_count 가 직전보다 늘어난 내 PR 만 댓글을 따로 가져온다(한 번에 10개까지).
    /// 못 가져오면(한도·오류·초과) commentCount 를 직전 값으로 되돌려 다음 새로고침에서 다시 시도하게 한다.
    private func withNewComments(_ prs: [PullRequest], client: BitbucketClient, workspace: String, uuid: String) async -> [PullRequest] {
        let old = loadSnapshot()
        var out = prs
        var fetched = 0
        for i in out.indices {
            guard let cnt = out[i].commentCount, let was = old?.mine[out[i].id]?.commentCount, cnt > was else { continue }
            let blocked = (nextAllowed[.bitbucket].map { $0 > Date() } ?? false) || fetched >= 10
            if blocked { out[i].commentCount = was; continue }
            fetched += 1
            do {
                let slug = PRLogic.repoKey(out[i].id).split(separator: "/").last.map(String.init) ?? ""
                out[i].recentActivity = try await client.recentComments(workspace: workspace, slug: slug, id: out[i].number, me: uuid)
            } catch {
                noteRateLimit(.bitbucket, error)
                out[i].commentCount = was
            }
        }
        return out
    }

    /// 원본에서 숨긴 저장소·Draft 를 거르고 정렬해 화면 목록을 만든다.
    /// succeeded: 이번에 성공한 제공자. 본 목록·알림 기준은 (거르기 전) 원본으로, 성공한 제공자 것만 갱신한다. 비면 화면만 다시 거른다.
    private func apply(succeeded: Set<PRProvider>) {
        let s = Settings.shared
        let hidden = Set(s.prHiddenRepoList), hideDrafts = s.prHideDrafts
        func keep(_ p: PullRequest) -> Bool { !hidden.contains(PRLogic.repoKey(p.id)) && !(hideDrafts && p.isDraft) }
        let rawRR = ghRR + bbRR, rawMine = ghMine + bbMine
        reviewRequests = PRLogic.sortReviewRequests(rawRR.filter(keep))
        mine = PRLogic.sortMine(rawMine.filter(keep))
        let trimmed = PRLogic.trimSeen(seen, present: Set(rawRR.map(\.id)), succeeded: succeeded)
        if trimmed != seen { seen = trimmed; saveSeen() }
        guard !succeeded.isEmpty else { return }

        let d = UserDefaults.standard
        var old = d.data(forKey: SettingsKey.prLastSnapshot).flatMap { try? JSONDecoder().decode(PRSnapshot.self, from: $0) }
        // Bitbucket 저장소 선택이 바뀌었으면 그쪽은 알림 없이 기준만 다시 잡는다.
        let repoKey = s.prBitbucketWorkspace + "|" + s.prBitbucketRepos
        if succeeded.contains(.bitbucket), d.string(forKey: Self.repoKeyKey) != repoKey {
            old?.providers.remove(PRProvider.bitbucket.rawValue)
            d.set(repoKey, forKey: Self.repoKeyKey)
        }
        let new = PRLogic.mergedSnapshot(old: old, fresh: PRLogic.snapshot(reviewRequests: rawRR, mine: rawMine, old: old), succeeded: succeeded)
        let notices = PRLogic.notifications(old: old, new: new,
                                            reviewRequests: rawRR.filter { succeeded.contains($0.provider) && keep($0) },
                                            mine: rawMine.filter { succeeded.contains($0.provider) && keep($0) })
        for n in notices { post(n) }
        d.set(try? JSONEncoder().encode(new), forKey: SettingsKey.prLastSnapshot)
    }

    /// 숨김·Draft 설정이 바뀌면 다시 받지 않고 다시 거른다.
    func reapplyFilters() { apply(succeeded: []) }

    private func post(_ n: PRNotice) {
        let s = Settings.shared
        switch n {
        case .newReviewRequest: guard s.prNotifyNewReview else { return }
        case .approved: guard s.prNotifyApproved else { return }
        case .changesRequested: guard s.prNotifyChanges else { return }
        case .comments: guard s.prNotifyComments else { return }
        }
        guard Bundle.main.bundleIdentifier != nil else { return }
        let c = UNMutableNotificationContent()
        c.title = n.title
        c.body = n.body
        c.userInfo = ["url": n.pr.url]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)) { err in
            DiagLog.append("pr notice \(c.title)\(err.map { " failed: \($0.localizedDescription)" } ?? " sent")")
        }
    }

    // MARK: - 본 것

    /// PR 탭이 보이고 목록이 나와 있을 때 부른다: 지금 있는 리뷰 요청을 모두 "봤다"로.
    func markSeen() {
        let ids = Set(reviewRequests.map(\.id))
        guard !ids.isSubset(of: seen) else { return }
        seen.formUnion(ids)
        saveSeen()
    }

    private func saveSeen() { UserDefaults.standard.set(seen.sorted(), forKey: SettingsKey.prSeenIDs) }

    // MARK: - 주기 새로고침

    private static var panelVisible: Bool { NSApp.windows.contains { $0 is FloatingPanel && $0.isVisible } }

    /// 앱 시작 때 한 번. 1분마다 깨어나 "설정한 분이 지났는가"만 본다 (설정을 바꿔도 재시작이 필요 없다).
    /// 패널이 보일 때는 늘, 숨겨져 있으면 알림이 하나라도 켜져 있을 때만 받는다.
    func startLoop() {
        guard loop == nil else { return }
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard let me = self else { return }
                await me.tick()
            }
        }
    }

    private func tick() async {
        let s = Settings.shared
        guard TabConfig.enabled(from: s.enabledTabs, all: allTabs.map(\.id)).contains("pr"), anyEnabled else { return }
        let notifies = s.prNotifyNewReview || s.prNotifyApproved || s.prNotifyChanges || s.prNotifyComments
        guard Self.panelVisible || notifies else { return }
        if let last = lastRefresh, Date().timeIntervalSince(last) < Double(s.prRefreshMinutes) * 60 - 5 { return }
        await refresh(interactive: false, background: !Self.panelVisible)
    }

    /// PR 탭이 나타날 때: 오래됐으면(1분) 새로 받는다.
    func refreshIfStale() async {
        if let last = lastRefresh, Date().timeIntervalSince(last) < 60 { return }
        await refresh(interactive: false)
    }

    // MARK: - 동작

    func open(_ pr: PullRequest) {
        guard let u = URL(string: pr.url), u.scheme == "https" else { return }
        NSWorkspace.shared.open(u)
    }

    func copyBranch(_ pr: PullRequest) {
        CopyFeedback.shared.copy(pr.sourceBranch, message: "브랜치 이름을 복사했어요")
    }

    func copyCheckout(_ pr: PullRequest) {
        // 브랜치 이름은 셸에 그대로 붙는다. 안전한 문자만 아니면 따옴표로 감싼다.
        let b = pr.sourceBranch
        let safe = b.allSatisfy { $0.isLetter || $0.isNumber || "/_-.".contains($0) }
        CopyFeedback.shared.copy("git fetch origin && git checkout " + (safe ? b : Updater.shellQuote(b)),
                                 message: "체크아웃 명령을 복사했어요")
    }

    /// 저장소 키("provider:owner/slug")로 숨긴다. 같은 이름의 다른 소유자 저장소는 영향 없다.
    func hideRepo(_ pr: PullRequest) {
        let s = Settings.shared
        s.prHiddenRepoList = s.prHiddenRepoList + [PRLogic.repoKey(pr.id)]
        reapplyFilters()
    }

    func unhideRepo(_ key: String) {
        let s = Settings.shared
        s.prHiddenRepoList = s.prHiddenRepoList.filter { $0 != key }
        reapplyFilters()
    }

    // MARK: - Bitbucket 저장소 선택용

    func repositories(workspace: String) async throws -> [BBRepo] {
        guard let c = await bitbucketClient() else { throw PRError.message("토큰이 없어요") }
        return try await c.repositories(workspace: workspace)
    }

    private struct RecentCache: Codable { let at: Date; let slugs: [String] }

    /// 최근 30일 내 리뷰어로 들어간 저장소. 저장소 수만큼 요청이 나가서 워크스페이스별로 24시간 캐시한다.
    func recentReviewed(workspace: String, slugs: [String], progress: @escaping @Sendable (Int, Int) -> Void) async -> [String] {
        let key = "prRecentReviewed.\(workspace)"
        let d = UserDefaults.standard
        if let c = d.data(forKey: key).flatMap({ try? JSONDecoder().decode(RecentCache.self, from: $0) }),
           Date().timeIntervalSince(c.at) < 86400 { return c.slugs }
        guard let c = await bitbucketClient() else { return [] }
        let user: BBUser
        if let cached = bbUser, cached.email == c.email { user = cached.user } else {
            guard let u = try? await c.me() else { return [] }
            user = u; bbUser = (c.email, u)
        }
        let found = await c.recentReviewedRepos(workspace: workspace, slugs: slugs, uuid: user.uuid,
                                                since: Date().addingTimeInterval(-30 * 86400), progress: progress)
        d.set(try? JSONEncoder().encode(RecentCache(at: Date(), slugs: found)), forKey: key)
        return found
    }
}
