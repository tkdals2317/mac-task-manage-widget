import AppKit
import SwiftUI
import TaskWidgetCore

/// Aside CLI 준비 상태 (경로 + 로그인).
enum AsideStatus: Equatable {
    case unchecked
    case checking
    case missing
    case signedOut(path: String)
    /// accountId: 실행용 폴더(`~/.aside/u/<id>/atm-e2e`)를 정하는 Aside 계정 번호
    case ready(path: String, account: String, accountId: Int)
    case failed(path: String, message: String)

    var isReady: Bool { if case .ready = self { return true }; return false }

    /// 찾은 aside 경로. 못 찾았거나 확인 전이면 nil.
    var path: String? {
        switch self {
        case .signedOut(let p), .ready(let p, _, _), .failed(let p, _): return p
        case .unchecked, .checking, .missing: return nil
        }
    }

    /// 실행을 막는 이유. 준비됐으면 nil.
    var problem: String? {
        switch self {
        case .unchecked, .checking: return "Aside CLI 를 확인하는 중이에요"
        case .missing: return "Aside CLI 를 찾지 못했어요 · 설치한 뒤 설정 > E2E 에서 다시 확인"
        case .signedOut: return "Aside CLI 로그인이 필요해요 · 설정 > E2E 의 '터미널에서 로그인' 후 Aside 설정 > 계정 > 기기에서 승인"
        case .failed(_, let m): return "Aside CLI 확인 실패 · \(m)"
        case .ready: return nil
        }
    }
}

/// E2E 탭의 데이터. job 기록은 디스크(E2EJobStore)가 원본이고, 실행 중·대기 상태는 E2ERunner 가 원본이다.
@MainActor
final class E2EModel: ObservableObject {
    @Published private(set) var jobs: [E2EJob] = []
    @Published private(set) var results: [String: E2EResultLoad] = [:]
    /// 이슈 키 → 가장 최근 판정 (Jira 목록 뱃지). reload 에서만 만든다.
    @Published private(set) var verdictByKey: [String: (verdict: E2EVerdict, jobId: String)] = [:]
    @Published private(set) var running: String?
    @Published private(set) var runningSince: Date?
    @Published private(set) var queued: [String] = []
    @Published private(set) var aside: AsideStatus = .unchecked
    @Published private(set) var asideSource = ""
    /// Aside 가 받아 둔 모델 목록과 내 요금제 (모델 메뉴용). 못 읽으면 빈 목록.
    @Published private(set) var asideModels: [AsideModel] = []
    @Published private(set) var asidePlan = ""
    @Published private(set) var submitting = false
    @Published var submitError: String?
    /// 결과 상세로 열린 job. nil 이면 목록.
    @Published var openJobId: String? { didSet { submitError = nil } }
    /// 요청 화면에서 고르고 쓰던 것. 결과를 보거나 탭을 옮겨도 남게 모델에 둔다.
    @Published var draftSelected: Set<String> = []
    @Published var draftKeys = ""
    @Published var draftNotes = ""

    let store: E2EJobStore
    private let runner: E2ERunner
    /// 터미널 로그인 뒤 승인될 때까지 상태를 다시 확인하는 작업.
    private var loginWatch: Task<Void, Never>?

    init(store: E2EJobStore = E2EJobStore()) {
        self.store = store
        runner = E2ERunner(store: store)
        // onUpdate 는 러너 큐에서 불린다. 러너 상태를 동기로 읽는 reload 는 메인에서 따로 돌린다.
        runner.onUpdate = { [weak self] job in
            if !job.status.isActive {
                DiagLog.append("e2e \(job.id) \(job.status.rawValue)\(job.error.map { " · \($0)" } ?? "")")
            }
            // Swift 5.10: weak self(var)를 Task 안에서 바로 쓰면 막힌다. let 으로 옮겨 넘긴다.
            let me = self
            Task { @MainActor in me?.reload() }
        }
    }

