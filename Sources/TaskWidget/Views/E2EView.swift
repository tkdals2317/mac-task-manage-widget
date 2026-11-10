import SwiftUI
import TaskWidgetCore

/// E2E 탭: 이슈를 고르고 환경을 골라 Aside 로 검증을 돌린다. 결과를 누르면 같은 자리에서 상세로 바뀐다.
struct E2EView: View {
    @ObservedObject var e2e: E2EModel
    @EnvironmentObject var state: AppState

    var body: some View {
        if let id = e2e.openJobId, let job = e2e.job(id) {
            E2EResultView(e2e: e2e, job: job)
        } else {
            E2ERequestView(e2e: e2e)
        }
    }
}

private struct E2ERequestView: View {
    @ObservedObject var e2e: E2EModel
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale
    @Environment(\.atmAccent) private var accent
    @AppStorage(SettingsKey.e2eEnv) private var envRaw = E2EEnv.st.rawValue
    @AppStorage(SettingsKey.e2eAllowPR) private var allowPR = false
    @AppStorage(SettingsKey.jiraVersionFilter) private var versionFilter = ""
    @AppStorage(SettingsKey.e2eIssuesCollapsed) private var issuesCollapsed = false
    @AppStorage(SettingsKey.e2eHistoryCollapsed) private var historyCollapsed = false
    @State private var confirmPR = false
    /// PR 환경 job 을 다시 실행하기 전 확인 중인 job id
    @State private var prRetry: String?
    @FocusState private var focus: Field?
    private enum Field { case keys, notes }

    /// 저장된 환경이 지금 고를 수 없는 것(PR 을 끈 뒤)이면 ST 로 본다.
    private var env: E2EEnv {
        let e = E2EEnv(rawValue: envRaw) ?? .st
        return E2EEnv.selectable(allowPR: allowPR).contains(e) ? e : .st
    }

    /// 실행할 키: 목록에서 고른 것(목록 순서) → 목록에 없는 고른 것 → 직접 입력. 중복 없이.
    private var keys: [String] {
        let listed = state.jiraIssues.map(\.id), selected = e2e.draftSelected
        let ordered = listed.filter(selected.contains) + selected.subtracting(listed).sorted() + E2EIssueKeys.parse(e2e.draftKeys)
        var seen = Set<String>()
        return ordered.filter { seen.insert($0).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                envRow
                if let p = e2e.aside.problem, e2e.aside != .checking, e2e.aside != .unchecked { asideProblem(p) }

                SectionHeader(title: "이슈 선택", count: keys.count, collapsed: $issuesCollapsed) {
                    JiraVersionMenu()
                    Button { Task { await state.refreshJira() } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10 * scale))
                    }
                    .buttonStyle(.plain)
                    .help("Jira 새로고침")
                }
                if !issuesCollapsed { issuePicker }
                inputs
                runRow

