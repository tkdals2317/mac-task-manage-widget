import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            Text("설정 (Task 17)")
            Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(width: 300, height: 160)
    }
}
