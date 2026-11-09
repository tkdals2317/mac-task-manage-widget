import SwiftUI
import TaskWidgetCore

struct JiraSection: View {
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale
    @AppStorage(SettingsKey.jiraBaseURL) private var jiraBaseURL = Settings.defaultJiraBaseURL
    @AppStorage(SettingsKey.jiraRefreshMinutes) private var refreshMinutes = 5
    @AppStorage(SettingsKey.jiraVersionFilter) private var versionFilter = ""
    @AppStorage(SettingsKey.jiraGroupByVersion) private var groupByVersion = false

    private var filter: VersionFilter { VersionFilter(storage: versionFilter) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !state.jiraConfigured {
                HStack(spacing: 8) {
                    Button("설정에서 Jira 토큰 입력") {
                        NotificationCenter.default.post(name: .openSettings, object: nil)
                    }
                    Button("설정 도우미") {
                        NotificationCenter.default.post(name: .openOnboarding, object: nil)
                    }
                    Link("토큰 발급 ↗", destination: Links.jiraToken)
                }
                .controlSize(.small)
                .font(.system(size: 11 * scale))
                .padding(.vertical, 8)
            } else {
                let filtered = JiraVersions.filter(state.jiraIssues, filter)
                let prefix = JiraVersions.commonPrefix(state.jiraIssues.flatMap(\.fixVersions))
                let mode: JiraRow.Trailing = filter != .all ? .none : (groupByVersion ? .status : .version)
                if groupByVersion {
                    ForEach(Array(JiraVersions.grouped(filtered).enumerated()), id: \.offset) { _, group in
                        groupHeader("\(group.title.map { JiraVersions.display($0, prefix: prefix) } ?? "버전 없음") · \(group.issues.count)")
                        ForEach(group.issues) { JiraRow(issue: $0, baseURL: jiraBaseURL, prefix: prefix, trailing: mode == .version ? .status : mode) }
                    }
                } else {
                    ForEach(JiraClient.grouped(filtered), id: \.status) { group in
                        groupHeader("\(group.status) · \(group.issues.count)")
                        ForEach(group.issues) { JiraRow(issue: $0, baseURL: jiraBaseURL, prefix: prefix, trailing: mode) }
                    }
                }
                if filtered.isEmpty && filter != .all && state.jiraError == nil && state.jiraUpdatedAt != nil {
                    Text("이 버전의 미완료 이슈 없음").font(.system(size: 11.5 * scale)).foregroundStyle(.secondary).padding(.vertical, 8)
                }
                if state.jiraIssues.isEmpty && filter == .all && state.jiraError == nil && state.jiraUpdatedAt != nil {
                    Text("미완료 이슈 없음").font(.system(size: 11.5 * scale)).foregroundStyle(.tertiary).padding(.vertical, 8)
                }
                if state.jiraTruncated {
                    Text("100건까지만 표시").font(.system(size: 10 * scale)).foregroundStyle(.secondary).padding(.top, 4)
                }
                footer
            }
        }
        .task(id: refreshMinutes) {
            await state.refreshJira()
            while !Task.isCancelled {
                // 취소되면 sleep 이 throw → 추가 요청 없이 종료
                guard (try? await Task.sleep(for: .seconds(max(1, refreshMinutes) * 60))) != nil else { break }
                // 패널이 orderOut 으로 숨겨져도 뷰는 살아 있으므로 보일 때만 호출 (스펙 6.2)
                guard NSApp.windows.contains(where: { $0 is FloatingPanel && $0.isVisible }) else { continue }
                await state.refreshJira()
            }
        }
    }

    private func groupHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5 * scale, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let e = state.jiraError {
                Text(e).foregroundStyle(.red).lineLimit(1)
                Button("설정") { NotificationCenter.default.post(name: .openSettings, object: nil) }
                    .controlSize(.mini)
            } else if let t = state.jiraUpdatedAt {
                Text("↻ \(t.formatted(date: .omitted, time: .shortened)) 갱신")
            }
            Spacer()
            if state.jiraLoading {
                ProgressView().controlSize(.small)
            }
        }
        .font(.system(size: 10.5 * scale))
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }
}

