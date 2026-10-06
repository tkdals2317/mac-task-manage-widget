import SwiftUI
import TaskWidgetCore

struct RootView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsKey.lastTab) private var tab = "tasks"
    @AppStorage(SettingsKey.fontScale) private var fontScale = 1.0
    @AppStorage(SettingsKey.panelCollapsed) private var collapsed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $tab) {
                    Text("할 일").tag("tasks")
                    Text("요약").tag("summary")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button {
                    NotificationCenter.default.post(name: .togglePanelCollapse, object: nil)
                } label: {
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                }
                .buttonStyle(.plain)
                .help(collapsed ? "펼치기" : "접기")
                Button {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("설정")
            }
            .padding(.leading, 26)   // 닫기 버튼 자리
            .padding(.trailing, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)
            if !collapsed {
                Divider()
                Group {
                    if tab == "summary" {
                        SummaryView()
                    } else {
                        TasksView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.fontScale, fontScale)
    }
}
