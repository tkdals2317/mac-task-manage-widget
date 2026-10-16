import AppKit
import ServiceManagement
import SwiftUI
import TaskWidgetCore

private enum OStep { case features, storage, atlassian, notes, pr, prRepos, claude, teleport, finish }

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// 설정 도우미: 고른 기능에 필요한 설정만 차례로 묻는다. 값은 기존 설정과 같은 곳(Settings·SecretStore·ClaudeIntegration…)에 저장해
/// 나중에 설정 창에서 그대로 보이고 고칠 수 있다.
struct OnboardingView: View {
    /// 창만 닫는다 (done 은 건드리지 않음).
    let onClose: () -> Void
    /// 끝내기: 패널을 열어 보여준다.
    let onFinish: () -> Void

    @EnvironmentObject var state: AppState
    @AppStorage(SettingsKey.fontScale) private var scale = 1.0
    @AppStorage(SettingsKey.globalHotKeyEnabled) private var hotKeyOn = true
    @AppStorage(SettingsKey.summaryHour) private var summaryHour = 18
    @AppStorage(SettingsKey.summaryMinute) private var summaryMinute = 0
    @Environment(\.atmAccent) private var accent

    @State private var step: OStep = .features
    // 1 기능
    @State private var useJira = false
    @State private var useNotes = false
    @State private var useSummary = true
    @State private var useTeleport = false
    @State private var usePR = false
    // 2 저장 위치
    @State private var storage = Settings.shared.secretStorage
    @State private var storageErr = ""
    // 3 Atlassian
    @State private var email = ""
    @State private var jiraURL = ""
    @State private var confURL = ""
    @State private var token = ""
    @State private var hasToken = false
    @State private var atlStatus = ""
    @State private var atlOK = false
    @State private var atlTested = false
    // 4 노트
    @State private var pw = ""
    @State private var pw2 = ""
    @State private var touchOn = true
    @State private var lockMade = false
    @State private var notesErr = ""
    // 5 Claude
    @State private var claudePathFound: String?
    @State private var claudeSearched = false
    @State private var wantHook = true
    @State private var wantTodoSkill = true
    /// 이미 설치돼 있으면 기본으로 다시 설치하지 않는다 (직접 고친 스킬 파일을 덮어쓰지 않게).
    @State private var hookInstalled = false
    @State private var todoInstalled = false
    @State private var claudeErr = ""
    // PR
    @State private var prGitHubOn = false
    @State private var prBitbucketOn = false
    @State private var bb: BitbucketSetup?
    @State private var prRepos: Set<String> = []
    @State private var prErr = ""
    // 6 Teleport
    @State private var tp: TeleportSetupModel?
    @State private var tshVersion = ""
    @State private var tpCount = 0
    // 7 마무리
    @State private var loginAtStart = false
    @State private var finishErr = ""
    @State private var busy = false
    @State private var loaded = false

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }
    private var integration: ClaudeIntegration {
        ClaudeIntegration(executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0])
    }

    /// 고른 기능에 해당하는 단계만.
    private var steps: [OStep] {
        var s: [OStep] = [.features]
        if useJira || useNotes || useTeleport || usePR { s.append(.storage) }
        if useJira || useNotes { s.append(.atlassian) }
        if useNotes { s.append(.notes) }
        if usePR {
            s.append(.pr)
            // 저장소 고르기는 Bitbucket 이 켜져 있고 연결이 확인된 뒤에만
            if prBitbucketOn, bb?.ok == true { s.append(.prRepos) }
        }
        if useSummary { s.append(.claude) }
        if useTeleport { s.append(.teleport) }
        s.append(.finish)
        return s
    }
    private var index: Int { steps.firstIndex(of: step) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress.padding(.horizontal, 24).padding(.top, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch step {
                    case .features: featuresStep
                    case .storage: storageStep
                    case .atlassian: atlassianStep
                    case .notes: notesStep
                    case .pr: prStep
                    case .prRepos: prReposStep
                    case .claude: claudeStep
                    case .teleport: teleportStep
                    case .finish: finishStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, 14)
            }
            Divider()
            footer.padding(.horizontal, 24).padding(.vertical, 12)
        }
        .frame(width: 560, height: 520)
        .environment(\.fontScale, scale)
        .task {
            guard !loaded else { return }
            loaded = true
            load()
        }
    }

    // MARK: - 공통 조각

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(steps.indices, id: \.self) { i in
                Capsule().fill(i <= index ? accent : Color.primary.opacity(0.12)).frame(height: 3)
            }
        }
    }

    private func header(_ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 16 * scale, weight: .medium))
            Text(desc).font(.system(size: 12 * scale)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private func helper(_ s: String) -> some View {
        Text(s).font(.system(size: 10.5 * scale)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    private func line(_ s: String, _ color: Color) -> some View {
        Text(s).font(.system(size: 11 * scale)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }

    private func card<C: View>(selected: Bool = false, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? accent : Color.primary.opacity(0.1), lineWidth: selected ? 1.5 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private func choice(_ icon: String, on: Bool, _ title: String, _ desc: String, enabled: Bool = true) -> some View {
        card(selected: on) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).font(.system(size: 15 * scale)).foregroundStyle(on ? accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12.5 * scale, weight: .semibold))
                    Text(desc).font(.system(size: 11 * scale)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .opacity(enabled ? 1 : 0.6)
        }
    }

    private func check(_ on: Binding<Bool>, _ title: String, _ desc: String) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: on.wrappedValue ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on.wrappedValue ? accent : .secondary).font(.system(size: 14 * scale))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12 * scale, weight: .medium))
                    helper(desc)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func labeled<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11 * scale, weight: .medium)).foregroundStyle(.secondary)
            content()
        }
    }

    private func chip(_ icon: String, _ text: String, _ style: AccentChip.Style, _ enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { AccentChip(icon: icon, text: text, style: style) }
            .buttonStyle(.plain).disabled(!enabled)
    }

    /// 아래 줄: 왼쪽 이전, 오른쪽은 단계마다.
    private var footer: some View {
        HStack(spacing: 8) {
            if index > 0 { chip("chevron.left", "이전", .plain, !busy) { back() } }
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            switch step {
            case .features:
                chip("clock", "나중에 하기", .plain) { Settings.shared.onboardingDone = true; onClose() }
                chip("chevron.right", "다음", .solid) { advance() }
            case .storage:
                chip("chevron.right", "다음", .solid, !busy) { applyStorage() }
            case .atlassian:
                chip("chevron.right", "다음", .solid, !busy) { Task { await nextAtlassian() } }
            case .notes:
                if !state.notes.hasLock { chip("forward", "잠금 안 씀", .plain, !busy) { advance() } }
                chip("chevron.right", "다음", .solid, !busy) { Task { await nextNotes() } }
            case .pr:
                chip("chevron.right", "다음", .solid, !busy) { Task { await nextPR() } }
            case .prRepos:
                chip("chevron.right", "다음", .solid, !busy) { savePRRepos(); advance() }
            case .claude:
                chip(claudePathFound == nil ? "chevron.right" : "arrow.down.circle", claudePathFound == nil ? "다음" : "설치하고 다음", .solid, !busy && claudeSearched) { installClaude() }
            case .teleport:
                if let m = tp {
                    TeleportFooter(m: m, skip: { advance() }, done: { tpCount = m.checked.count; advance() })
                }
            case .finish:
                chip("checkmark", "ATM 시작하기", .solid) { finish() }
            }
        }
    }

    // MARK: - 이동

    private func advance() {
        guard index + 1 < steps.count else { return }
        step = steps[index + 1]
        enter(step)
    }

    private func back() {
        if step == .teleport, let m = tp, m.step == 2 { m.step = 1; m.error = nil; return }
        guard index > 0 else { return }
        step = steps[index - 1]
    }

    /// 단계에 들어올 때 필요한 상태를 읽는다.
    private func enter(_ s: OStep) {
        switch s {
        case .claude where !claudeSearched:
            Task {
                let p = await Task.detached { ClaudeRunner.locateWithSource(configured: Settings.shared.claudePath)?.path }.value
                claudePathFound = p; claudeSearched = true
            }
        case .pr where bb == nil:
            bb = BitbucketSetup(pr: state.pr)
            prGitHubOn = Settings.shared.prGitHubEnabled
            prBitbucketOn = Settings.shared.prBitbucketEnabled
            Task {
                await bb?.load()
                await state.pr.probeGitHub()
                if case .ok = state.pr.githubStatus, !Settings.shared.prGitHubEnabled { prGitHubOn = true }
            }
        case .prRepos:
            prRepos = Set(Settings.shared.prBitbucketRepoList)
        case .teleport where tp == nil:
            tp = TeleportSetupModel(tp: state.teleport)
            if let path = state.teleport.tshPath {
                Task { tshVersion = await Task.detached { TeleportTsh.versionLine(path) }.value }
            }
        case .finish:
            if isBundled { loginAtStart = SMAppService.mainApp.status == .enabled }
        default: break
        }
    }

    private func load() {
        let s = Settings.shared
        let tabs = TabConfig.enabled(from: s.enabledTabs, all: allTabs.map(\.id))
        useSummary = tabs.contains("summary")
        useNotes = tabs.contains("notes")
        useTeleport = tabs.contains("teleport")
        usePR = tabs.contains("pr")
        email = s.jiraEmail
        jiraURL = s.jiraBaseURL
        confURL = s.confluenceBaseURL
        useJira = !s.jiraEmail.isEmpty
        if !s.jiraEmail.isEmpty { Task { hasToken = await state.jiraToken(for: s.jiraEmail) != nil } }
    }

    // MARK: - 1 기능 고르기

    private var featuresStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("ATM 에서 무엇을 쓸까요?", "고른 것만 설정해요. 나중에 언제든 설정에서 켜고 끌 수 있어요.")
            choice("checkmark.square.fill", on: true, "할 일", "오늘 할 일을 적고 체크해요. 하위 할 일·마감일·태그도 붙일 수 있어요. 따로 설정할 건 없어요.", enabled: false)
            Button { useJira.toggle() } label: {
                choice(useJira ? "checkmark.square.fill" : "square", on: useJira, "Jira", "나한테 배정된 이슈를 할 일 아래에 보여주고, 상태도 여기서 바로 바꿔요. Atlassian 토큰이 필요해요.")
            }.buttonStyle(.plain)
            Button { useNotes.toggle() } label: {
                choice(useNotes ? "checkmark.square.fill" : "square", on: useNotes, "노트", "메모를 적고 비밀번호로 잠글 수 있어요. 자주 여는 링크와 Confluence 에서 별표한 문서도 모아 보여줘요.")
            }.buttonStyle(.plain)
            Button { useSummary.toggle() } label: {
                choice(useSummary ? "checkmark.square.fill" : "square", on: useSummary, "요약", "Claude Code 로 한 작업·커밋·할 일을 모아 저녁에 하루 업무 요약을 만들어요. Claude Code 가 설치돼 있어야 해요.")
            }.buttonStyle(.plain)
            Button { usePR.toggle() } label: {
                choice(usePR ? "checkmark.square.fill" : "square", on: usePR, "PR", "GitHub·Bitbucket 에서 나한테 온 리뷰 요청과 내가 올린 PR 의 승인 상태를 모아 봐요. 승인되면 알려줘요.")
            }.buttonStyle(.plain)
            Button { useTeleport.toggle() } label: {
                choice(useTeleport ? "checkmark.square.fill" : "square", on: useTeleport, "Teleport", "개발·스테이징 DB 에 로그인하고 터널을 자동으로 열어 둬요. DB 툴에서 localhost 포트로 접속하면 돼요.")
            }.buttonStyle(.plain)
        }
    }

    // MARK: - 2 비밀 저장 위치

    private var storageStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("비밀 정보를 어디에 둘까요?", "Jira 토큰, Teleport 비밀번호·OTP 키, 노트 Touch ID 열쇠를 저장할 곳이에요. 나중에 설정에서 옮길 수 있어요.")
            Button { storage = "keychain" } label: {
                choice(storage == "keychain" ? "largecircle.fill.circle" : "circle", on: storage == "keychain", "macOS 키체인 (추천)",
                       "Mac 이 비밀번호를 보관하는 금고예요. 가장 안전해요. 처음 쓸 때 'ATM 이 키체인을 사용하려고 합니다' 창이 뜨면 항상 허용을 눌러 주세요.")
            }.buttonStyle(.plain)
            Button { storage = "file" } label: {
                choice(storage == "file" ? "largecircle.fill.circle" : "circle", on: storage == "file", "앱 폴더의 파일",
                       "허용 창이 전혀 뜨지 않아요. 내 계정만 읽을 수 있는 파일(secrets.json)에 저장되지만, 키체인보다는 덜 안전해요. 키체인 창이 자꾸 뜨는 경우에 골라 주세요.")
            }.buttonStyle(.plain)
            helper("노트 메모 자체는 비밀번호로 암호화돼서, 어느 쪽을 골라도 내용이 그대로 저장되지는 않아요.")
            if !storageErr.isEmpty { line(storageErr, .red) }
        }
        .disabled(busy)
    }

    /// 지금 설정과 다르면 기존 항목을 옮기면서 바꾼다 (AppState 가 실패 시 설정을 그대로 둔다).
    private func applyStorage() {
        storageErr = ""
        guard storage != Settings.shared.secretStorage, let kind = SecretStorageKind(rawValue: storage) else { advance(); return }
        busy = true
        Task {
            defer { busy = false }
            do {
                _ = try await state.switchSecretStorage(to: kind)
                advance()
            } catch {
                storageErr = "저장 위치를 바꾸지 못했어요 (기존 설정 유지): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - 3 Atlassian

    private var atlassianStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Atlassian 계정", "Jira 와 Confluence 가 같은 계정·토큰을 써요. 값은 다음을 누를 때 저장돼요.")
            labeled("이메일") { ThemedTextField(prompt: "name@company.com", text: $email) }
            if useJira {
                labeled("Jira 주소") { ThemedTextField(prompt: "https://your-site.atlassian.net", text: $jiraURL) }
            }
            if useNotes {
                labeled("Confluence 주소") {
                    ThemedTextField(prompt: "https://your-site.atlassian.net", text: $confURL)
                    helper("비워 두면 Confluence 별표 문서는 안 보여요")
                }
            }
            labeled("API 토큰") {
                HStack(spacing: 8) {
                    ThemedTextField(prompt: hasToken ? "저장됨 · 바꾸려면 입력" : "토큰을 붙여넣으세요 (⌘V)", text: $token, secure: true)
                    Link("토큰 발급 ↗", destination: Links.jiraToken).font(.system(size: 11 * scale))
                }
                helper("Atlassian 계정 > 보안 > API 토큰에서 만들어 붙여넣으세요. Jira 와 Confluence 가 같은 토큰을 써요.")
            }
            HStack(spacing: 8) {
                chip("bolt.horizontal", "연결 확인", .soft, !busy) { Task { await testAtlassian() } }
                if !atlStatus.isEmpty { line(atlStatus, atlOK ? .green : (atlTested ? .red : .secondary)) }
            }
        }
        .disabled(busy)
    }

    /// 이메일·주소·토큰 저장 (설정 > Jira / 노트 와 같은 곳).
    private func saveAtlassian() async throws {
        let s = Settings.shared
        s.jiraEmail = email.trimmed
        if useJira { jiraURL = Onboarding.normalizedURL(jiraURL); s.jiraBaseURL = jiraURL }
        if useNotes { confURL = Onboarding.normalizedURL(confURL); s.confluenceBaseURL = confURL }
        let t = token.trimmed
        if !t.isEmpty, !s.jiraEmail.isEmpty {
            try await state.setJiraToken(t, account: s.jiraEmail)
            token = ""
        }
        hasToken = s.jiraEmail.isEmpty ? false : await state.jiraToken(for: s.jiraEmail) != nil
    }

    private func nextAtlassian() async {
        busy = true; defer { busy = false }
        do { try await saveAtlassian(); advance() } catch { atlStatus = "저장 실패: \(error.localizedDescription)"; atlOK = false; atlTested = true }
    }

    private func testAtlassian() async {
        busy = true; defer { busy = false }
        atlTested = true; atlOK = false
        do { try await saveAtlassian() } catch { atlStatus = "저장 실패: \(error.localizedDescription)"; return }
        let s = Settings.shared
        if s.jiraEmail.isEmpty { atlStatus = "이메일을 입력하세요"; return }
        guard hasToken else { atlStatus = "API 토큰을 붙여넣으세요 (한글 입력 소스에서는 ⌘V 로)"; return }
        var parts: [String] = []
        var ok = true
        if useJira {
            if let url = URL(string: s.jiraBaseURL), !s.jiraBaseURL.isEmpty, let t = await state.jiraToken(for: s.jiraEmail) {
                do { parts.append("Jira: " + (try await JiraClient(baseURL: url, email: s.jiraEmail, token: t).whoAmI())) }
                catch let e as JiraError { parts.append("Jira: " + e.userMessage); ok = false }
                catch { parts.append("Jira: " + error.localizedDescription); ok = false }
            } else { parts.append("Jira: 주소를 입력하세요"); ok = false }
        }
        if useNotes, !s.confluenceBaseURL.isEmpty {
            let r = await state.testConfluence(baseURL: s.confluenceBaseURL)
            if r.hasPrefix("OK: ") { parts.append("Confluence: 별표 " + r.dropFirst(4)) } else { parts.append("Confluence: " + r); ok = false }
        }
        atlStatus = parts.isEmpty ? "저장했어요" : parts.joined(separator: " · ")
        atlOK = ok
    }

    // MARK: - 4 노트 잠금

    private var hasLock: Bool { state.notes.hasLock || lockMade }

    private var notesStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("메모 잠금", "비밀번호를 정해 두면 메모마다 🔒를 눌러 잠글 수 있어요. 잠긴 메모는 암호화돼서 저장되고, 5분이 지나거나 패널을 닫으면 다시 잠겨요.")
            if hasLock {
                line("잠금 비밀번호가 이미 있어요", .green)
                if NotesModel.touchIDAvailable {
                    helper("Touch ID 로 열기: \(state.notes.touchIDEnabled ? "켜짐" : "꺼짐") (바꾸려면 설정 > 노트)")
                }
            } else {
                labeled("잠금 비밀번호") { ThemedTextField(prompt: "4자 이상", text: $pw, secure: true) }
                labeled("한 번 더") { ThemedTextField(prompt: "", text: $pw2, secure: true) }
                line("비밀번호를 잊으면 잠긴 메모는 되살릴 수 없어요.", .orange)
                if NotesModel.touchIDAvailable {
                    check($touchOn, "Touch ID 로도 열기", "지문으로 열 수 있게 메모 열쇠를 2단계에서 고른 곳에 보관해요.")
                }
                if !notesErr.isEmpty { line(notesErr, .red) }
            }
        }
        .disabled(busy)
    }

    private func nextNotes() async {
        guard !hasLock else { advance(); return }
        busy = true; defer { busy = false }
        notesErr = ""
        do {
            try await state.notes.createPassword(pw, confirm: pw2)
            lockMade = true
            if touchOn, NotesModel.touchIDAvailable { try await state.notes.enableTouchID(password: pw) }
        } catch {
            // 비밀번호는 만들어졌는데 Touch ID 만 실패한 경우도 여기로 온다 (비밀번호는 유지, 설정에서 다시 켤 수 있음).
            notesErr = error.localizedDescription
            pw = ""; pw2 = ""
            state.notes.relockAll()
            if lockMade { notesErr += " — 비밀번호는 만들어졌어요. Touch ID 는 설정 > 노트에서 켤 수 있어요." }
            return
        }
        pw = ""; pw2 = ""
        state.notes.relockAll()   // 열쇠가 메모리에 남지 않게
        advance()
    }

    // MARK: - PR 연결

    private var prStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("PR 연결", "GitHub 는 gh CLI 로그인을 그대로 써요. Bitbucket 은 API 토큰이 필요해요. 둘 다 읽기만 해요.")
            if let bb {
                PROnboardingBody(pr: state.pr, bb: bb, github: $prGitHubOn, bitbucket: $prBitbucketOn, card: { c in AnyView(card { c }) })
            } else {
                ProgressView().controlSize(.small)
            }
            if !prErr.isEmpty { line(prErr, .red) }
        }
        .disabled(busy)
    }

    private func nextPR() async {
        busy = true; defer { busy = false }
        prErr = ""
        let s = Settings.shared
        // Bitbucket 은 연결 확인이 성공해야 켠다 (확인 전에는 이메일·켜짐 상태를 저장하지 않는다).
        if prBitbucketOn, let bb, !bb.ok {
            await bb.test()
            if !bb.ok { prErr = "Bitbucket 연결을 확인하지 못했어요. 이메일·토큰을 고치거나 Bitbucket 을 끄고 다음으로 가세요."; return }
        }
        s.prGitHubEnabled = prGitHubOn
        s.prBitbucketEnabled = prBitbucketOn
        advance()
    }

    private var prReposStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("리뷰 요청 볼 저장소", "Bitbucket 은 저장소 단위로 리뷰 요청을 찾아요. 이 Mac 에 클론된 저장소와 최근 리뷰어로 들어간 저장소를 미리 골라 뒀어요.")
            BitbucketRepoPicker(pr: state.pr, workspace: Settings.shared.prBitbucketWorkspace, selection: $prRepos)
                .frame(height: 300)
        }
    }

    private func savePRRepos() { Settings.shared.prBitbucketRepoList = Array(prRepos) }

    // MARK: - 5 Claude 연동

    private var claudeStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: 0).onAppear {
                let ig = integration
                hookInstalled = ig.hookStatus() == .installed && ig.skillInstalled()
                todoInstalled = ig.todoSkillInstalled()
                wantHook = !hookInstalled
                wantTodoSkill = !todoInstalled
            }
            header("Claude 연동", "요약에 쓸 작업 기록을 Claude Code 에서 받아와요.")
            if let p = claudePathFound {
                line("claude 찾음 · \(p)", .green)
            } else if claudeSearched {
                line("Claude Code 가 없어요 — 설치 후 설정 > Claude 연동에서 이어서 할 수 있어요", .orange)
                Link("claude.com/claude-code ↗", destination: URL(string: "https://claude.com/claude-code")!).font(.system(size: 11 * scale))
            } else {
                ProgressView().controlSize(.small)
            }
            check($wantHook, hookInstalled ? "작업 기록 훅 다시 설치 (이미 설치됨)" : "작업 기록 훅 설치",
                  "Claude Code 로 한 작업을 기록해서 요약에 써요. ~/.claude/settings.json 은 백업한 뒤 추가해요. (/worklog 스킬도 함께 설치돼요)")
            check($wantTodoSkill, todoInstalled ? "할 일 추가 스킬 다시 설치 (이미 설치됨)" : "할 일 추가 스킬 설치",
                  "Claude Code 에 '할 일에 추가해' 라고 말하면 ATM 할 일로 들어가요.")
            HStack(spacing: 6) {
                Text("자동 요약 시각").font(.system(size: 12 * scale))
                Picker("", selection: $summaryHour) {
                    ForEach(15...21, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }.labelsHidden().frame(width: 70)
                Text(":")
                Picker("", selection: $summaryMinute) {
                    ForEach([0, 30], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }.labelsHidden().frame(width: 70)
            }
            if !claudeErr.isEmpty { line(claudeErr, .red) }
        }
        .disabled(busy)
    }

    /// 설정 > Claude 연동 과 같은 함수로 설치한다 (settings.json 은 ClaudeIntegration 이 백업).
    private func installClaude() {
        claudeErr = ""
        guard claudePathFound != nil else { advance(); return }   // claude 가 없으면 건드리지 않고 넘어간다
        let ig = integration
        do {
            if wantHook { try ig.installHook(); try ig.installSkill() }
            if wantTodoSkill { try ig.installTodoSkill() }
        } catch {
            claudeErr = "설치 실패: \(error)"
            return
        }
        advance()
    }

    // MARK: - 6 Teleport

    @ViewBuilder
    private var teleportStep: some View {
        if let m = tp {
            TeleportOnboardingBody(m: m, tsh: state.teleport.tshPath, tshVersion: tshVersion, scale: scale)
        }
    }

    // MARK: - 7 마무리

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("거의 다 됐어요", "마지막으로 모양과 단축키를 골라요. 모두 설정에서 다시 바꿀 수 있어요.")
            labeled("테마") { ThemeColorPicker() }
            Toggle("전역 단축키로 패널 열기/닫기", isOn: $hotKeyOn).font(.system(size: 12 * scale))
            if hotKeyOn { HotKeyRecorder() }
            Toggle("로그인할 때 ATM 자동 실행", isOn: $loginAtStart)
                .font(.system(size: 12 * scale))
                .disabled(!isBundled)
                .onChange(of: loginAtStart) { _, on in setLogin(on) }
            if !isBundled { helper("앱 번들로 실행했을 때만 가능 (make install)") }
            if !finishErr.isEmpty { line(finishErr, .red) }
            card {
                VStack(alignment: .leading, spacing: 5) {
                    Text("준비된 것").font(.system(size: 12 * scale, weight: .semibold))
                    ForEach(summaryItems, id: \.self) { t in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(t).font(.system(size: 11.5 * scale))
                        }
                    }
                }
            }
        }
    }

    private var summaryItems: [String] {
        var r = ["탭: " + allTabs.filter { Onboarding.enabledTabs(summary: useSummary, notes: useNotes, teleport: useTeleport, pr: usePR).split(separator: ",").contains(Substring($0.id)) }.map(\.title).joined(separator: " · ")]
        if useJira || useNotes {
            r.append(atlOK ? "Atlassian 연결됨" : (hasToken ? "Atlassian 토큰 저장됨 (연결은 확인 안 함)" : "Atlassian 토큰 없음 — 설정 > Jira 에서 입력"))
        }
        if useNotes { r.append(hasLock ? "노트 잠금 설정됨" : "노트 잠금 안 씀") }
        if useSummary {
            let ig = integration
            r.append("Claude 훅 \(ig.hookStatus() == .installed ? "설치됨" : "미설치") · 할 일 스킬 \(ig.todoSkillInstalled() ? "설치됨" : "미설치")")
        }
        if usePR {
            var parts: [String] = []
            if prGitHubOn { if case .ok = state.pr.githubStatus { parts.append("GitHub ✓") } else { parts.append("GitHub (로그인 필요)") } }
            if prBitbucketOn { parts.append(bb?.ok == true ? "Bitbucket 저장소 \(Settings.shared.prBitbucketRepoList.count)개" : "Bitbucket 미연결") }
            r.append("PR: " + (parts.isEmpty ? "연결 안 함 — 설정 > PR 에서" : parts.joined(separator: " / ")))
        }
        if useTeleport { r.append(tpCount > 0 ? "Teleport DB \(tpCount)개" : "Teleport 미설정 — 탭에서 이어서 할 수 있어요") }
        return r
    }

    private func setLogin(_ on: Bool) {
        guard isBundled else { return }
        let current = SMAppService.mainApp.status == .enabled
        guard current != on else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            finishErr = ""
        } catch {
            finishErr = "로그인 항목 변경 실패: \(error.localizedDescription)"
            loginAtStart = current
        }
    }

    private func finish() {
        let s = Settings.shared
        s.enabledTabs = Onboarding.enabledTabs(summary: useSummary, notes: useNotes, teleport: useTeleport, pr: usePR)
        s.onboardingDone = true
        onClose()
        onFinish()
        if useJira { Task { await state.refreshJira() } }
        if useNotes { Task { await state.refreshConfluence() } }
        if usePR { Task { await state.pr.refresh() } }
    }
}

