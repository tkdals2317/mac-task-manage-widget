import SwiftUI
import AppKit

/// 복사했다는 걸 알려 주는 토스트. 복사 버튼을 눌러도 화면이 그대로라 됐는지 알기 어려워서 둔다.
@MainActor
final class CopyFeedback: ObservableObject {
    static let shared = CopyFeedback()

    /// 토스트 문구 (2초)
    @Published private(set) var toast: String?
    private var token = 0

    /// 클립보드에 쓰고 토스트를 띄운다. 새로 복사하면 앞의 토스트를 바꾼다.
    func copy(_ text: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        token += 1
        let t = token
        withAnimation(.easeOut(duration: 0.2)) { toast = message }
        let me = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard me.token == t else { return }
            withAnimation(.easeIn(duration: 0.25)) { me.toast = nil }
        }
    }
}

/// 내용 영역 아래쪽 가운데에 뜨는 토스트. 버튼 줄이 있는 탭은 그 위에 띄운다.
struct CopyToast: View {
    @ObservedObject private var fb = CopyFeedback.shared
    @Environment(\.fontScale) private var scale

    var body: some View {
        if let m = fb.toast {
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 10.5 * scale, weight: .bold))
                Text(m).font(.system(size: 12 * scale, weight: .medium))
            }
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.85)))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }
}
