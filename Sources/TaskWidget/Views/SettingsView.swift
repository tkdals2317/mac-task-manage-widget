import SwiftUI
import ServiceManagement
import TaskWidgetCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var state: AppState

    @AppStorage(SettingsKey.opacity) private var opacity = 1.0
    @AppStorage(SettingsKey.hoverOpaque) private var hoverOpaque = true
    @AppStorage(SettingsKey.theme) private var theme = "system"
    @AppStorage(SettingsKey.fontScale) private var fontScale = 1.0
    @AppStorage(SettingsKey.alwaysOnTop) private var alwaysOnTop = true
    @AppStorage(SettingsKey.allSpaces) private var allSpaces = true
    @AppStorage(SettingsKey.jiraBaseURL) private var jiraBaseURL = Settings.defaultJiraBaseURL
    @AppStorage(SettingsKey.jiraEmail) private var jiraEmail = ""
    @AppStorage(SettingsKey.jiraRefreshMinutes) private var jiraRefreshMinutes = 5
    @AppStorage(SettingsKey.jiraJQL) private var jiraJQL = ""
    @AppStorage(SettingsKey.summaryHour) private var summaryHour = 18
    @AppStorage(SettingsKey.summaryMinute) private var summaryMinute = 0
    @AppStorage(SettingsKey.summaryNotify) private var summaryNotify = true
    @AppStorage(SettingsKey.claudeModel) private var claudeModel = ""
    @AppStorage(SettingsKey.claudePath) private var claudePath = ""

    @State private var token = ""
    @State private var tokenStatus = ""
    @State private var loginAtStart = false
    @State private var hookStatus: HookStatus = .notInstalled
    @State private var skillInstalled = false
    @State private var integrationError = ""
    @State private var todayActivityCount = 0

    private var integration: ClaudeIntegration {
        ClaudeIntegration(executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0])
    }
    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("외관") {
                    Slider(value: $opacity, in: 0.6...1.0, step: 0.05) {
                        Text("투명도 \(Int((opacity * 100).rounded()))%")
                    }
                    Toggle("마우스 올리면 불투명", isOn: $hoverOpaque)
                    Picker("테마", selection: $theme) {
                        Text("시스템").tag("system")
                        Text("라이트").tag("light")
                        Text("다크").tag("dark")
                    }
                    Picker("글자 크기", selection: $fontScale) {
                        Text("작게").tag(0.9)
                        Text("보통").tag(1.0)
                        Text("크게").tag(1.15)
                    }
                }

                Section("창") {
                    Toggle("항상 위", isOn: $alwaysOnTop)
                    Toggle("모든 Spaces에 표시", isOn: $allSpaces)
                }

                Section("일반") {
                    Toggle("로그인 시 실행", isOn: $loginAtStart)
                        .disabled(!isBundled)
                        .onChange(of: loginAtStart) { _, on in setLogin(on) }
                    if !isBundled {
                        Text("앱 번들로 실행했을 때만 가능 (make install)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Jira") {
                    TextField("URL", text: $jiraBaseURL)
                    TextField("이메일", text: $jiraEmail)
                    HStack {
                        SecureField("API 토큰 (저장 후 비워짐)", text: $token)
                        Button("저장") { saveToken() }
                            .disabled(token.isEmpty || jiraEmail.isEmpty)
                    }
                    HStack {
                        Button("연결 테스트") { testJira() }
                        Text(tokenStatus).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Picker("갱신 주기", selection: $jiraRefreshMinutes) {
                        Text("1분").tag(1)
                        Text("5분").tag(5)
                        Text("15분").tag(15)
                    }
                    TextField("JQL (비우면 기본값)", text: $jiraJQL)
                }

                Section("요약") {
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
                    TextField("모델 (비우면 CLI 기본)", text: $claudeModel)
                    TextField("claude 경로 (비우면 자동 탐색)", text: $claudePath)
                }

                Section("Claude 연동") {
                    HStack {
                        Text("활동 훅")
                        Spacer()
                        Text("\(hookLabel) · 오늘 \(todayActivityCount)건").foregroundStyle(.secondary)
                        Button(hookButton) { toggleHook() }
                    }
                    HStack {
                        Text("/worklog 스킬")
                        Spacer()
                        Text(skillInstalled ? "설치됨" : "미설치").foregroundStyle(.secondary)
                        Button(skillInstalled ? "제거" : "설치") { toggleSkill() }
                    }
                    if !integrationError.isEmpty {
                        Text(integrationError).foregroundStyle(.red).font(.caption)
                    }
                    HStack {
                        Button("데이터 폴더 열기") { NSWorkspace.shared.open(Paths.dataDir) }
                        Button("요약 폴더 열기") { NSWorkspace.shared.open(Paths.summariesDir) }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(10)
        }
        .frame(width: 460, height: 600)
        .onAppear(perform: refreshStatus)
    }

    // MARK: - Actions

    private func refreshStatus() {
        hookStatus = integration.hookStatus()
        skillInstalled = integration.skillInstalled()
        todayActivityCount = ActivityLog.records(on: Date(), from: Paths.activityFile).count
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

    private func saveToken() {
        do {
            try Keychain.set(token, account: jiraEmail)
            token = ""
            tokenStatus = "저장됨"
            Task { await state.refreshJira() }
        } catch {
            tokenStatus = "저장 실패: \(error)"
        }
    }

    private func testJira() {
        guard let url = URL(string: jiraBaseURL), let t = Keychain.get(account: jiraEmail) else {
            tokenStatus = "토큰 없음"
            return
        }
        tokenStatus = "확인 중…"
        Task {
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
