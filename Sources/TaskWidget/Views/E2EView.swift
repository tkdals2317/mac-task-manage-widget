import AppKit
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
    @AppStorage(SettingsKey.jiraGroupByVersion) private var groupByVersion = false
    @AppStorage(SettingsKey.e2eIssuesCollapsed) private var issuesCollapsed = false
    @AppStorage(SettingsKey.e2eHistoryCollapsed) private var historyCollapsed = false
    @State private var confirmPR = false
    /// PR 환경 job 을 다시 실행하기 전 확인 중인 job id
    @State private var prRetry: String?
    @State private var commentTarget: E2ECommentTarget?
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
                E2ESetupSection(e2e: e2e, env: env).id(env)

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
            if e2e.report == nil { await e2e.checkAside() }
            if state.jiraUpdatedAt == nil { await state.refreshJira() }
        }
        .onAppear { e2e.reload() }
        .e2ePRConfirm(isPresented: $confirmPR) { submit() }
        .e2ePRConfirm(isPresented: Binding(get: { prRetry != nil }, set: { if !$0 { prRetry = nil } })) {
            if let id = prRetry { Task { _ = await e2e.retry(id) } }
        }
        .e2eCommentConfirm(e2e, target: $commentTarget)
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

    private func openSettings() { NotificationCenter.default.post(name: .openSettings, object: "e2e") }

    // MARK: - 이슈 선택

    @ViewBuilder
    private var issuePicker: some View {
        if !state.jiraConfigured {
            Text("Jira 를 연결하면 내 이슈에서 고를 수 있어요. 아래에 키를 직접 넣어도 돼요.")
                .font(.system(size: 11 * scale)).foregroundStyle(.secondary).padding(.vertical, 6)
        } else {
            let issues = JiraVersions.filter(state.jiraIssues, VersionFilter(storage: versionFilter))
            if groupByVersion {
                let prefix = JiraVersions.commonPrefix(state.jiraIssues.flatMap(\.fixVersions))
                ForEach(Array(JiraVersions.grouped(issues).enumerated()), id: \.offset) { _, group in
                    JiraGroupHeader(text: "\(group.title.map { JiraVersions.display($0, prefix: prefix) } ?? "버전 없음") · \(group.issues.count)")
                    ForEach(group.issues) { issueRow($0) }
                }
            } else {
                ForEach(issues) { issueRow($0) }
            }
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
            field("Aside 에 추가 요청사항 · 테스트 데이터, 허용할 동작", text: $e2e.draftNotes, focused: .notes)
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
            E2EHistoryRow(e2e: e2e, job: job, onRetry: { retry(job) },
                          onComment: { commentTarget = E2ECommentTarget(job: job, issue: $0) })
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

    /// Jira 댓글로 남기기 전 확인. 결과 폴더에 스크린샷이 있으면 같이 첨부할지도 고른다.
    @MainActor
    func e2eCommentConfirm(_ e2e: E2EModel, target: Binding<E2ECommentTarget?>) -> some View {
        confirmationDialog(target.wrappedValue.map { "\($0.issue.key) 이슈에 검증 결과를 댓글로 남길까요?" } ?? "",
                           isPresented: Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } }),
                           presenting: target.wrappedValue) { t in
            let shots = e2e.commentScreenshots(t.job.id, issue: t.issue).count
            if shots > 0 { Button("댓글 + 스크린샷 \(shots)장") { t.post(e2e, withScreenshots: true) } }
            Button(shots > 0 ? "댓글만 (스크린샷 없이)" : "댓글 남기기") { t.post(e2e, withScreenshots: false) }
            Button("취소", role: .cancel) {}
        } message: { t in
            Text("Jira 에 내 이름으로 댓글이 달리고, 이슈를 보는 사람에게 알림이 갈 수 있어요. 판정·시나리오·기대·실제 결과와 환경 주소가 들어가요."
                 + (e2e.commentScreenshots(t.job.id, issue: t.issue).isEmpty ? "" : "\n스크린샷은 이슈에 첨부되고 댓글 안 시나리오 아래에 이미지로 보여요.")
                 + (t.job.jiraComments[t.issue.key] == nil ? "" : "\n이 결과는 이미 한 번 남겼어요."))
        }
    }
}

