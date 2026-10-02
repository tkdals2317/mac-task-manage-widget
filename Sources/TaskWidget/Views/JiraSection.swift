import SwiftUI
import TaskWidgetCore

struct JiraSection: View {
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale
    @AppStorage(SettingsKey.jiraBaseURL) private var jiraBaseURL = Settings.defaultJiraBaseURL
    @AppStorage(SettingsKey.jiraRefreshMinutes) private var refreshMinutes = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !state.jiraConfigured {
                Button("설정에서 Jira 토큰 입력") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .controlSize(.small)
                .padding(.vertical, 8)
            } else {
                ForEach(JiraClient.grouped(state.jiraIssues), id: \.status) { group in
                    Text("\(group.status) · \(group.issues.count)")
                        .font(.system(size: 10.5 * scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    ForEach(group.issues) { issue in
                        JiraRow(issue: issue, baseURL: jiraBaseURL)
                    }
                }
                if state.jiraIssues.isEmpty && state.jiraError == nil && state.jiraUpdatedAt != nil {
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
