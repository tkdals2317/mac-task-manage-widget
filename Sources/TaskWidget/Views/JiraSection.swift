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
                Button("설정에서 Jira 토큰 입력") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .controlSize(.small)
                .padding(.vertical, 8)
            } else {
                let filtered = JiraVersions.filter(state.jiraIssues, filter)
                let mode: JiraRow.Trailing = filter != .all ? .none : (groupByVersion ? .status : .version)
                if groupByVersion {
                    ForEach(Array(JiraVersions.grouped(filtered).enumerated()), id: \.offset) { _, group in
                        groupHeader("\(group.title ?? "버전 없음") · \(group.issues.count)",
                                    color: group.title == nil ? .secondary : .purple)
                        ForEach(group.issues) { JiraRow(issue: $0, baseURL: jiraBaseURL, trailing: mode == .version ? .status : mode) }
                    }
                } else {
                    ForEach(JiraClient.grouped(filtered), id: \.status) { group in
                        groupHeader("\(group.status) · \(group.issues.count)", color: .secondary)
                        ForEach(group.issues) { JiraRow(issue: $0, baseURL: jiraBaseURL, trailing: mode) }
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

    private func groupHeader(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5 * scale, weight: .semibold))
            .foregroundStyle(color)
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

struct JiraRow: View {
    let issue: JiraIssue
    let baseURL: String
    var trailing: Trailing = .none
    enum Trailing { case none, version, status }
    @Environment(\.fontScale) private var scale

    var body: some View {
        Button {
            if let u = URL(string: "\(baseURL)/browse/\(issue.id)") {
                NSWorkspace.shared.open(u)
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(priorityColor).frame(width: 6, height: 6)
                Text(issue.id)
                    .font(.system(size: 11 * scale, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                Text(issue.summary)
                    .font(.system(size: 12 * scale))
                    .lineLimit(1)
                Spacer(minLength: 0)
                switch trailing {
                case .version:
                    if let tag = JiraVersions.tag(for: issue) {
                        Text(tag)
                            .font(.system(size: 11 * scale))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.purple.opacity(0.18)))
                    }
                case .status:
                    Text(issue.status).font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
                case .none:
                    EmptyView()
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(issue.summary)
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
        item("전체 (\(state.jiraIssues.count))", on: filter == .all, to: .all)
        ForEach(c.versions, id: \.name) { v in
            item("\(v.name) (\(v.count))", on: filter == .named(v.name), to: .named(v.name))
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
        case .named(let n): label = n
        }
        return HStack(spacing: 3) {
            if filter == .all && groupBy { Image(systemName: "rectangle.split.1x2") }
            Text(label)
            if !selected { Image(systemName: "chevron.down").font(.system(size: 8 * scale)) }
        }
        .font(.system(size: 11 * scale))
        .foregroundStyle(selected ? Color.purple : Color.secondary)
        .padding(.horizontal, 7).padding(.vertical, 1)
        .background(Capsule().fill(selected ? Color.purple.opacity(0.18) : .clear))
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.5), lineWidth: selected ? 0 : 0.5))
    }
}
