import SwiftUI
import TaskWidgetCore

struct RootView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsKey.lastTab) private var tab = "tasks"
    @AppStorage(SettingsKey.fontScale) private var fontScale = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $tab) {
                    Text("할 일").tag("tasks")
                    Text("요약").tag("summary")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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
    }
}