// MARK: - Teleport 단계 (TeleportSetupModel 재사용)

private struct TeleportOnboardingBody: View {
    @ObservedObject var m: TeleportSetupModel
    let tsh: String?
    let tshVersion: String
    let scale: Double
    @Environment(\.atmAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if m.step == 1 { login } else { dbs }
            if let e = m.error { Text(e).font(.system(size: 11 * scale)).foregroundStyle(.red).textSelection(.enabled) }
        }
        .disabled(m.busy)
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11 * scale, weight: .medium)).foregroundStyle(.secondary)
            c()
        }
    }

    private var login: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Teleport 로그인").font(.system(size: 16 * scale, weight: .medium))
                Text("한 번 입력해 두면 앱이 대신 로그인해요.").font(.system(size: 12 * scale)).foregroundStyle(.secondary)
            }
            if tsh != nil {
                Text(tshVersion.isEmpty ? "tsh 찾음" : "\(tshVersion) 찾음").font(.system(size: 11 * scale)).foregroundStyle(.green)
            } else {
                Text("tsh 가 없어요 — 터미널에서 brew install teleport 후 다시 시도해 주세요. 지금은 건너뛰고 나중에 Teleport 탭에서 이어서 할 수 있어요.")
                    .font(.system(size: 11 * scale)).foregroundStyle(.orange)
            }
            field("프록시 주소") { ThemedTextField(prompt: "teleport.example.com", text: $m.proxy) }
            field("아이디") { ThemedTextField(prompt: "Teleport 계정 (DB 사용자 developer 아님)", text: $m.user) }
            field("비밀번호") { ThemedTextField(prompt: m.hasSavedSecrets ? "저장됨 · 바꾸려면 입력" : "", text: $m.password, secure: true) }
            field("OTP 키") {
                HStack(spacing: 8) {
                    ThemedTextField(prompt: m.hasSavedSecrets ? "저장됨 · 바꾸려면 입력" : "base32 키 또는 otpauth:// URL", text: $m.otpKey, secure: true)
                    Button { m.readQR() } label: { AccentChip(icon: "qrcode.viewfinder", text: "QR 읽기", style: .soft) }.buttonStyle(.plain)
                }
                Text("Google OTP 등록할 때 받은 긴 영문 키예요 (QR 아래 '키 직접 입력'). QR 이미지가 있으면 [QR 읽기]")
                    .font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
                // 넣은 키가 맞는지 OTP 앱 숫자와 바로 비교할 수 있게 (Teleport 설정 화면과 같다)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    if let t = TOTP(input: m.otpKey) {
                        let c = t.code(at: ctx.date)
                        Text("현재 코드 \(c.prefix(3)) \(c.suffix(3)) · OTP 앱 숫자와 같으면 맞게 들어간 거예요")
                            .font(.system(size: 11 * scale, weight: .medium)).monospacedDigit().foregroundStyle(.green)
                    }
                }
                Link("OTP 키를 모르면: OTP 키 구하는 법 ↗", destination: Links.otpKeyGuide).font(.system(size: 11 * scale))
            }
            Text("입력한 값은 2단계에서 고른 곳에만 저장돼요. 매번 OTP 를 칠 필요 없이 앱이 대신 로그인해요.")
                .font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
        }
    }

    /// teleport.json 에 적은 그룹(없으면 이름의 첫 토큰)별로 묶는다. 순서는 tsh 가 준 순서.
    private var groups: [(name: String, ids: [String])] {
        var order: [String] = [], map: [String: [String]] = [:]
        for e in m.entries {
            let g = m.displayGroup(e.name)
            if map[g] == nil { order.append(g) }
            map[g, default: []].append(e.id)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private var dbs: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DB 고르기").font(.system(size: 16 * scale, weight: .medium))
                if !m.entries.isEmpty {
                    Text("로그인 성공 · 접근 가능한 DB \(m.entries.count)개").font(.system(size: 11 * scale)).foregroundStyle(.green)
                }
                Text("고른 DB 는 앱이 켜져 있는 동안 아래 포트로 열어 둬요. DB 툴에서 localhost:포트 로 접속하면 돼요.")
                    .font(.system(size: 12 * scale)).foregroundStyle(.secondary)
            }
            if m.entries.isEmpty && !m.busy {
                Button { Task { await m.loadDBs() } } label: { AccentChip(icon: "arrow.clockwise", text: "다시 불러오기", style: .soft) }.buttonStyle(.plain)
            }
            let dup = m.duplicates
            ForEach(groups, id: \.name) { g in
                VStack(alignment: .leading, spacing: 4) {
                    groupToggle(g.name, g.ids)
                    ForEach(g.ids, id: \.self) { id in row(id, dup) }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }
            if m.entries.contains(where: { $0.checked && $0.isProd }) {
                Text("운영 DB 를 골랐어요. 조회만 하더라도 조심해 주세요.").font(.system(size: 11 * scale, weight: .medium)).foregroundStyle(.red)
            }
        }
    }

    private func groupToggle(_ name: String, _ ids: [String]) -> some View {
        let all = ids.allSatisfy { id in m.entries.first { $0.id == id }?.checked == true }
        return Button { ids.forEach { m.setChecked($0, !all) } } label: {
            HStack(spacing: 6) {
                Image(systemName: all ? "checkmark.square.fill" : "square").foregroundStyle(all ? accent : .secondary)
                Text(name).font(.system(size: 12 * scale, weight: .semibold))
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func row(_ id: String, _ dup: Set<Int>) -> some View {
        if let i = m.entries.firstIndex(where: { $0.id == id }) {
            let e = m.entries[i]
            HStack(spacing: 6) {
                Button { m.setChecked(id, !e.checked) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: e.checked ? "checkmark.square.fill" : "square").foregroundStyle(e.checked ? accent : .secondary)
                        Text(e.name).font(.system(size: 12 * scale))
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                if e.isProd {
                    Text("운영").font(.system(size: 10 * scale, weight: .semibold)).foregroundStyle(.red)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.red.opacity(0.14)))
                }
                Spacer()
                if e.checked {
                    Text("포트").font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                    ThemedTextField(prompt: "4306", text: $m.entries[i].portText).frame(width: 72)
                        .foregroundStyle(dup.contains(Int(e.portText) ?? -1) ? Color.red : Color.primary)
                }
            }
        }
    }
}

