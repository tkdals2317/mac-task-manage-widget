import AppKit
import SwiftUI
import TaskWidgetCore

/// Aside 준비 상태를 한 번 살펴본 결과.
struct AsideReport: Equatable {
    var browserInstalled: Bool
    var browserVersion: String
    /// Aside CLI 를 못 찾았으면 nil
    var probe: AsideProbe?

    /// 진단 로그용 한 줄 (계정 이메일은 넣지 않는다).
    var diagLine: String {
        guard let p = probe else { return "browser=\(browserInstalled ? browserVersion : "없음") cli=없음" }
        let account: String
        switch p.account {
        case .signedIn(_, let id, _): account = "signedIn(u\(id))"
        case .signedOut(_, let reason): account = "signedOut(\(reason))"
        case .unknown(let m): account = "unknown(\(m.replacingOccurrences(of: "[^\\s@]+@[^\\s@]+", with: "<이메일>", options: .regularExpression)))"
        }
        return "browser=\(browserInstalled ? browserVersion : "없음") cli=\(p.version)(\(p.source), 최신 \(p.latestVersion)) "
            + "runnable=\(p.runnable) account=\(account) others=\(p.otherAccounts.count) window=\(p.windowOpen.map(String.init) ?? "?")"
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
    /// 마지막 Aside 점검 결과. 아직 점검 전이면 nil. 다시 점검하는 동안에도 이전 결과를 그대로 보여준다.
    @Published private(set) var report: AsideReport?
    @Published private(set) var checkingAside = false
    /// Aside 가 받아 둔 모델 목록과 내 요금제 (모델 메뉴용). 못 읽으면 빈 목록.
    @Published private(set) var asideModels: [AsideModel] = []
    @Published private(set) var asidePlan = ""
    @Published private(set) var submitting = false
    @Published var submitError: String?
    /// 준비 점검의 동작(계정 바꾸기·터미널 열기)이 실패했을 때 보여줄 한 줄
    @Published private(set) var setupError: String?
    /// 결과 상세로 열린 job. nil 이면 목록.
    @Published var openJobId: String? { didSet { submitError = nil } }
    /// 요청 화면에서 고르고 쓰던 것. 결과를 보거나 탭을 옮겨도 남게 모델에 둔다.
    @Published var draftSelected: Set<String> = []
    @Published var draftKeys = ""
    @Published var draftNotes = ""

    let store: E2EJobStore
    private let runner: E2ERunner
    /// 진행 중인 Aside 점검. 겹쳐 부르면 같은 점검을 기다린다.
    private var checkTask: Task<Void, Never>?
    /// 사용자가 Aside 쪽 할 일을 마칠 때까지 다시 확인하는 작업.
    private var asideWatch: Task<Void, Never>?

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

    // MARK: - 탭 도입 (한 번)

    /// E2E 탭이 생긴 버전으로 처음 올라온 사용자에게 탭을 한 번 켜 준다. 이후 끄면 다시 켜지 않는다.
    /// 처음 설치하는 사람은 설정 도우미에서 고르므로 건드리지 않는다.
    static func introduceTabIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: SettingsKey.e2eTabIntroduced) else { return }
        let s = Settings.shared
        defer { d.set(true, forKey: SettingsKey.e2eTabIntroduced) }
        let fm = FileManager.default
        if Onboarding.shouldShow(done: s.onboardingDone, todosExists: fm.fileExists(atPath: Paths.todosFile.path),
                                 jiraEmail: s.jiraEmail, teleportExists: fm.fileExists(atPath: Paths.teleportFile.path),
                                 notesExists: fm.fileExists(atPath: Paths.notesFile.path)) { return }
        let ids = allTabs.map(\.id)
        if !TabConfig.enabled(from: s.enabledTabs, all: ids).contains("e2e") {
            s.enabledTabs = TabConfig.toggled("e2e", in: s.enabledTabs, all: ids)
        }
    }

    // MARK: - Aside 준비 점검

    var probe: AsideProbe? { report?.probe }

    /// 실행에 쓸 aside 경로와 Aside 계정 번호 (실행용 폴더 `~/.aside/u/<id>/atm-e2e` 를 정한다). 준비가 안 됐으면 nil.
    var runTarget: (path: String, accountId: Int)? {
        guard let p = probe, p.runnable, case .signedIn(_, let id, _) = p.account else { return nil }
        return (p.path, id)
    }
    var asideReady: Bool { runTarget != nil }

    /// 준비 항목. env 를 주면 그 환경의 주소·로그인 항목까지 본다 (url·user 는 설정에 넣은 값 그대로).
    func setupItems(env: E2EEnv? = nil, url: String = "", user: String = "") -> [E2ESetupItem] {
        guard let report else { return [] }
        let base = Onboarding.normalizedURL(url)
        var finished: [(job: E2EJob, result: E2EResult)] = []
        if env != nil {
            for j in jobs where j.status == .done {
                if case .ok(let r) = results[j.id] { finished.append((j, r)) }
            }
        }
        return E2ESetup.items(E2ESetupInput(
            browserInstalled: report.browserInstalled, browserVersion: report.browserVersion, probe: report.probe,
            env: env, envURL: base, envUser: user.trimmingCharacters(in: .whitespaces),
            lastLogin: env.map { E2ELoginHistory.latest(env: $0, baseUrl: base, finished: finished) } ?? .none))
    }

    /// quiet: 확인 중 표시 없이 결과만 바꾼다 (사용자를 기다리며 반복 확인할 때, 실행 직전).
    /// 이미 점검 중이면 그 점검이 끝나기를 기다린다.
    func checkAside(quiet: Bool = false) async {
        if let t = checkTask { await t.value; return }
        let t = Task { await runCheck(quiet: quiet) }
        checkTask = t
        await t.value
        checkTask = nil
    }

    private func runCheck(quiet: Bool) async {
        // 스크린샷 데모는 실제 CLI 를 부르지 않는다
        if DemoFixtures.isOn {
            let demo = AsideProbe(path: "aside", source: "데모", account: .signedIn(email: "demo@example.com", accountId: 0, plan: ""),
                                  windowOpen: true)
            report = AsideReport(browserInstalled: true, browserVersion: "", probe: demo)
            return
        }
        if !quiet { checkingAside = true }
        defer { checkingAside = false }
        let configured = Settings.shared.e2eAsidePath
        let app = AsideBrowser.appURL
        let probe = await Task.detached { () -> AsideProbe? in
            guard let f = AsideCLI.locateWithSource(configured: configured) else { return nil }
            return AsideCLI.probe(executable: f.path, source: f.source)
        }.value
        let next = AsideReport(browserInstalled: app != nil, browserVersion: app.map(AsideBrowser.version) ?? "", probe: probe)
        if next != report { DiagLog.append("e2e aside: \(next.diagLine)") }
        report = next
        if case .signedIn(_, let accountId, let plan) = probe?.account {
            asidePlan = plan
            asideModels = await Task.detached { AsideCLI.models(accountId: accountId) }.value
        }
    }

    /// 준비 항목의 버튼. env 는 환경을 여는 동작에만 쓴다.
    func perform(_ fix: E2ESetupFix, env: E2EEnv? = nil) {
        setupError = nil
        switch fix {
        case .downloadBrowser:
            if let u = URL(string: AsideCLI.browserDownloadURL) { NSWorkspace.shared.open(u) }
            watchAside(minutes: 10) { $0.browserInstalled }
        case .installCLI:
            guard openTerminal(AsideCLI.installScript(), name: "ATM-aside-install.command") else { return }
            watchAside(minutes: 10) { $0.probe != nil }
        case .updateCLI:
            guard let p = probe, openTerminal(AsideCLI.updateScript(executable: p.path), name: "ATM-aside-update.command") else { return }
            let before = p.version
            watchAside(minutes: 5) { $0.probe?.version != before }
        case .openAside:
            AsideBrowser.launch()
            watchAside(minutes: 5) { r in
                guard let p = r.probe, case .signedIn = p.account else { return false }
                return p.windowOpen != false
            }
        case .switchAccount(let id, _):
            guard let exe = probe?.path else { return }
            Task {
                setupError = await Task.detached { AsideCLI.useAccount(executable: exe, id: id) }.value
                await checkAside()
            }
        case .openSettings:
            NotificationCenter.default.post(name: .openSettings, object: "e2e")
        case .openEnvironment:
            guard let env, let site = E2EWebURL.parse(Onboarding.normalizedURL(Settings.shared.e2eURL(env))) else { return }
            AsideBrowser.open(site)
        }
    }

    /// 스크립트를 .command 로 써서 터미널로 연다.
    private func openTerminal(_ text: String, name: String) -> Bool {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try Data(text.utf8).write(to: script, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch {
            setupError = "터미널 스크립트를 만들지 못했어요 · \(error.localizedDescription)"
            return false
        }
        NSWorkspace.shared.open(script)
        return true
    }

    /// 사용자가 Aside·터미널에서 할 일을 마칠 때까지 3초마다 조용히 다시 확인한다. done 이 true 가 되면 멈춘다.
    private func watchAside(minutes: Int, until done: @escaping (AsideReport) -> Bool) {
        asideWatch?.cancel()
        asideWatch = Task { [weak self] in
            for _ in 0..<(minutes * 20) {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, let me = self else { return }
                await me.checkAside(quiet: true)
                if let r = me.report, done(r) { return }
            }
        }
    }

    /// Aside 창이 닫혀 있으면 실행이 바로 실패한다. Aside 를 열고 창이 연결될 때까지 잠깐 기다린다.
    private func openAsideWindow(executable: String) async -> Bool {
        AsideBrowser.launch(activate: false)
        for _ in 0..<15 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            // 확인하지 못한 경우(nil)는 막지 않고 실행에 맡긴다
            if await Task.detached(operation: { AsideCLI.windowOpen(executable: executable) }).value != false {
                report?.probe?.windowOpen = true
                return true
            }
        }
        return false
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

        // 실행 직전 상태로 다시 본다 (그사이 로그아웃했거나 Aside 창을 닫았을 수 있다)
        await checkAside(quiet: true)
        guard let target = runTarget else {
            submitError = E2ESetup.blocker(setupItems())?.detail ?? "Aside 준비 상태를 확인하지 못했어요 · '다시 확인'을 눌러 주세요"
            return false
        }
        let exe = target.path, accountId = target.accountId
        if probe?.windowOpen == false, !(await openAsideWindow(executable: exe)) {
            submitError = "Aside 브라우저 창을 열지 못했어요 · Aside 를 직접 연 뒤 다시 실행해 주세요"
            return false
        }

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

    static func version(_ app: URL) -> String {
        Bundle(url: app)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    static func open(_ url: URL) {
        guard let app = appURL else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Aside 를 켠다. 이미 켜져 있고 창이 없으면 새 창이 뜬다. activate 가 false 면 앞으로 가져오지 않는다.
    static func launch(activate: Bool = true) {
        guard let app = appURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = activate
        NSWorkspace.shared.openApplication(at: app, configuration: config)
    }
}