    /// 앱 시작 시: 지난 실행이 남긴 비밀번호·실행 상태를 정리하고 오래된 job 을 지운다.
    func start() {
        let store = store, days = Settings.shared.e2eRetentionDays, launchedAt = Date()
        Task {
            let configured = Settings.shared.e2eAsidePath
            let cleaned = await Task.detached { () -> [String] in
                let closed = store.recoverOnLaunch(createdBefore: launchedAt)
                store.prune(olderThanDays: days)
                var notes: [String] = []
                for id in E2EJobStore.pruneWorkDirs(in: AsideCLI.workRoots(), createdBefore: launchedAt) {
                    notes.append("남은 실행용 폴더 정리 (\(id))")
                }
                for c in closed {
                    if let pid = c.pid, AsideCLI.terminateLeftover(pid) { notes.append("남은 aside 프로세스 종료 (\(c.id))") }
                    if let sid = c.sessionId, let exe = AsideCLI.locateWithSource(configured: configured)?.path {
                        AsideCLI.stopSession(executable: exe, id: sid)
                        notes.append("남은 Aside 세션 정지 (\(c.id) \(sid))")
                    }
                }
                return notes
            }.value
            for n in cleaned { DiagLog.append("e2e: \(n)") }
            reload()
        }
    }

    func shutdown() { runner.shutdown(timeout: 3) }

    func reload() {
        let list = store.list()
        var r: [String: E2EResultLoad] = [:]
        var entries: [(job: E2EJob, result: E2EResult)] = []
        for j in list where !j.status.isActive {
            let res = store.result(j.id)
            r[j.id] = res
            if j.status == .done, case .ok(let result) = res { entries.append((j, result)) }
        }
        jobs = list
        results = r
        verdictByKey = E2ELatestVerdicts.build(entries)
        let s = runner.state
        if s.running != running { runningSince = s.running == nil ? nil : Date() }
        running = s.running
        queued = s.queued
        if let id = openJobId, !list.contains(where: { $0.id == id }) { openJobId = nil }
    }

