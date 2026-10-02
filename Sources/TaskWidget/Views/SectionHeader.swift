import SwiftUI

struct SectionHeader<Trailing: View>: View {
    let title: String
    let count: Int
    @Binding var collapsed: Bool
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.fontScale) private var scale

    init(title: String, count: Int, collapsed: Binding<Bool>, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.count = count
        self._collapsed = collapsed
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9 * scale, weight: .semibold))
                    Text(title).font(.system(size: 11 * scale, weight: .semibold))
                    Text("\(count)").font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            trailing()
        }
        .foregroundStyle(.secondary)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

/// trailing 없이 쓰는 호출용. 제네릭 기본 인자는 Swift 가 추론 못 하므로 extension 으로.
extension SectionHeader where Trailing == EmptyView {
    init(title: String, count: Int, collapsed: Binding<Bool>) {
        self.init(title: title, count: count, collapsed: collapsed) { EmptyView() }
    }
}
