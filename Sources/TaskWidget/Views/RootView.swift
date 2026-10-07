import SwiftUI
import TaskWidgetCore

struct RootView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsKey.lastTab) private var tab = "tasks"
    @AppStorage(SettingsKey.fontScale) private var fontScale = 1.0

    @AppStorage(SettingsKey.enabledTabs) private var enabledTabs = "tasks,summary"

    var body: some View {
        let enabled = TabConfig.enabled(from: enabledTabs, all: allTabs.map(\.id))
        let current = enabled.contains(tab) ? tab : enabled[0]
        VStack(spacing: 0) {
            if enabled.count > 1 {
                HStack(spacing: 8) {
                    TabSegmentedControl(
                        items: allTabs.filter { enabled.contains($0.id) }.map { ($0.id, $0.title) },
                        selection: Binding(get: { current }, set: { tab = $0 })
                    )
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 10)   // 아래 목록과 같은 좌우 여백
                .padding(.top, 8)
                .padding(.bottom, 6)
                Divider()
            }
            content(for: current)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                if let n = state.updateStatus?.behind, n > 0 {
                    Button("업데이트 있음 (\(n))") {
                        NotificationCenter.default.post(name: .openSettings, object: "about")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11 * fontScale))
                    .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13 * fontScale))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("설정")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.fontScale, fontScale)
        .onAppear { if tab != current { tab = current } }
        .onChange(of: enabledTabs) { _, _ in if tab != current { tab = current } }
    }

    @ViewBuilder
    private func content(for id: String) -> some View {
        switch id {
        case "summary": SummaryView()
        default: TasksView()
        }
    }
}
