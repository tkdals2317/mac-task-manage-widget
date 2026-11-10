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
            case .ready(let path, let account, _):
                Text("✓ aside 준비됨 · \(account.isEmpty ? "로그인됨" : account)").foregroundStyle(.green)
                Text("\(path) (\(e2e.asideSource))").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            case .missing, .signedOut, .failed:
                Text(e2e.aside.problem ?? "").foregroundStyle(.orange).lineLimit(3)
            }
            Spacer(minLength: 4)
            if case .signedOut = e2e.aside {
                Button { e2e.openLoginTerminal() } label: { AccentChip(icon: "terminal", text: "터미널에서 로그인", style: .solid) }
                    .buttonStyle(.plain)
                    .help("ATM 이 찾은 aside 로 로그인 창을 열어요. Aside 설정 > 계정 > 기기에서 승인하면 자동으로 다시 확인해요.")
            }
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
    @AppStorage(SettingsKey.e2eAllowPR) private var allowPR = false

    var body: some View {
        Section("Aside CLI") {
            AsideStatusLine(e2e: e2e)
            TextField("aside 경로", text: $asidePath, prompt: Text("비우면 자동 탐색"))
                .onSubmit { Task { await e2e.checkAside() } }
            CommandCopyRow(label: "설치", command: AsideCLI.installCommand)
            CommandCopyRow(label: "로그인", command: AsideCLI.loginCommand)
            Text("Aside 브라우저를 설치해 켜 두세요. CLI 는 위 명령이나 Aside 설정 > 개발자에서 설치하고, 로그인이 필요하면 '터미널에서 로그인'을 눌러 이메일을 넣은 뒤 Aside 설정 > 계정 > 기기에서 승인해요. 터미널에서 aside 를 못 찾으면 ~/.local/bin/aside 로 실행해요.")
                .font(.caption).foregroundStyle(.secondary)
            Text("ATM 은 aside 를 guard 권한으로 실행해요. Aside 에이전트는 Aside 계정 폴더 안의 실행용 폴더(~/.aside/u/<계정>/atm-e2e)에서만 파일을 읽고 쓰고, 끝나면 ATM 이 스크린샷 이미지와 result.json 만 골라 가져와요. 다만 Aside 브라우저에 로그인된 사이트는 그대로 쓸 수 있으니 믿을 수 있는 이슈만 검증하세요.")
                .font(.caption).foregroundStyle(.orange)
        }
        Section {
            ForEach(E2EEnv.selectable(allowPR: allowPR)) { E2EEnvFields(env: $0) }
            Toggle("PR(운영) 환경 쓰기", isOn: $allowPR)
            Text("기본은 꺼져 있어요. 켜면 E2E 탭에 PR 이 보이고 실행 전에 한 번 더 물어요. '조회만' 은 Aside 에 주는 지시로만 지켜지니 운영 데이터가 바뀌어도 괜찮은 경우에만 켜세요.")
                .font(.caption).foregroundStyle(allowPR ? .orange : .secondary)
        } header: {
            Text("환경")
        } footer: {
            Text("테스트 계정 비밀번호는 ATM 이 Aside 에 넘기지 않아요. 주소 옆 'Aside 에서 열기'로 환경을 열어 직접 로그인하고 Aside Vault 에 저장해 두면 Aside 가 자동 채우기로 로그인해요. Vault 가 잠기면 로그인이 막히니 실행 전에 풀어 두세요. 계정 ID 를 넣으면 그 계정으로 로그인하라고 알려줘요.")
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

/// 환경 하나의 주소·테스트 계정 ID.
private struct E2EEnvFields: View {
    let env: E2EEnv
    @AppStorage private var url: String
    @AppStorage private var user: String

    init(env: E2EEnv) {
        self.env = env
        _url = AppStorage(wrappedValue: "", SettingsKey.e2eURL(env))
        _user = AppStorage(wrappedValue: "", SettingsKey.e2eUser(env))
    }

    var body: some View {
        let site = E2EWebURL.parse(Onboarding.normalizedURL(url))
        HStack(spacing: 6) {
            TextField("\(env.rawValue) 주소", text: $url, prompt: Text("https://\(env.rawValue.lowercased()).example.com"))
                .onSubmit { url = Onboarding.normalizedURL(url) }
            Button { if let site { AsideBrowser.open(site) } } label: {
                AccentChip(icon: "arrow.up.right.square", text: "Aside 에서 열기", style: .plain)
            }
            .buttonStyle(.plain)
            .disabled(site == nil || AsideBrowser.appURL == nil)
            .help("Aside 브라우저에서 이 환경을 열어 직접 로그인하고 Aside Vault 에 저장해 두세요")
        }
        TextField("\(env.rawValue) 계정 ID", text: $user, prompt: Text("비우면 Aside 에 저장된 로그인"))
        if env.forcesReadOnly {
            Text("PR 환경은 조회만 하라고 지시해요 (쓰기 동작은 SKIPPED)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