/// Teleport 단계의 아래 오른쪽 버튼들. 모델 상태(busy·step)를 봐야 해서 따로 둔다.
private struct TeleportFooter: View {
    @ObservedObject var m: TeleportSetupModel
    let skip: () -> Void
    let done: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if m.busy { ProgressView().controlSize(.small) }
            Button(action: skip) { AccentChip(icon: "forward", text: "건너뛰기", style: .plain) }.buttonStyle(.plain).disabled(m.busy)
            if m.step == 1 {
                // 이미 저장된 비밀번호·OTP 키가 있고 새로 입력하지 않았으면 그걸로 로그인해서 목록만 받는다.
                if m.hasSavedSecrets && m.password.isEmpty && m.otpKey.isEmpty {
                    Button { Task { await m.loadWithSaved() } } label: { AccentChip(icon: "person.badge.key", text: "저장된 정보로 DB 불러오기", style: .solid) }
                        .buttonStyle(.plain).disabled(m.busy)
                } else {
                    Button { Task { await m.next() } } label: { AccentChip(icon: "person.badge.key", text: "로그인하고 DB 불러오기", style: .solid) }
                        .buttonStyle(.plain).disabled(!m.canNext)
                }
            } else {
                Button {
                    m.save()
                    if m.error == nil { done() }
                } label: { AccentChip(icon: "chevron.right", text: "다음", style: .solid) }
                    .buttonStyle(.plain).disabled(!m.canSave || m.busy)
            }
        }
    }
}

