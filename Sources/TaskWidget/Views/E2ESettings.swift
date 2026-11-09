import SwiftUI
import TaskWidgetCore

/// Aside CLI 상태 한 줄 + 다시 확인. 설정과 설정 도우미가 같이 쓴다.
struct AsideStatusLine: View {
    @ObservedObject var e2e: E2EModel
    @Environment(\.fontScale) private var scale

    var body: some View {
        HStack(spacing: 8) {
            switch e2e.aside {
            case .unchecked, .checking:
                ProgressView().controlSize(.small)
                Text("Aside CLI 확인 중…").foregroundStyle(.secondary)
            case .ready(let path, let account):
                Text("✓ aside 준비됨 · \(account.isEmpty ? "로그인됨" : account)").foregroundStyle(.green)
                Text("\(path) (\(e2e.asideSource))").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            case .missing, .signedOut, .failed:
                Text(e2e.aside.problem ?? "").foregroundStyle(.orange).lineLimit(3)
            }
            Spacer(minLength: 4)
            Button { Task { await e2e.checkAside() } } label: { AccentChip(icon: "arrow.clockwise", text: "다시 확인", style: .soft) }
                .buttonStyle(.plain)
                .disabled(e2e.aside == .checking)
        }
        .font(.system(size: 11.5 * scale))
    }
}

/// 명령 한 줄 + 복사 버튼.
struct CommandCopyRow: View {
    let label: String
    let command: String
    @Environment(\.fontScale) private var scale

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 11 * scale)).foregroundStyle(.secondary)
            Text(command).font(.system(size: 11 * scale, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer(minLength: 4)
            Button { CopyFeedback.shared.copy(command, message: "명령을 복사했어요") } label: {
                AccentChip(icon: "doc.on.doc", text: "복사", style: .plain)
            }
            .buttonStyle(.plain)
        }
    }
}

/// 설정 > E2E
struct E2ESettingsSections: View {
    @ObservedObject var e2e: E2EModel
    @AppStorage(SettingsKey.e2eAsidePath) private var asidePath = ""
    @AppStorage(SettingsKey.e2eModel) private var model = ""
    @AppStorage(SettingsKey.e2eMinutesPerIssue) private var minutesPerIssue = 10
    @AppStorage(SettingsKey.e2eMaxMinutes) private var maxMinutes = 30
    @AppStorage(SettingsKey.e2eMaxIssues) private var maxIssues = 5
    @AppStorage(SettingsKey.e2eRetentionDays) private var retentionDays = 30

    var body: some View {
        Section("Aside CLI") {
            AsideStatusLine(e2e: e2e)
            TextField("aside 경로", text: $asidePath, prompt: Text("비우면 자동 탐색"))
                .onSubmit { Task { await e2e.checkAside() } }
            CommandCopyRow(label: "설치", command: AsideCLI.installCommand)
            CommandCopyRow(label: "로그인", command: AsideCLI.loginCommand)
            Text("Aside 브라우저를 설치하고 Jira·테스트 환경에 로그인해 두세요. CLI 는 위 명령이나 Aside 설정 > 개발자에서 설치하고, 로그인 후 Aside 설정 > 계정 > 기기에서 승인해요.")
                .font(.caption).foregroundStyle(.secondary)
            Text("ATM 은 aside 를 --permission full-access 로 실행해요. 기본 권한으로는 결과 폴더에 쓸 수 없어서예요. 실행하는 동안 Aside 에이전트가 이 Mac 의 파일에 접근할 수 있으니 믿을 수 있는 이슈만 검증하세요.")
                .font(.caption).foregroundStyle(.orange)
        }
        Section {
            ForEach(E2EEnv.allCases) { E2EEnvFields(env: $0) }
        } header: {
            Text("환경")
        } footer: {
            Text("비밀번호는 설정 > 창·일반 > 비밀 정보 저장에서 고른 곳(키체인 또는 파일)에 저장돼요. 실행하는 동안만 요청 파일에 들어가고 끝나면 지워요. 계정을 비우면 Aside 에 저장된 로그인을 써요.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("실행") {
            TextField("모델", text: $model, prompt: Text("비우면 Aside 기본 · 예: claude-sonnet-5"))
            Text("E2E 탭 실행 버튼 옆 메뉴에서도 고를 수 있어요. 메뉴에 없는 모델(provider/model)은 여기에 직접 넣어요.")
                .font(.caption).foregroundStyle(.secondary)
            Stepper("이슈당 제한 시간 \(minutesPerIssue)분", value: $minutesPerIssue, in: 1...30)
            Stepper("최대 제한 시간 \(maxMinutes)분", value: $maxMinutes, in: 5...120, step: 5)
            Stepper("한 번에 최대 \(maxIssues)건", value: $maxIssues, in: 1...20)
            Picker("결과 보관", selection: $retentionDays) {
                Text("7일").tag(7)
                Text("30일").tag(30)
                Text("90일").tag(90)
                Text("지우지 않음").tag(0)
            }
            Text("검증은 한 번에 하나씩 돌고, 실행 중에 요청하면 대기열에 쌓여요. 결과 폴더: \(Paths.e2eJobsDir.path)")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .task { if e2e.aside == .unchecked { await e2e.checkAside() } }
    }
}

/// 환경 하나의 주소·테스트 계정.
private struct E2EEnvFields: View {
    let env: E2EEnv
    @AppStorage private var url: String
    @AppStorage private var user: String
    @State private var password = ""
    @State private var hasPassword = false
    @State private var status = ""

    init(env: E2EEnv) {
        self.env = env
        _url = AppStorage(wrappedValue: "", SettingsKey.e2eURL(env))
        _user = AppStorage(wrappedValue: "", SettingsKey.e2eUser(env))
    }

    var body: some View {
        TextField("\(env.rawValue) 주소", text: $url, prompt: Text("https://\(env.rawValue.lowercased()).example.com"))
            .onSubmit { url = Onboarding.normalizedURL(url) }
        TextField("\(env.rawValue) 계정 ID", text: $user, prompt: Text("비우면 Aside 에 저장된 로그인"))
        HStack(spacing: 6) {
            SecureField("\(env.rawValue) 비밀번호", text: $password, prompt: Text(hasPassword ? "저장됨 · 바꾸려면 입력" : "비밀번호"))
                .onSubmit(save)
            Button("저장", action: save).disabled(password.isEmpty)
            if hasPassword { Button("지우기", action: remove) }
        }
        .task {
            let e = env
            hasPassword = await Task.detached { SecretStore.get(service: E2ESecrets.service, account: E2ESecrets.account(e)) != nil }.value
        }
        if !status.isEmpty || env.forcesReadOnly {
            Text([env.forcesReadOnly ? "PR 환경은 항상 조회만 해요 (쓰기 동작은 SKIPPED)" : nil, status.isEmpty ? nil : status]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard !password.isEmpty else { return }
        do {
            try SecretStore.set(password, service: E2ESecrets.service, account: E2ESecrets.account(env))
            password = ""
            hasPassword = true
            status = "비밀번호 저장됨"
        } catch {
            status = "저장 실패: \(error.localizedDescription)"
        }
    }

    private func remove() {
        SecretStore.delete(service: E2ESecrets.service, account: E2ESecrets.account(env))
        hasPassword = false
        status = "비밀번호 지움"
    }
}