    func job(_ id: String) -> E2EJob? { jobs.first { $0.id == id } }
    /// 모델 id → 메뉴에 보일 이름 (모르는 id 는 그대로).
    func modelName(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "Aside 기본 모델" }
        return asideModels.first { $0.id == id }?.name ?? id
    }
    func isActive(_ id: String) -> Bool { running == id || queued.contains(id) }

    // MARK: - Aside CLI

    /// quiet: 확인 중 표시 없이 결과만 바꾼다 (로그인 대기 중 반복 확인용).
    func checkAside(quiet: Bool = false) async {
        guard aside != .checking else { return }
        // 스크린샷 데모는 실제 CLI 를 부르지 않는다
        if DemoFixtures.isOn { aside = .ready(path: "aside", account: "demo@example.com", accountId: 0); asideSource = "데모"; return }
        if !quiet { aside = .checking }
        let configured = Settings.shared.e2eAsidePath
        let found = await Task.detached { () -> (path: String, source: String, account: AsideAccountStatus)? in
            guard let f = AsideCLI.locateWithSource(configured: configured) else { return nil }
            return (f.path, f.source, AsideCLI.accountStatus(executable: f.path))
        }.value
        guard let found else {
            aside = .missing
            asideSource = ""
            return
        }
        asideSource = found.source
        switch found.account {
        case .signedIn(let who, let accountId, let plan):
            aside = .ready(path: found.path, account: who, accountId: accountId)
            asidePlan = plan
            asideModels = await Task.detached { AsideCLI.models(accountId: accountId) }.value
        case .signedOut: aside = .signedOut(path: found.path)
        case .unknown(let m): aside = .failed(path: found.path, message: m)
        }
    }

    /// 찾은 aside 로 로그인하는 터미널 창을 열고, 승인 화면이 보이게 Aside 를 앞으로 띄운다.
    /// 승인될 때까지 3초마다 조용히 다시 확인한다 (최대 5분).
    func openLoginTerminal() {
        guard let exe = aside.path else { return }
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("ATM-aside-login.command")
        do {
            try Data(AsideCLI.loginScript(executable: exe).utf8).write(to: script, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch {
            submitError = "터미널 스크립트를 만들지 못했어요 · \(error.localizedDescription)"
            return
        }
        if let app = AsideBrowser.appURL {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
        NSWorkspace.shared.open(script)
        loginWatch?.cancel()
        loginWatch = Task { [weak self] in
            for _ in 0..<100 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, let me = self else { return }
                await me.checkAside(quiet: true)
                if me.aside.isReady { return }
            }
        }
    }

    // MARK: - 실행

    /// 요청 화면의 초안으로 실행한다. 성공하면 초안을 비운다.
    func submit(env: E2EEnv, keys: [String], notes: String, titles: [String: String]) async -> Bool {
        guard await enqueue(env: env, keys: keys, notes: notes, titles: titles) else { return false }
        draftSelected = []
        draftKeys = ""
        draftNotes = ""
        return true
    }

    /// 끝난 job 을 같은 환경·이슈·메모로 다시 실행한다. 모델과 환경 주소는 지금 설정을 쓴다.
    func retry(_ id: String) async -> Bool {
        guard let job = job(id), !isActive(id) else { return false }
        let titles = Dictionary(job.issues.map { ($0.key, $0.title) }, uniquingKeysWith: { a, _ in a })
        return await enqueue(env: job.env, keys: job.issueKeys, notes: job.notes, titles: titles)
    }

    /// 검증 요청을 만들고 대기열에 넣는다. titles 는 아는 제목 (모르면 빈 값으로 넘긴다).
    private func enqueue(env: E2EEnv, keys: [String], notes: String, titles: [String: String]) async -> Bool {
        submitError = nil
        let s = Settings.shared
        guard !keys.isEmpty else { submitError = "검증할 이슈를 고르거나 키를 입력하세요"; return false }
        guard keys.count <= s.e2eMaxIssues else {
            submitError = "한 번에 \(s.e2eMaxIssues)건까지 실행할 수 있어요 (설정 > E2E 에서 바꿀 수 있어요)"
            return false
        }
        guard env != .pr || s.e2eAllowPR else {
            submitError = "PR(운영) 환경은 설정 > E2E 에서 켜야 실행할 수 있어요"
            return false
        }
        let base = Onboarding.normalizedURL(s.e2eURL(env))
        guard !base.isEmpty else { submitError = "\(env.rawValue) 환경 주소를 설정 > E2E 에 입력하세요"; return false }
        guard !submitting else { return false }
        submitting = true
        defer { submitting = false }

        if !aside.isReady { await checkAside() }
        guard case .ready(let exe, _, let accountId) = aside else { submitError = aside.problem; return false }

        // 비밀번호는 넘기지 않는다. 로그인은 Aside Vault 나 이미 로그인된 세션으로 한다.
        let user = s.e2eUser(env).trimmingCharacters(in: .whitespaces)
        let jira = Onboarding.normalizedURL(s.jiraBaseURL)
        let jobId = E2EJobID.make()
        let (files, logNotes) = await prepareIssueFiles(keys: keys, jobDir: store.dir(jobId), jiraBase: jira)
        let issues = keys.map { key in
            E2EIssueRef(key: key, url: jira.isEmpty ? "" : "\(jira)/browse/\(key)",
                        title: files[key]?.title ?? titles[key] ?? "", detailFile: files[key]?.path)
        }
        let model = s.e2eModel.trimmingCharacters(in: .whitespaces)
        let job = E2EJob(id: jobId, env: env, baseUrl: base, username: user, issues: issues,
                         notes: notes.trimmingCharacters(in: .whitespacesAndNewlines), requestedBy: s.jiraEmail,
                         model: model.isEmpty ? nil : model)
        do {
            try store.create(job)
        } catch {
            submitError = "요청 파일을 만들지 못했어요: \(error.localizedDescription)"
            return false
        }
        let workDir = AsideCLI.workDir(accountId: accountId, jobId: job.id)
        let options = E2ERunOptions(
            executable: exe,
            arguments: AsideCLI.execArguments(prompt: E2EPrompt.render(jobDir: workDir), model: model),
            environment: AsideCLI.environment(executable: exe),
            timeout: E2ERunPolicy.timeout(issueCount: keys.count, minutesPerIssue: s.e2eMinutesPerIssue, maxMinutes: s.e2eMaxMinutes),
            workDir: workDir,
            stopSession: { AsideCLI.stopSession(executable: exe, id: $0) },
            logNotes: logNotes)
        runner.enqueue(job, options: options)
        DiagLog.append("e2e submit \(job.id) env=\(env.rawValue) issues=\(keys.count) model=\(model.isEmpty ? "기본" : model)")
        reload()
        return true
    }

    /// Aside 브라우저가 Jira 2단계 인증에 막히지 않게, ATM 의 Jira 토큰으로 이슈 내용을 받아 job 폴더에 써 둔다.
    /// 토큰이 없거나 실패한 이슈는 파일 없이 두고(브라우저로 연다) 이유를 run.log 에 남긴다.
    private func prepareIssueFiles(keys: [String], jobDir: URL, jiraBase: String)
        async -> (files: [String: (path: String, title: String)], logNotes: [String]) {
        let email = Settings.shared.jiraEmail.trimmingCharacters(in: .whitespaces)
        guard !DemoFixtures.isOn, !email.isEmpty, !jiraBase.isEmpty, let base = URL(string: jiraBase) else {
            return ([:], ["Jira 연결 정보가 없어 이슈는 Aside 브라우저로 열어요"])
        }
        guard let token = await Task.detached(operation: { SecretStore.get(service: Keychain.service, account: email) }).value else {
            return ([:], ["Jira 토큰을 읽지 못해 이슈는 Aside 브라우저로 열어요"])
        }
        let client = JiraClient(baseURL: base, email: email, token: token)
        let fetched = await E2EIssueContext.fetch(keys: keys, client: client)
        var files: [String: (path: String, title: String)] = [:]
        var notes: [String] = []
        for (key, p) in fetched.prepared {
            do {
                let path = try E2EIssueContext.write(p, jobDir: jobDir, issueURL: "\(jiraBase)/browse/\(key)")
                files[key] = (path, p.detail.summary)
                notes.append("Jira \(key): API 로 받음 (댓글 \(p.detail.comments.count), 이미지 \(p.images.count))")
            } catch {
                notes.append("Jira \(key): 파일을 쓰지 못해 브라우저로 열어요 (\(error.localizedDescription))")
            }
        }
        for (key, e) in fetched.errors.sorted(by: { $0.key < $1.key }) {
            notes.append("Jira \(key): 받지 못해 브라우저로 열어요 (\(e))")
            DiagLog.append("e2e jira \(key) 받기 실패: \(e)")
        }
        return (files, notes)
    }

    func cancel(_ id: String) { runner.cancel(jobId: id) }

    func delete(_ id: String) {
        guard !isActive(id) else { return }
        try? store.delete(id)
        reload()
    }

    func revealInFinder(_ id: String) {
        NSWorkspace.shared.activateFileViewerSelecting([store.jobFile(id)])
    }

    func openLog(_ id: String) {
        NSWorkspace.shared.open(store.logFile(id))
    }

    /// run.log 마지막 몇 줄 (실패 원인 보기).
    func logTail(_ id: String, lines: Int = 15) -> String {
        guard let text = try? String(contentsOf: store.logFile(id), encoding: .utf8) else { return "" }
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Aside 브라우저로 주소 열기. 사용자가 직접 로그인하고 Aside Vault 에 저장하게 일반 창에 연다.
/// `aside <주소>` 는 에이전트 세션(모델)이 페이지를 읽고, `aside repl` 은 시크릿 창이라 저장이 남지 않아 앱으로 바로 연다.
enum AsideBrowser {
    static var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: AsideCLI.browserBundleId) }

    static func open(_ url: URL) {
        guard let app = appURL else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