                SectionHeader(title: "이력", count: e2e.jobs.count, collapsed: $historyCollapsed)
                if !historyCollapsed { history }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .themedScrollbar()
        .task {
            if e2e.aside == .unchecked { await e2e.checkAside() }
            if state.jiraUpdatedAt == nil { await state.refreshJira() }
        }
        .onAppear { e2e.reload() }
        .e2ePRConfirm(isPresented: $confirmPR) { submit() }
        .e2ePRConfirm(isPresented: Binding(get: { prRetry != nil }, set: { if !$0 { prRetry = nil } })) {
            if let id = prRetry { Task { _ = await e2e.retry(id) } }
        }
    }

    // MARK: - 환경

    private var envRow: some View {
        HStack(spacing: 6) {
            ForEach(E2EEnv.selectable(allowPR: allowPR)) { e in
                Button { envRaw = e.rawValue } label: {
                    AccentChip(icon: e == env ? "checkmark" : "circle", text: e.rawValue, style: e == env ? .soft : .plain)
                }
                .buttonStyle(.plain)
            }
            E2EEnvURL(env: env).id(env)
            Spacer(minLength: 0)
            Button { openSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 11 * scale))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("E2E 설정")
        }
        .padding(.top, 8)
    }

    private func asideProblem(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text).font(.system(size: 11 * scale)).foregroundStyle(.orange).lineLimit(3)
            Spacer(minLength: 4)
            Button { Task { await e2e.checkAside() } } label: { AccentChip(icon: "arrow.clockwise", text: "다시 확인", style: .soft) }
                .buttonStyle(.plain)
            Button { openSettings() } label: { AccentChip(icon: "gearshape", text: "설정", style: .plain) }
                .buttonStyle(.plain)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
        .padding(.top, 6)
    }

    private func openSettings() { NotificationCenter.default.post(name: .openSettings, object: "e2e") }

    // MARK: - 이슈 선택

    @ViewBuilder
    private var issuePicker: some View {
        if !state.jiraConfigured {
            Text("Jira 를 연결하면 내 이슈에서 고를 수 있어요. 아래에 키를 직접 넣어도 돼요.")
                .font(.system(size: 11 * scale)).foregroundStyle(.secondary).padding(.vertical, 6)
        } else {
            let issues = JiraVersions.filter(state.jiraIssues, VersionFilter(storage: versionFilter))
            ForEach(issues) { issueRow($0) }
            if issues.isEmpty && state.jiraUpdatedAt != nil {
                Text("보여줄 이슈가 없어요").font(.system(size: 11.5 * scale)).foregroundStyle(.tertiary).padding(.vertical, 6)
            }
            if let e = state.jiraError {
                Text(e).font(.system(size: 10.5 * scale)).foregroundStyle(.red).lineLimit(1).padding(.vertical, 4)
            }
        }
    }

    private func issueRow(_ issue: JiraIssue) -> some View {
        let on = e2e.draftSelected.contains(issue.id)
        return VStack(spacing: 0) {
            Button {
                if on { e2e.draftSelected.remove(issue.id) } else { e2e.draftSelected.insert(issue.id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: on ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(on ? accent : Color.secondary)
                    Text(issue.id).font(.system(size: 11 * scale, design: .monospaced)).foregroundStyle(accent)
                    Text(issue.summary).font(.system(size: 12 * scale)).lineLimit(1).truncationHelp(issue.summary)
                    Spacer(minLength: 0)
                    if let v = e2e.verdictByKey[issue.id] { E2EVerdictBadge(verdict: v.verdict) }
                    Text(issue.status).font(.system(size: 10 * scale)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
        }
    }

    // MARK: - 입력·실행

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 6) {
            field("이슈 키·링크 직접 입력 (쉼표·줄바꿈으로 여러 개)", text: $e2e.draftKeys, focused: .keys)
            field("메모 (선택) · 테스트 데이터, 허용하는 동작 등", text: $e2e.draftNotes, focused: .notes)
        }
        .padding(.top, 8)
    }

    private func field(_ placeholder: String, text: Binding<String>, focused: Field) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .font(.system(size: 12 * scale))
            .focused($focus, equals: focused)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(focus == focused ? accent : Color.primary.opacity(0.12), lineWidth: focus == focused ? 1.5 : 0.5))
    }

    private var runRow: some View {
        let n = keys.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(n == 0 ? "고른 이슈 없음" : keys.joined(separator: ", "))
                    .font(.system(size: 10.5 * scale)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                E2EModelMenu(e2e: e2e)
                if e2e.submitting { ProgressView().controlSize(.small) }
                Button {
                    if env == .pr { confirmPR = true } else { submit() }
                } label: {
                    AccentChip(icon: "play.fill", text: e2e.running == nil ? "검증 실행 (\(n)건)" : "대기열에 추가 (\(n)건)", style: .solid)
                }
                .buttonStyle(.plain)
                .disabled(n == 0 || e2e.submitting)
            }
            if let e = e2e.submitError {
                Text(e).font(.system(size: 11 * scale)).foregroundStyle(.red).lineLimit(3)
            }
            Text("실행하면 내 Aside 브라우저가 탭을 열어 직접 조작해요. 결과는 참고용 자동 검증이에요.")
                .font(.system(size: 10 * scale)).foregroundStyle(.tertiary)
        }
        .padding(.top, 8)
    }

    private func submit() {
        let titles = Dictionary(state.jiraIssues.map { ($0.id, $0.summary) }, uniquingKeysWith: { a, _ in a })
        let run = keys, memo = e2e.draftNotes, target = env
        Task { _ = await e2e.submit(env: target, keys: run, notes: memo, titles: titles) }
    }

    private func retry(_ job: E2EJob) {
        if job.env.forcesReadOnly { prRetry = job.id } else { Task { _ = await e2e.retry(job.id) } }
    }

    // MARK: - 이력

    @ViewBuilder
    private var history: some View {
        if e2e.jobs.isEmpty {
            Text("아직 실행한 검증이 없어요").font(.system(size: 11.5 * scale)).foregroundStyle(.tertiary).padding(.vertical, 6)
        }
        ForEach(e2e.jobs) { job in
            HStack(spacing: 6) {
                Button { e2e.openJobId = job.id } label: {
                    HStack(spacing: 6) {
                        Text(job.createdAt.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute()))
                            .font(.system(size: 10.5 * scale)).foregroundStyle(.secondary).monospacedDigit()
                        E2EEnvTag(env: job.env)
                        Text(job.issueKeys.joined(separator: ", ")).font(.system(size: 11.5 * scale)).lineLimit(1)
                        Spacer(minLength: 4)
                        E2EJobStatusView(e2e: e2e, job: job)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if e2e.isActive(job.id) {
                    Button { e2e.cancel(job.id) } label: {
                        Image(systemName: "xmark.circle").font(.system(size: 11 * scale))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("취소")
                } else if job.status == .failed || job.status == .cancelled {
                    Button { retry(job) } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11 * scale))
                    }
                    .buttonStyle(.plain).foregroundStyle(accent).help("다시 실행 (지금 고른 모델로)")
                }
            }
            .contextMenu {
                Button("결과 보기") { e2e.openJobId = job.id }
                Button("Finder 에서 보기") { e2e.revealInFinder(job.id) }
                if e2e.isActive(job.id) {
                    Button("취소") { e2e.cancel(job.id) }
                } else {
                    Button("다시 실행") { retry(job) }
                    Button("삭제") { e2e.delete(job.id) }
                }
            }
            Divider()
        }
    }
}

