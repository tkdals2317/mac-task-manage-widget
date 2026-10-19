import SwiftUI

/// 테마 강조색 알약 버튼 모양 (노트 열기·지금 잠그기, Teleport 상단 버튼, 하위 할 일 개수 알약과 같은 톤).
/// soft: 옅은 강조 (기본), solid: 지금 눌러야 할 주 버튼, plain: 덜 중요한 버튼.
struct AccentChip: View {
    enum Style { case soft, solid, plain }
    let icon: String
    let text: String?
    var style: Style = .soft
    /// 자주 누르는 하단 버튼용 큰 크기 (요약 탭)
    var large = false
    @Environment(\.fontScale) private var scale
    @Environment(\.atmAccent) private var accent
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        HStack(spacing: large ? 4 : 3) {
            Image(systemName: icon).font(.system(size: (text == nil ? 12 : (large ? 11 : 9.5)) * scale, weight: .semibold))
            if let text { Text(text).font(.system(size: (large ? 12.5 : 11) * scale, weight: .medium)).lineLimit(1) }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, text == nil ? 6 : (large ? 11 : 8)).padding(.vertical, large ? 5 : 3)
        .background(Capsule().fill(background))
        .opacity(enabled ? 1 : 0.5)
        .contentShape(Capsule())
        .onHover { hover = $0 }
        .fixedSize()
    }

    private var foreground: Color {
        switch style {
        case .soft: return accent
        case .solid: return .white
        case .plain: return .secondary
        }
    }

    private var background: Color {
        let h = hover && enabled
        switch style {
        case .soft: return accent.opacity(h ? 0.26 : 0.16)
        case .solid: return accent.opacity(h ? 0.85 : 1)
        case .plain: return Color.primary.opacity(h ? 0.08 : 0)
        }
    }
}
