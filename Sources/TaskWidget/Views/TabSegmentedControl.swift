import AppKit
import SwiftUI

/// macOS 버전마다 SwiftUI segmented Picker 폭이 다르다(14/15 는 글자 폭, 26 은 꽉 참).
/// NSSegmentedControl 을 직접 써서 어디서나 같은 폭으로 꽉 채운다.
struct TabSegmentedControl: NSViewRepresentable {
    let items: [(id: String, title: String)]
    @Binding var selection: String
    @Environment(\.atmThemed) private var themed
    @Environment(\.atmAccent) private var accent

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: items.map(\.title), trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if control.segmentCount != items.count {
            control.segmentCount = items.count
        }
        for (i, item) in items.enumerated() where control.label(forSegment: i) != item.title {
            control.setLabel(item.title, forSegment: i)
        }
        control.selectedSegmentBezelColor = themed ? NSColor(accent) : nil
        control.selectedSegment = items.firstIndex { $0.id == selection } ?? 0
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: TabSegmentedControl
        init(_ parent: TabSegmentedControl) { self.parent = parent }

        @objc func changed(_ sender: NSSegmentedControl) {
            let i = sender.selectedSegment
            guard parent.items.indices.contains(i) else { return }
            parent.selection = parent.items[i].id
        }
    }
}

/// 패널 탭 바. 테마 색을 쓰면 직접 그린 "옅은 강조" 탭(포커스를 잃어도 색 유지), 기본 테마면 macOS 기본 세그먼트.
struct PanelTabBar: View {
    let items: [(id: String, title: String)]
    @Binding var selection: String
    /// 탭 id → 배지 숫자 (0 이면 숨김)
    var badges: [String: Int] = [:]
    @Environment(\.atmThemed) private var themed

    var body: some View {
        if themed {
            SoftAccentTabBar(items: items, selection: $selection, badges: badges)
        } else {
            TabSegmentedControl(items: items, selection: $selection)
                // NSSegmentedControl 안에는 못 그려서 각 칸의 오른쪽 위에 겹쳐 놓는다.
                .overlay {
                    GeometryReader { g in
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            if let n = badges[item.id], n > 0 {
                                TabBadge(count: n)
                                    .position(x: g.size.width * CGFloat(i + 1) / CGFloat(items.count) - 14, y: g.size.height / 2)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
        }
    }
}

/// 탭 제목 옆의 작은 빨간 알약.
struct TabBadge: View {
    let count: Int
    @Environment(\.fontScale) private var scale

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9.5 * scale, weight: .semibold)).monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 4.5).frame(minWidth: 14 * scale, minHeight: 14 * scale)
            .background(Capsule().fill(Color.red))
    }
}

/// 선택된 탭에 강조색을 옅게 깔고 글자를 강조색으로. NSSegmentedControl 처럼 비활성 창에서 회색이 되지 않는다.
private struct SoftAccentTabBar: View {
    let items: [(id: String, title: String)]
    @Binding var selection: String
    var badges: [String: Int] = [:]
    @Environment(\.atmAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.fontScale) private var scale
    @State private var hovered: String?

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 2) {
            ForEach(items, id: \.id) { item in
                let on = item.id == selection
                Button { selection = item.id } label: {
                    HStack(spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 12.5 * scale, weight: on ? .medium : .regular))
                            .foregroundStyle(on ? (dark ? Color.white : accent) : Color.secondary)
                        if let n = badges[item.id], n > 0 { TabBadge(count: n) }
                    }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(on ? accent.opacity(dark ? 0.28 : 0.18)
                                         : (hovered == item.id ? Color.primary.opacity(0.06) : .clear))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(dark ? 0.06 : 0.05)))
    }
}
