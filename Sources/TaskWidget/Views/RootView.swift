import SwiftUI
import TaskWidgetCore

struct RootView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsKey.lastTab) private var tab = "tasks"
    @AppStorage(SettingsKey.fontScale) private var fontScale = 1.0
    @State private var showSettings = false

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
                    NSApp.activate(ignoringOtherApps: true)
                    showSettings = true
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
        .environment(\.fontScale, fontScale)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            showSettings = true
        }
    }
}
