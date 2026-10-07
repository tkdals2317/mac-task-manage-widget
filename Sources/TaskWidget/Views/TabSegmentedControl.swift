import AppKit
import SwiftUI

/// macOS 버전마다 SwiftUI segmented Picker 폭이 다르다(14/15 는 글자 폭, 26 은 꽉 참).
/// NSSegmentedControl 을 직접 써서 어디서나 같은 폭으로 꽉 채운다.
struct TabSegmentedControl: NSViewRepresentable {
    let items: [(id: String, title: String)]
    @Binding var selection: String

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