/// 실행에 쓸 Aside 모델 메뉴 (Jira 버전 메뉴와 같은 알약). 목록은 Aside 가 받아 둔 카탈로그, 없는 id 는 설정에서 직접 입력.
struct E2EModelMenu: View {
    @ObservedObject var e2e: E2EModel
    @AppStorage(SettingsKey.e2eModel) private var model = ""
    @Environment(\.fontScale) private var scale

    var body: some View {
        Menu {
            item("Aside 기본 모델", id: "")
            ForEach(groups) { group in
                Divider()
                Section(group.title) {
                    ForEach(group.models) { m in
                        let locked = m.needsPaidPlan && e2e.asidePlan.lowercased() == "free"
                        item(m.needsPaidPlan ? "\(m.name) · \(m.minPlan.capitalized)" : m.name, id: m.id).disabled(locked)
                    }
                }
            }
            if !model.isEmpty, !e2e.asideModels.contains(where: { $0.id == model }) {
                Divider()
                item(model, id: model)
            }
            Divider()
            Button("직접 입력…") { NotificationCenter.default.post(name: .openSettings, object: "e2e") }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "cpu").font(.system(size: 9.5 * scale))
                Text(model.isEmpty ? "기본 모델" : e2e.modelName(model)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8 * scale))
            }
            .font(.system(size: 11 * scale))
            .foregroundStyle(model.isEmpty ? Color.secondary : Color.primary)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(Capsule().fill(model.isEmpty ? Color.clear : Color.primary.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.5), lineWidth: model.isEmpty ? 0.5 : 0))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("검증에 쓸 Aside 모델")
    }

    private func item(_ title: String, id: String) -> some View {
        Toggle(title, isOn: Binding(get: { model == id }, set: { _ in model = id }))
    }

    /// Aside 제공 모델을 먼저, 내가 연동한 provider 모델은 이름순으로 나눈다.
    /// 한 줄 식으로 쓰면 Swift 5.10 타입 검사가 시간 초과로 실패한다.
    private var groups: [E2EModelGroup] {
        let byProvider: [String: [AsideModel]] = Dictionary(grouping: e2e.asideModels) { $0.provider }
        let providers: [String] = byProvider.keys.sorted { a, b in
            if a == E2EModelGroup.aside { return b != E2EModelGroup.aside }
            if b == E2EModelGroup.aside { return false }
            return a < b
        }
        return providers.map { E2EModelGroup(provider: $0, models: byProvider[$0] ?? []) }
    }
}

private struct E2EModelGroup: Identifiable {
    static let aside = "aside"
    let provider: String
    let models: [AsideModel]
    var id: String { provider }
    var title: String { provider == Self.aside ? "Aside 제공" : "연동: \(provider)" }
}

extension View {
    /// PR(운영) 환경 실행 전 확인.
    func e2ePRConfirm(isPresented: Binding<Bool>, action: @escaping () -> Void) -> some View {
        confirmationDialog("PR(운영) 환경에서 검증할까요?", isPresented: isPresented) {
            Button("조회만 하고 실행", action: action)
            Button("취소", role: .cancel) {}
        } message: {
            Text("운영 환경에서는 조회만 하고, 쓰기 동작이 필요한 시나리오는 SKIPPED 로 남겨요.")
        }
    }
}

/// 고른 환경의 주소 (설정 값이 바뀌면 바로 따라가도록 환경별 키를 직접 본다).
private struct E2EEnvURL: View {
    @AppStorage private var url: String
    @Environment(\.fontScale) private var scale

    init(env: E2EEnv) {
        _url = AppStorage(wrappedValue: "", SettingsKey.e2eURL(env))
    }

    var body: some View {
        Text(url.isEmpty ? "주소 없음" : url)
            .font(.system(size: 10.5 * scale))
            .foregroundStyle(url.isEmpty ? Color.orange : Color.secondary)
            .lineLimit(1).truncationMode(.middle)
            .help(url.isEmpty ? "설정 > E2E 에서 환경 주소를 넣어 주세요" : url)
    }
}