// MARK: - PR 단계 본문 (GitHub·Bitbucket 카드)

private struct PROnboardingBody: View {
    @ObservedObject var pr: PRModel
    @ObservedObject var bb: BitbucketSetup
    @Binding var github: Bool
    @Binding var bitbucket: Bool
    let card: (AnyView) -> AnyView
    @Environment(\.fontScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            card(AnyView(VStack(alignment: .leading, spacing: 6) {
                Toggle("GitHub", isOn: $github).font(.system(size: 12.5 * scale, weight: .semibold))
                GitHubStatusLine(pr: pr)
            }))
            card(AnyView(VStack(alignment: .leading, spacing: 6) {
                Toggle("Bitbucket", isOn: $bitbucket).font(.system(size: 12.5 * scale, weight: .semibold))
                if bitbucket {
                    ThemedTextField(prompt: "이메일 (Atlassian 계정)", text: $bb.email)
                    HStack(spacing: 8) {
                        ThemedTextField(prompt: bb.hasToken ? "저장됨 · 바꾸려면 입력" : "API 토큰을 붙여넣으세요 (⌘V)", text: $bb.token, secure: true)
                        Link("토큰 만드는 법 ↗", destination: Links.bitbucketToken).font(.system(size: 11 * scale))
                    }
                    Text("Atlassian 계정 > 보안 > 범위가 있는 API 토큰 만들기 → 앱 Bitbucket → 읽기 권한 4개 (저장소·PR·계정·워크스페이스). 승인 버튼을 쓰려면 write:pullrequest:bitbucket 도 체크")
                        .font(.system(size: 10.5 * scale)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button { Task { await bb.test() } } label: { AccentChip(icon: "bolt.horizontal", text: "연결 확인", style: .soft) }
                            .buttonStyle(.plain).disabled(bb.busy)
                        if !bb.status.isEmpty {
                            Text(bb.status).font(.system(size: 11 * scale)).foregroundStyle(bb.ok ? Color.green : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if bb.workspaces.count > 1 {
                        Picker("워크스페이스", selection: Binding(get: { bb.workspace }, set: { bb.selectWorkspace($0) })) {
                            ForEach(bb.workspaces) { Text($0.name).tag($0.slug) }
                        }
                    }
                }
            }))
        }
    }
}