/// 상태 변경 팝오버: 맨 위에 지금 상태(✓), 아래에 바꿀 수 있는 상태를 종류 색 점과 함께.
/// 목록 조회 때 같이 받은 transitions 가 있으면 바로 보여주고, 없을 때만 따로 받는다.
/// (열린 NSMenu 는 비동기 로드 후 다시 그려지지 않아 팝오버를 쓴다.)
struct JiraTransitionPopover: View {
    @EnvironmentObject var state: AppState
    let issue: JiraIssue
    let close: () -> Void
    @State private var items: [JiraTransition]?
    @State private var error: String?
    @Environment(\.atmAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header("현재")
            row(issue.status, category: issue.statusCategory, current: true) {}
            header("바꾸기").padding(.top, 4)
            if let error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    .frame(maxWidth: 220, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 4)
            } else if let items = items ?? issue.transitions {
                let next = items.filter { $0.toName != issue.status }
                if next.isEmpty {
                    Text("가능한 전환 없음").font(.system(size: 12)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }
                ForEach(next) { t in
                    row(t.toName, category: t.toCategory, current: false) {
                        close()
                        Task { await state.transitionJira(issue.id, to: t) }
                    }
                }
            } else {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("불러오는 중…") }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
        }
        .padding(6)
        .frame(minWidth: 170, alignment: .leading)
        .themedPopover()
        .task {
            guard issue.transitions == nil else { return }
            do { items = try await state.loadTransitions(for: issue.id) }
            catch { self.error = (error as? JiraError)?.userMessage ?? error.localizedDescription }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 1)
    }

    private func row(_ name: String, category: String, current: Bool, _ action: @escaping () -> Void) -> some View {
        TransitionRow(name: name, color: JiraStatusColor.color(category, accent: accent), current: current, action: action)
    }
}

private struct TransitionRow: View {
    let name: String
    let color: Color
    let current: Bool
    let action: () -> Void
    @Environment(\.atmAccent) private var accent
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(name).font(.system(size: 12, weight: current ? .semibold : .regular))
                    .foregroundStyle(current ? accent : Color.primary)
                Spacer(minLength: 8)
                if current { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(accent) }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(
                current ? accent.opacity(0.16) : (hover ? Color.primary.opacity(0.07) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!current)   // disabled 는 흐리게 그려져서 지금 상태가 안 보인다
        .onHover { hover = $0 }
    }
}

/// 상태 종류(new / indeterminate / done)별 색. 상태 알약과 팝오버 점이 같은 색을 쓴다.
enum JiraStatusColor {
    static func color(_ category: String, accent: Color) -> Color {
        switch category {
        case "indeterminate": return accent
        case "done": return .green
        default: return .secondary
        }
    }
}

/// 상태 변경 버튼: 상태 종류(new / indeterminate / done)별 색 알약 + ▾.
struct JiraStatusPill: View {
    let status: String
    let category: String
    let action: () -> Void
    @Environment(\.fontScale) private var scale
    @Environment(\.atmAccent) private var accent
    @State private var hover = false

    private var tint: Color { JiraStatusColor.color(category, accent: accent) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(status).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8 * scale, weight: .bold))
            }
            .font(.system(size: 10.5 * scale, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(hover ? 0.26 : 0.16)))
            .overlay(Capsule().stroke(tint.opacity(0.25), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("상태 변경")
    }
}

struct JiraRow: View {
    @EnvironmentObject var state: AppState
    let issue: JiraIssue
    let baseURL: String
    var prefix = ""
    var trailing: Trailing = .none
    enum Trailing { case none, version, status }
    @State fileprivate var showTransitions = false
    @Environment(\.fontScale) private var scale
    @Environment(\.atmAccent) private var accent
    @AppStorage(SettingsKey.enabledTabs) private var enabledTabs = "tasks,summary"

    private var e2eOn: Bool { TabConfig.enabled(from: enabledTabs, all: allTabs.map(\.id)).contains("e2e") }

