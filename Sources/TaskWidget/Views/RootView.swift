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
        case "teleport": TeleportView(tp: state.teleport)
        default: TasksView()
        }
    }
}

/// 패널 타이틀바 오른쪽(신호등 버튼 줄)에 붙는 업데이트 버튼. 새 커밋이 있을 때만 보인다.
/// 하단 상태줄은 눈에 잘 안 띄고, 별도 줄을 만들면 아래 내용이 밀려서 타이틀바 빈 자리를 쓴다.
struct UpdateTitlebarButton: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            if let n = state.updateStatus?.behind, n > 0 {
                // 기본 버튼은 흰색이라 눈에 안 띈다. 작은 크기는 유지하고 강조 스타일(시스템 강조색)만 쓴다.
                Button(state.updating ? "업데이트 중…" : "업데이트") { Task { await state.startUpdate() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(state.updating)
                    .help("새 커밋 \(n)개 — 받아서 다시 설치합니다")
            }
        }
        // 패널 모서리에 붙지 않게 아래 탭 바와 같은 좌우 여백(10)을 주고, 신호등 버튼 높이에 맞춰 살짝 내린다.
        .padding(.trailing, 10)
        .padding(.top, 6)
        .frame(maxHeight: .infinity)
    }
}
