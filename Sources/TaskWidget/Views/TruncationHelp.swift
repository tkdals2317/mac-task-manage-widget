import SwiftUI

/// 한 줄 텍스트가 "…" 로 잘렸을 때만 전체 문자열을 툴팁으로 보여준다.
/// 잘리지 않았으면 `hint` 만(없으면 툴팁 없음). 잘림 여부는 보이는 폭과 한 줄 전체 폭을 비교해 판단한다.
struct TruncationHelp: ViewModifier {
    let full: String
    var hint: String?
    @State private var shown: CGFloat = 0
    @State private var ideal: CGFloat = 0

    private var text: String? {
        let truncated = ideal > shown + 0.5
        switch (truncated, hint) {
        case (true, let h?): return "\(full)\n\n\(h)"
        case (true, nil): return full
        case (false, let h): return h
        }
    }

    func body(content: Content) -> some View {
        content
            .background(WidthReader { shown = $0 })
            .background(alignment: .leading) {
                content.fixedSize().hidden()
                    .background(WidthReader { ideal = $0 })
            }
            .help(text ?? "")
    }
}

/// 뷰의 폭을 알려준다. onGeometryChange 는 macOS 15 SDK(Xcode 16)에만 있어서 macOS 14 SDK 로도 빌드되게 GeometryReader 를 쓴다.
private struct WidthReader: View {
    let onWidth: (CGFloat) -> Void

    var body: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { onWidth(g.size.width) }
                .onChange(of: g.size.width) { _, w in onWidth(w) }
        }
    }
}

extension View {
    func truncationHelp(_ full: String, hint: String? = nil) -> some View {
        modifier(TruncationHelp(full: full, hint: hint))
    }
}