    var body: some View {
        HStack(spacing: 6) {
        Button {
            if let u = URL(string: "\(baseURL)/browse/\(issue.id)") {
                NSWorkspace.shared.open(u)
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(priorityColor).frame(width: 6, height: 6)
                Text(issue.id)
                    .font(.system(size: 11 * scale, design: .monospaced))
                    .foregroundStyle(accent)
                Text(issue.summary)
                    .font(.system(size: 12 * scale))
                    .lineLimit(1)
                    .truncationHelp(issue.summary)
                Spacer(minLength: 0)
                switch trailing {
                case .version:
                    if let tag = JiraVersions.tag(for: issue, prefix: prefix) {
                        Text(tag)
                            .font(.system(size: 10 * scale, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.78))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.09)))
                    }
                case .status:
                    EmptyView()
                case .none:
                    EmptyView()
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if e2eOn, let v = state.e2e.verdictByKey[issue.id] {
            Button {
                state.e2e.openJobId = v.jobId
                UserDefaults.standard.set("e2e", forKey: SettingsKey.lastTab)
            } label: { E2EVerdictBadge(verdict: v.verdict) }
                .buttonStyle(.plain)
                .help("최근 E2E 검증 결과 · 눌러서 보기")
        }
        if state.jiraBusyKeys.contains(issue.id) {
            ProgressView().controlSize(.mini)
        } else {
            JiraStatusPill(status: issue.status, category: issue.statusCategory) { showTransitions = true }
                .transitionAnchor(true, row: self)
        }
        }
        .contextMenu {
            Button("상태 변경…") { showTransitions = true }
        }
        Divider()
    }

    private var priorityColor: Color {
        switch issue.priority {
        case "Highest", "High": return .red
        case "Medium": return .orange
        default: return .gray
        }
    }
}

/// Jira 헤더의 버전 필터/묶기 메뉴 pill.
struct JiraVersionMenu: View {
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale
    @AppStorage(SettingsKey.jiraVersionFilter) private var stored = ""
    @AppStorage(SettingsKey.jiraGroupByVersion) private var groupBy = false

    private var filter: VersionFilter { VersionFilter(storage: stored) }

    var body: some View {
        if state.jiraConfigured {
            HStack(spacing: 3) {
                Menu { menuItems } label: { pill }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                if filter != .all {
                    Button { stored = "" } label: {
                        Image(systemName: "xmark").font(.system(size: 9 * scale, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("필터 해제")
                }
            }
        }
    }

    @ViewBuilder private var menuItems: some View {
        let c = JiraVersions.counts(state.jiraIssues)
        let prefix = JiraVersions.commonPrefix(c.versions.map(\.name))
        item("전체 (\(state.jiraIssues.count))", on: filter == .all, to: .all)
        ForEach(c.versions, id: \.name) { v in
            item("\(JiraVersions.display(v.name, prefix: prefix)) (\(v.count))", on: filter == .named(v.name), to: .named(v.name))
        }
        item("버전 없음 (\(c.noneCount))", on: filter == .none, to: .none)
        Divider()
        Toggle("버전별로 묶기", isOn: $groupBy)
    }

    private func item(_ title: String, on: Bool, to f: VersionFilter) -> some View {
        Toggle(title, isOn: Binding(get: { on }, set: { _ in stored = f.storage }))
    }

    private var pill: some View {
        let selected = filter != .all
        let label: String
        switch filter {
        case .all: label = groupBy ? "버전별" : "버전 전체"
        case .none: label = "버전 없음"
        case .named(let n): label = JiraVersions.display(n, prefix: JiraVersions.commonPrefix(state.jiraIssues.flatMap(\.fixVersions)))
        }
        return HStack(spacing: 3) {
            if filter == .all && groupBy { Image(systemName: "rectangle.split.1x2") }
            Text(label)
            if !selected { Image(systemName: "chevron.down").font(.system(size: 8 * scale)) }
        }
        .font(.system(size: 11 * scale))
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .padding(.horizontal, 7).padding(.vertical, 1)
        .background(Capsule().fill(selected ? Color.primary.opacity(0.14) : .clear))
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.5), lineWidth: selected ? 0 : 0.5))
    }
}


private extension View {
    /// 상태 변경 팝오버를 이 뷰 왼쪽에 띄운다. `on` 이 false 면 아무것도 안 붙인다.
    @ViewBuilder func transitionAnchor(_ on: Bool, row: JiraRow) -> some View {
        if on {
            popover(isPresented: row.$showTransitions, arrowEdge: .leading) {
                JiraTransitionPopover(issue: row.issue) { row.showTransitions = false }
            }
        } else { self }
    }
}