/// Jira 댓글로 남길지 묻는 중인 결과.
struct E2ECommentTarget {
    let job: E2EJob
    let issue: E2EIssueResult

    @MainActor
    func post(_ e2e: E2EModel, withScreenshots: Bool) {
        let id = job.id, key = issue.key
        Task { await e2e.postComment(id, key: key, withScreenshots: withScreenshots) }
    }
}

/// 이력 한 줄. 누르면 결과 상세, 판정 옆에 Jira 댓글 · Jira 이슈 열기 · 다시 실행 버튼.
private struct E2EHistoryRow: View {
    @ObservedObject var e2e: E2EModel
    let job: E2EJob
    let onRetry: () -> Void
    let onComment: (E2EIssueResult) -> Void
    @Environment(\.fontScale) private var scale
    private typealias IssueLink = (key: String, title: String, url: URL)

    var body: some View {
        let issues = e2e.commentableIssues(job)
        let links = job.issues.compactMap { r in r.webURL.map { (key: r.key, title: r.title, url: $0) } }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // 다 들어가면 한 줄, 아니면 판정·버튼을 둘째 줄로 내린다 (기본 폭 320 에서 줄이 넘치면 패널 전체가 잘린다)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        openButton {
                            HStack(spacing: 6) { title; Spacer(minLength: 4); E2EJobStatusView(e2e: e2e, job: job) }
                                .padding(.vertical, 5)
                        }
                        HStack(spacing: 2) { actions(issues, links: links) }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        openButton { HStack(spacing: 6) { title; Spacer(minLength: 0) }.padding(.top, 5) }
                        HStack(spacing: 6) {
                            openButton { HStack { Spacer(minLength: 0); E2EJobStatusView(e2e: e2e, job: job) } }
                            HStack(spacing: 2) { actions(issues, links: links) }
                        }
                        .padding(.bottom, 4)
                    }
                }
                if let note = commentNote(issues) {
                    Text(note).font(.system(size: 10.5 * scale)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .padding(.bottom, 4)
                }
            }
            .contextMenu { menu(issues, links: links) }
            Divider()
        }
    }

    private var title: some View {
        HStack(spacing: 6) {
            Text(job.createdAt.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute()))
                .font(.system(size: 10.5 * scale)).foregroundStyle(.secondary).monospacedDigit()
            E2EEnvTag(env: job.env)
            Text(job.issueKeys.joined(separator: ", ")).font(.system(size: 11.5 * scale)).lineLimit(1)
        }
    }

    private func openButton<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        Button { e2e.openJobId = job.id } label: { label().contentShape(Rectangle()) }
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actions(_ issues: [E2EIssueResult], links: [IssueLink]) -> some View {
        if !e2e.isActive(job.id) { commentButton(issues) }
        jiraButton(links)
        if e2e.isActive(job.id) {
            Button { e2e.cancel(job.id) } label: { AccentChip(icon: "xmark.circle", text: nil, style: .plain) }
                .buttonStyle(.plain).help("취소")
        } else if job.status == .failed || job.status == .cancelled {
            Button(action: onRetry) { AccentChip(icon: "arrow.clockwise", text: nil, style: .soft) }
                .buttonStyle(.plain).help("다시 실행 (지금 고른 모델로)")
        }
    }

    /// 주소는 ATM 이 만든 Jira 링크만 쓴다. 이슈가 하나면 바로 열고, 여럿이면 메뉴에서 고른다.
    @ViewBuilder
    private func jiraButton(_ links: [IssueLink]) -> some View {
        let chip = AccentChip(icon: "arrow.up.right.square", text: nil, style: .plain)
        if links.count == 1, let link = links.first {
            Button { NSWorkspace.shared.open(link.url) } label: { chip }
                .buttonStyle(.plain).help("\(link.key) Jira 에서 열기")
        } else if !links.isEmpty {
            Menu {
                ForEach(links, id: \.key) { link in
                    Button(link.title.isEmpty ? link.key : "\(link.key) · \(link.title)") { NSWorkspace.shared.open(link.url) }
                }
            } label: { chip }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("이슈를 골라 Jira 에서 열기")
        }
    }

    /// 이슈가 하나면 바로 묻고, 여럿이면 메뉴에서 고른다. 다 남겼으면 체크 표시로 바뀐다.
    @ViewBuilder
    private func commentButton(_ issues: [E2EIssueResult]) -> some View {
        let done = !issues.isEmpty && issues.allSatisfy { job.jiraComments[$0.key] != nil }
        let chip = AccentChip(icon: done ? "checkmark.bubble" : "text.bubble", text: nil, style: done ? .plain : .soft)
        if issues.contains(where: { e2e.commenting == E2EModel.commentId(job.id, $0.key) }) {
            ProgressView().controlSize(.mini).frame(width: 24)
        } else if issues.count == 1, let issue = issues.first {
            Button { onComment(issue) } label: { chip }
                .buttonStyle(.plain).disabled(e2e.commenting != nil)
                .help(posted(issue.key).map { "\($0) Jira 댓글 남김 · 누르면 한 번 더 남겨요" } ?? "Jira 댓글로 남기기 (누르면 한 번 더 물어봐요)")
        } else if !issues.isEmpty {
            Menu {
                ForEach(issues, id: \.key) { i in
                    Button(menuTitle(i)) { onComment(i) }
                }
            } label: { chip }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .disabled(e2e.commenting != nil)
            .help("이슈를 골라 Jira 댓글로 남기기")
        }
    }

    @ViewBuilder
    private func menu(_ issues: [E2EIssueResult], links: [IssueLink]) -> some View {
        Button("결과 보기") { e2e.openJobId = job.id }
        ForEach(links, id: \.key) { link in
            Button(links.count == 1 ? "Jira 에서 열기" : "Jira 에서 열기 · \(link.key)") { NSWorkspace.shared.open(link.url) }
        }
        Button("Finder 에서 보기") { e2e.revealInFinder(job.id) }
        if e2e.isActive(job.id) {
            Button("취소") { e2e.cancel(job.id) }
        } else {
            Button("다시 실행", action: onRetry)
            ForEach(issues, id: \.key) { i in
                Button(issues.count == 1 ? "Jira 댓글로 남기기" : "Jira 댓글로 남기기 · \(menuTitle(i))") { onComment(i) }
                    .disabled(e2e.commenting != nil)
            }
            Button("파일로 내보내기") { e2e.exportReport(job.id) }
            Button("삭제") { e2e.delete(job.id) }
        }
    }

    private func menuTitle(_ issue: E2EIssueResult) -> String {
        let verdict = issue.verdict?.rawValue ?? "?"
        return posted(issue.key).map { "\(issue.key) · \(verdict) · \($0) 남김" } ?? "\(issue.key) · \(verdict)"
    }

    private func posted(_ key: String) -> String? {
        job.jiraComments[key].flatMap(E2EDate.parse)?.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
    }

    /// 이 줄의 댓글 시도가 실패했을 때 안내. 이슈가 여럿이면 어느 이슈인지 앞에 붙인다.
    private func commentNote(_ issues: [E2EIssueResult]) -> String? {
        guard let note = e2e.commentNote,
              let issue = issues.first(where: { E2EModel.commentId(job.id, $0.key) == note.id }) else { return nil }
        return issues.count == 1 ? note.text : "\(issue.key) · \(note.text)"
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
