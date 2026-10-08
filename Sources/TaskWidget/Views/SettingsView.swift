import SwiftUI
import ServiceManagement
import TaskWidgetCore

private enum Pane: String, CaseIterable, Identifiable {
    case appearance, window, tags, jira, summary, claude, teleport, about
    var id: Self { self }

    var title: String {
        switch self {
        case .appearance: return "외관"
        case .window: return "창 · 일반"
        case .tags: return "태그"
        case .jira: return "Jira"
        case .summary: return "요약"
        case .claude: return "Claude 연동"
        case .teleport: return "Teleport"
        case .about: return "정보"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintpalette"
        case .window: return "macwindow"
        case .tags: return "tag"
        case .jira: return "ticket"
        case .summary: return "doc.text"
        case .claude: return "sparkles"
        case .teleport: return "network"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    @AppStorage(SettingsKey.opacity) private var opacity = 1.0
    @AppStorage(SettingsKey.hoverOpaque) private var hoverOpaque = true
    @AppStorage(SettingsKey.theme) private var theme = "system"
    @AppStorage(SettingsKey.fontScale) private var fontScale = 1.0
    @AppStorage(SettingsKey.alwaysOnTop) private var alwaysOnTop = true
    @AppStorage(SettingsKey.allSpaces) private var allSpaces = true
    @AppStorage(SettingsKey.globalHotKeyEnabled) private var globalHotKey = true
    @AppStorage(SettingsKey.jiraBaseURL) private var jiraBaseURL = Settings.defaultJiraBaseURL
    @AppStorage(SettingsKey.jiraEmail) private var jiraEmail = ""
    @AppStorage(SettingsKey.jiraRefreshMinutes) private var jiraRefreshMinutes = 5
    @AppStorage(SettingsKey.jiraJQL) private var jiraJQL = ""
    @AppStorage(SettingsKey.summaryHour) private var summaryHour = 18
    @AppStorage(SettingsKey.summaryMinute) private var summaryMinute = 0
    @AppStorage(SettingsKey.summaryNotify) private var summaryNotify = true
    @AppStorage(SettingsKey.claudeModel) private var claudeModel = ""
    @AppStorage(SettingsKey.claudePath) private var claudePath = ""
    @AppStorage(SettingsKey.tshPath) private var tshPath = ""
    @AppStorage(SettingsKey.teleportAutoConnect) private var teleportAutoConnect = true
    @AppStorage(SettingsKey.enabledTabs) private var enabledTabs = "tasks,summary"
    @AppStorage(SettingsKey.sortTodosByTag) private var sortByTag = true
    @AppStorage(SettingsKey.summaryInstructions) private var summaryInstructions = ""
    @AppStorage(SettingsKey.secretStorage) private var secretStorage = "keychain"
    @State private var secretStatus = ""
    @State private var secretError = ""
    @State private var secretBusy = false
    @State private var instructionsDraft = ""
    @State private var confirmReset = false
    @State private var diagMessage = ""
    @State private var diagError = false
    @State private var diagBusy = false
    @State private var newTagId: String?

    @State private var pane: Pane
    @State private var token = ""
    @State private var tokenStatus = ""
    @State private var hasToken = false
    @State private var loginAtStart = false
    @State private var hookStatus: HookStatus = .notInstalled
    @State private var skillInstalled = false
    @State private var integrationError = ""
    @State private var claudeFound: (path: String, source: String)?
    @State private var claudeSearched = false
    @State private var claudeSearching = false
    @State private var todayActivityCount = 0
    @State private var supportLinkCopied = false

    init(initialPane: String? = nil) {
        _pane = State(initialValue: Pane(rawValue: initialPane ?? "") ?? .appearance)
    }

    private var integration: ClaudeIntegration {
        ClaudeIntegration(executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0])
    }
    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label {
                    HStack {
                        Text(p.title)
                        if p == .jira {
                            Spacer()
                            Circle().fill(hasToken ? Color.green : Color.secondary.opacity(0.4))
                                .frame(width: 7, height: 7)
                                .help(hasToken ? "토큰 저장됨" : "토큰 없음")
                        }
                    }
                } icon: {
                    Image(systemName: p.icon)
                }
                .tag(p)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            Form { detail }
                .formStyle(.grouped)
                .navigationTitle(pane.title)
        }
        .frame(minWidth: 620, minHeight: 440)
        .onAppear {
            refreshStatus()
            instructionsDraft = summaryInstructions.isEmpty ? SummaryPrompt.defaultInstructions : summaryInstructions
        }
        .onChange(of: jiraEmail) { _, _ in refreshStatus() }
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .appearance: appearancePane
        case .window: windowPane
        case .tags: tagsPane
        case .jira: jiraPane
        case .summary: summaryPane
        case .claude: claudePane
        case .teleport: teleportPane
        case .about: aboutPane
        }
    }

    // MARK: - Panes

    @ViewBuilder
    private var appearancePane: some View {
        Section {
            LabeledContent("투명도") {
                HStack {
                    Slider(value: $opacity, in: 0.6...1.0, step: 0.05)
                    Text("\(Int((opacity * 100).rounded()))%")
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }
            }
            Toggle("마우스 올리면 불투명", isOn: $hoverOpaque)
        }
        Section {
            Picker("테마", selection: $theme) {
                Text("시스템").tag("system")
                Text("라이트").tag("light")
                Text("다크").tag("dark")
            }
            .pickerStyle(.segmented)
            Picker("글자 크기", selection: $fontScale) {
                Text("작게").tag(0.9)
                Text("보통").tag(1.0)
                Text("크게").tag(1.15)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var windowPane: some View {
        Section("창") {
            Toggle("항상 위", isOn: $alwaysOnTop)
            Toggle("모든 Spaces에 표시", isOn: $allSpaces)
            Toggle("전역 단축키 ⌃⌥Space 로 패널 열기/닫기", isOn: $globalHotKey)
        }
        Section("탭") {
            let ids = allTabs.map(\.id)
            let enabled = TabConfig.enabled(from: enabledTabs, all: ids)
            ForEach(allTabs, id: \.id) { t in
                let isOn = enabled.contains(t.id)
                Toggle(t.title, isOn: Binding(
                    get: { isOn },
                    set: { _ in enabledTabs = TabConfig.toggled(t.id, in: enabledTabs, all: ids) }
                ))
                .disabled(enabled.count == 1 && isOn)
            }
            if enabled.count == 1 {
                Text("최소 1개는 켜져 있어야 합니다").font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("일반") {
            Toggle("로그인 시 실행", isOn: $loginAtStart)
                .disabled(!isBundled)
                .onChange(of: loginAtStart) { _, on in setLogin(on) }
            if !isBundled {
                Text("앱 번들로 실행했을 때만 가능 (make install)").font(.caption).foregroundStyle(.secondary)
            }
            if !integrationError.isEmpty {
                Text(integrationError).foregroundStyle(.red).font(.caption)
            }
        }
        Section("비밀 정보 저장") {
            Picker("저장 위치", selection: Binding(
                get: { secretStorage },
                set: { switchSecretStorage(to: $0) }
            )) {
                Text("키체인 (권장)").tag("keychain")
                Text("파일").tag("file")
            }
            .pickerStyle(.segmented)
            .disabled(secretBusy)
            if secretStorage == "file" {
                Text("Jira 토큰과 Teleport 비밀번호·OTP 키가 ~/Library/Application Support/TaskWidget/secrets.json 에 암호화 없이 저장돼요 (내 계정만 읽기 가능). 키체인 허용 창이 뜨지 않아요.")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text("업데이트·재설치 후 macOS가 한 번 허용을 물어요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !secretStatus.isEmpty {
                Text(secretStatus).font(.caption).foregroundStyle(.secondary)
            }
            if !secretError.isEmpty {
                Text(secretError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var secretWhere: String { secretStorage == "file" ? "secrets.json" : "키체인" }

    private func switchSecretStorage(to value: String) {
        guard value != secretStorage, let kind = SecretStorageKind(rawValue: value) else { return }
        secretBusy = true
        secretStatus = "옮기는 중…"
        secretError = ""
        Task {
            defer { secretBusy = false }
            do {
                let n = try await state.switchSecretStorage(to: kind)
                secretStatus = "옮김: \(n)개"
                refreshStatus()
            } catch {
                secretStatus = ""
                secretError = "저장 위치를 바꾸지 못했어요 (기존 설정 유지): \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private var teleportPane: some View {
        Section {
            LabeledContent("tsh") {
                if let p = state.teleport.tshPath {
                    Text(p).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                } else {
                    Link("설치 안 됨 · goteleport.com/download", destination: teleportDownloadURL)
                }
            }
            TextField("tsh 경로 (비우면 자동 탐색)", text: $tshPath)
                .onSubmit { state.teleport.locateTsh() }
            Button("다시 찾기") { state.teleport.locateTsh() }
        }
        Section {
            Toggle("ATM 시작 시 마지막에 켜 둔 DB 자동 연결", isOn: $teleportAutoConnect)
        }
        Section {
            Button("설정 다시 하기") {
                if !TabConfig.enabled(from: enabledTabs, all: allTabs.map(\.id)).contains("teleport") {
                    enabledTabs = TabConfig.toggled("teleport", in: enabledTabs, all: allTabs.map(\.id))
                }
                UserDefaults.standard.set("teleport", forKey: SettingsKey.lastTab)
                state.teleport.setupRequested = true
            }
            .disabled(state.teleport.tshPath == nil)
            Button("teleport.json 열기") {
                if !FileManager.default.fileExists(atPath: Paths.teleportFile.path) { try? state.teleport.config.save() }
                NSWorkspace.shared.open(Paths.teleportFile)
            }
            Text("탭이 꺼져 있으면 켜지고, Teleport 탭에서 설정이 이어집니다. 비밀번호·OTP 키는 \(secretWhere)에 저장돼요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tagsPane: some View {
        ForEach(Array(state.tagConfig.groups.enumerated()), id: \.element.id) { idx, group in
            Section {
                List {
                    ForEach(group.tags) { tag in
                        TagEditRow(tag: tag, focusOnAppear: tag.id == newTagId)
                    }
                    .onMove { state.moveTags(in: group.id, from: $0, to: $1) }
                }
                .frame(minHeight: CGFloat(max(group.tags.count, 1)) * 34 + 8)
                Button("＋ 태그") {
                    newTagId = state.addTag(toGroup: group.id, name: "새 태그", colorHex: TagColor.gray.hex).id
                }
            } header: {
                TagGroupHeader(group: group, isFirst: idx == 0, isLast: idx == state.tagConfig.groups.count - 1)
            }
        }
        Section {
            Button("＋ 그룹 추가") { state.addGroup() }
            Toggle("태그 순서로 정렬", isOn: $sortByTag)
            Button("기본값으로 되돌리기") { confirmReset = true }
        } footer: {
            Text("태그를 드래그해 그룹 안에서 순서를 바꿉니다. '정렬 기준' 그룹의 위쪽 태그가 먼저 정렬됩니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .alert("태그를 기본값으로 되돌릴까요?", isPresented: $confirmReset) {
            Button("되돌리기", role: .destructive) { state.resetTags() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("그룹과 태그가 초기화되고, 사라진 태그는 할 일에서 제거됩니다.")
        }
    }

    @ViewBuilder
    private var jiraPane: some View {
        Section("계정") {
            TextField("URL", text: $jiraBaseURL, prompt: Text("https://your-site.atlassian.net"))
            TextField("이메일", text: $jiraEmail, prompt: Text("name@company.com"))
            HStack {
                SecureField(hasToken ? "API 토큰 (저장됨 · 바꾸려면 입력)" : "API 토큰", text: $token)
                Button("저장") { saveToken() }   // 비활성화하지 않고 누르면 빠진 걸 알려준다
                Link("토큰 발급 ↗", destination: Links.jiraToken)
            }
            Text("Atlassian 계정 > 보안 > API 토큰에서 'API 토큰 만들기' 후 복사해 붙여넣으세요. 토큰은 \(secretWhere)에 저장돼요.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("연결 테스트") { testJira() }
                Text(tokenStatus).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        Section {
            Picker("갱신 주기", selection: $jiraRefreshMinutes) {
                Text("1분").tag(1)
                Text("5분").tag(5)
                Text("15분").tag(15)
            }
            .pickerStyle(.segmented)
            TextField("JQL", text: $jiraJQL, prompt: Text(JiraClient.defaultJQL), axis: .vertical)
                .lineLimit(2...4)
                .font(.system(.body, design: .monospaced))
        } header: {
            Text("동기화")
        } footer: {
            HStack {
                Text(jiraJQL.isEmpty ? "비워 두면 위 기본값으로 조회합니다." : "기본값: \(JiraClient.defaultJQL)")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
                if !jiraJQL.isEmpty {
                    Button("기본값으로") { jiraJQL = "" }.controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var summaryPane: some View {
        Section {
            HStack {
                Text("생성 시각")
                Spacer()
                Picker("", selection: $summaryHour) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                .labelsHidden().frame(width: 70)
                Text(":")
                Picker("", selection: $summaryMinute) {
                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                .labelsHidden().frame(width: 70)
            }
            Toggle("완료 알림", isOn: $summaryNotify)
        }
        Section {
            TextEditor(text: $instructionsDraft)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 220)
            HStack {
                Button("저장") { saveInstructions() }
                    .disabled(instructionsDraft == (summaryInstructions.isEmpty ? SummaryPrompt.defaultInstructions : summaryInstructions))
                Button("기본값으로 되돌리기") {
                    instructionsDraft = SummaryPrompt.defaultInstructions
                    summaryInstructions = ""
                }
                Spacer()
                Text(summaryInstructions.isEmpty ? "기본값 사용 중" : "사용자 지정")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("요약 프롬프트")
        } footer: {
            Text("`{날짜}`는 그날 날짜로 바뀝니다. 업무 일지·대화 기록·커밋 데이터는 이 지시문 뒤에 자동으로 붙습니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Claude CLI") {
            TextField("모델", text: $claudeModel, prompt: Text("비우면 CLI 기본"))
            TextField("claude 경로", text: $claudePath, prompt: Text("비우면 자동 탐색"))
            HStack {
                Button("자동 찾기") {
                    claudeSearching = true
                    Task.detached {
                        let r = ClaudeRunner.locateWithSource(configured: "")
                        await MainActor.run { claudeFound = r; claudeSearched = true; claudeSearching = false }
                    }
                }
                .disabled(claudeSearching)
                if claudeSearching { ProgressView().controlSize(.small) }
                else if let f = claudeFound {
                    Text("찾음: \(f.path) (\(f.source))").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("이 경로 사용") { claudePath = f.path }
                } else if claudeSearched {
                    Text("찾지 못함").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func exportDiagnostics() {
        let s = Settings.shared, tp = state.teleport
        let input = DiagnosticsExport.InfoInput(
            build: state.buildInfo, settings: s, teleport: tp.config, tshPath: tp.tshPath,
            claudePath: ClaudeRunner.locateWithSource(configured: s.claudePath)?.path,
            hasJiraToken: state.jiraConfigured, hasTeleportSecrets: tp.hasSecrets)
        diagBusy = true; diagMessage = ""
        Task {
            let r = await Task.detached { () -> Result<URL, Error> in
                Result {
                    let defaults = ProcessRunner.run(executable: "/usr/bin/defaults", arguments: ["read", DiagnosticsExport.defaultsDomain], timeout: 5).stdout
                    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                    return try DiagnosticsExport.export(to: desktop, info: DiagnosticsExport.infoText(input), defaults: defaults)
                }
            }.value
            diagBusy = false
            switch r {
            case .success(let url):
                diagError = false; diagMessage = "내보냄: \(url.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            case .failure(let e):
                diagError = true; diagMessage = "내보내기 실패: \((e as? TeleportError)?.message ?? e.localizedDescription)"
            }
        }
    }

    private var updateLog: URL { Paths.logsDir.appendingPathComponent("update.log") }

    @ViewBuilder
    private var aboutPane: some View {
        let info = state.buildInfo
        Section {
            LabeledContent("앱", value: "ATM (Ats Task Manager)")
            LabeledContent("버전", value: info.displayVersion)
            LabeledContent("빌드 날짜", value: info.buildDate)
            if !info.sourceDir.isEmpty {
                LabeledContent("소스 폴더") {
                    Text(info.sourceDir).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Finder에서 열기") { NSWorkspace.shared.open(URL(fileURLWithPath: info.sourceDir)) }
                }
            }
        }
        Section("업데이트") {
            if info.sourceDir.isEmpty {
                Text("소스 폴더 정보가 없습니다. 저장소에서 make install 로 다시 설치하세요.")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("업데이트 확인") {
                    if state.checkingUpdates { ProgressView().controlSize(.small) }
                    if let st = state.updateStatus {
                        Text(st.checkedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("업데이트 확인") { Task { await state.checkForUpdates() } }
                        .disabled(state.checkingUpdates || state.updating)
                }
                if let st = state.updateStatus {
                    if st.behind == 0 {
                        Text("최신 버전입니다 (\(info.version))").foregroundStyle(.secondary)
                    } else {
                        Text(st.notes.isEmpty ? "작은 수정 \(st.behind)개" : "새 버전 \(st.latestVersion ?? st.notes[0].version)")
                        if !st.notes.isEmpty {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(st.notes, id: \.version) { n in
                                        Text([n.version, n.date].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                        MarkdownText(markdown: n.body)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 220)
                        }
                        if state.updating {
                            Text("업데이트 중… 끝나면 앱이 다시 열립니다").foregroundStyle(.secondary)
                        }
                        Button("업데이트") { Task { await state.startUpdate() } }
                            .disabled(state.updating)
                    }
                }
            }
            if !info.sourceDir.isEmpty {
                let log = URL(fileURLWithPath: info.sourceDir).appendingPathComponent("CHANGELOG.md")
                Button("전체 업데이트 노트") { NSWorkspace.shared.open(log) }
                    .disabled(!FileManager.default.fileExists(atPath: log.path))
            }
            if let err = state.updateError {
                HStack {
                    Text(err).foregroundStyle(.red).font(.caption)
                    Spacer()
                    if FileManager.default.fileExists(atPath: updateLog.path) {
                        Button("로그 열기") { NSWorkspace.shared.open(updateLog) }
                    }
                }
            }
        }
        Section("문제 해결") {
            LabeledContent("진단 정보") {
                if diagBusy { ProgressView().controlSize(.small) }
                Button("진단 정보 내보내기") { exportDiagnostics() }.disabled(diagBusy)
            }
            if !diagMessage.isEmpty {
                Text(diagMessage).font(.caption).foregroundStyle(diagError ? .red : .secondary).textSelection(.enabled)
            }
            Text("로그와 설정 요약을 zip 으로 만들어요. 비밀번호·OTP·토큰은 들어가지 않아요. 이 파일을 개발자에게 보내 주세요.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("개발자 후원") {
            LabeledContent("카카오페이로 후원하기") {
                HStack {
                    Button("QR 열기 ↗") { NSWorkspace.shared.open(Links.kakaoPaySupportQR) }
                    Button(supportLinkCopied ? "복사됨" : "링크 복사") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Links.kakaoPaySupport, forType: .string)
                        supportLinkCopied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            supportLinkCopied = false
                        }
                    }
                }
            }
            Text("ATM이 도움이 됐다면 커피 한 잔 후원해 주세요 ☕")
                .font(.caption).foregroundStyle(.secondary)
            Text("브라우저에 뜬 QR을 휴대폰 카메라로 찍으면 카카오페이 송금 화면이 열립니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var claudePane: some View {
        Section {
            LabeledContent("활동 훅") {
                Text("\(hookLabel) · 오늘 \(todayActivityCount)건").foregroundStyle(.secondary)
                Button(hookButton) { toggleHook() }
            }
            LabeledContent("/worklog 스킬") {
                Text(skillInstalled ? "설치됨" : "미설치").foregroundStyle(.secondary)
                Button(skillInstalled ? "제거" : "설치") { toggleSkill() }
            }
            if !integrationError.isEmpty {
                Text(integrationError).foregroundStyle(.red).font(.caption)
            }
        }
        Section {
            HStack {
                Button("데이터 폴더 열기") { NSWorkspace.shared.open(Paths.dataDir) }
                Button("요약 폴더 열기") { NSWorkspace.shared.open(Paths.summariesDir) }
            }
        }
    }

    // MARK: - Actions

    private func refreshStatus() {
        hookStatus = integration.hookStatus()
        skillInstalled = integration.skillInstalled()
        todayActivityCount = ActivityLog.records(on: Date(), from: Paths.activityFile).count
        let email = jiraEmail
        Task {
            let t = email.isEmpty ? nil : await state.jiraToken(for: email)
            hasToken = t != nil
        }
        if isBundled { loginAtStart = SMAppService.mainApp.status == .enabled }
    }

    private func setLogin(_ on: Bool) {
        guard isBundled else { return }
        let current = SMAppService.mainApp.status == .enabled
        guard current != on else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            integrationError = "로그인 항목 변경 실패: \(error.localizedDescription)"
            loginAtStart = current
        }
    }

    private func saveInstructions() {
        let trimmed = instructionsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDefault = trimmed == SummaryPrompt.defaultInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        summaryInstructions = isDefault ? "" : instructionsDraft
        if isDefault { instructionsDraft = SummaryPrompt.defaultInstructions }
    }

    private func saveToken() {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if jiraEmail.trimmingCharacters(in: .whitespaces).isEmpty {
            tokenStatus = "이메일을 먼저 입력하세요"
            return
        }
        guard !t.isEmpty else {
            // 비밀번호 칸은 한글 입력 소스에서 타이핑이 안 들어간다. 붙여넣기는 된다.
            tokenStatus = "토큰이 비어 있음 — ⌘V로 붙여넣으세요"
            return
        }
        Task {
            do {
                try await state.setJiraToken(t, account: jiraEmail)
                token = ""
                tokenStatus = "저장됨"
                hasToken = true
                await state.refreshJira()
            } catch {
                tokenStatus = "저장 실패: \(error)"
            }
        }
    }

    private func testJira() {
        guard let url = URL(string: jiraBaseURL) else {
            tokenStatus = "토큰 없음"
            return
        }
        tokenStatus = "확인 중…"
        Task {
            guard let t = await state.jiraToken(for: jiraEmail) else {
                tokenStatus = "토큰 없음"
                return
            }
            do {
                tokenStatus = "OK: " + (try await JiraClient(baseURL: url, email: jiraEmail, token: t).whoAmI())
            } catch let e as JiraError {
                tokenStatus = e.userMessage
            } catch {
                tokenStatus = error.localizedDescription
            }
        }
    }

    private var hookLabel: String {
        switch hookStatus {
        case .installed: return "설치됨"
        case .notInstalled: return "미설치"
        case .pathMismatch: return "경로 불일치"
        }
    }

    private var hookButton: String {
        switch hookStatus {
        case .installed: return "제거"
        case .notInstalled: return "설치"
        case .pathMismatch: return "재설치"
        }
    }

    private func toggleHook() {
        do {
            if hookStatus == .installed { try integration.removeHook() } else { try integration.installHook() }
            integrationError = ""
        } catch {
            integrationError = "훅 변경 실패: \(error)"
        }
        refreshStatus()
    }

    private func toggleSkill() {
        do {
            if skillInstalled { try integration.removeSkill() } else { try integration.installSkill() }
            integrationError = ""
        } catch {
            integrationError = "스킬 변경 실패: \(error)"
        }
        refreshStatus()
    }
}

private struct TagGroupHeader: View {
    let group: TagGroup
    let isFirst: Bool
    let isLast: Bool
    @EnvironmentObject var state: AppState
    @State private var draft = ""
    @State private var confirmDelete = false
    @FocusState private var focused: Bool

    var body: some View {
        let isSort = state.tagConfig.sortGroup?.id == group.id
        HStack(spacing: 8) {
            TextField("그룹 이름", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, f in if !f { commit() } }
            Picker("", selection: Binding(
                get: { group.selection },
                set: { state.setSelection(group.id, $0) }
            )) {
                Text("하나만").tag(TagSelection.single)
                Text("여러 개").tag(TagSelection.multiple)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            Button { state.setSortGroup(group.id) } label: {
                Label("정렬 기준", systemImage: isSort ? "largecircle.fill.circle" : "circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSort ? Color.accentColor : Color.secondary)
            Menu {
                Button("위로 이동") { state.moveGroup(group.id, by: -1) }.disabled(isFirst)
                Button("아래로 이동") { state.moveGroup(group.id, by: 1) }.disabled(isLast)
                Divider()
                Button("삭제", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .onAppear { draft = group.name }
        .onChange(of: group.name) { _, n in draft = n }
        .alert("\"\(group.name)\" 그룹을 삭제할까요?", isPresented: $confirmDelete) {
            Button("삭제", role: .destructive) { state.deleteGroup(group.id) }
            Button("취소", role: .cancel) {}
        } message: {
            Text("그룹과 태그 \(group.tags.count)개가 삭제되고 할 일에서 빠집니다.")
        }
    }

    private func commit() {
        guard let name = Todo.normalizedTitle(draft) else { draft = group.name; return }
        if name != group.name { state.renameGroup(group.id, name) }
        draft = name
    }
}

private struct TagColorDot: View {
    let tag: Tag
    @EnvironmentObject var state: AppState
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            Circle().fill(Color(hex: tag.colorHex)).frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show) {
            HStack(spacing: 6) {
                ForEach(TagColor.allCases, id: \.self) { c in
                    Button { set(c.hex) } label: {
                        Circle().fill(Color(hex: c.hex)).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.primary, lineWidth: c.hex == tag.colorHex.uppercased() ? 2 : 0).padding(-2))
                    }
                    .buttonStyle(.plain)
                }
                ColorPicker("", selection: Binding(
                    get: { Color(hex: tag.colorHex) },
                    set: { if let h = $0.hexString { set(h) } }
                ), supportsOpacity: false)
                .labelsHidden()
            }
            .padding(10)
        }
    }

    private func set(_ hex: String) {
        var t = tag
        t.colorHex = hex
        state.updateTag(t)
    }
}

private struct TagEditRow: View {
    let tag: Tag
    let focusOnAppear: Bool
    @EnvironmentObject var state: AppState
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TagColorDot(tag: tag)

            TextField("", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, f in if !f { commit() } }

            Button { state.deleteTag(tag.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            draft = tag.name
            if focusOnAppear { DispatchQueue.main.async { focused = true } }
        }
        .onChange(of: tag.name) { _, n in draft = n }
    }

    private func commit() {
        guard let name = Todo.normalizedTitle(draft) else { draft = tag.name; return }
        if name != tag.name { var t = tag; t.name = name; state.updateTag(t) }
        draft = name
    }
}
