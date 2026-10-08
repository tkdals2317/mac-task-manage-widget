import SwiftUI

/// 줄 단위 간이 Markdown. `# `, `## `, `- `/`* ` 만 블록으로 처리, 나머지는 인라인 강조만.
struct MarkdownText: View {
    let markdown: String
    @Environment(\.fontScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.hasPrefix("# ") {
            Text(inline(String(line.dropFirst(2))))
                .font(.system(size: 14 * scale, weight: .bold))
                .padding(.bottom, 4)
        } else if line.hasPrefix("## ") {
            Text(inline(String(line.dropFirst(3))))
                .font(.system(size: 12.5 * scale, weight: .semibold))
                .padding(.top, 8)
        } else if line.hasPrefix("  - ") || line.hasPrefix("  * ") {
            // 한 단계 들여쓴 하위 항목
            HStack(alignment: .top, spacing: 6) {
                Text("◦")
                Text(inline(String(line.dropFirst(4))))
            }
            .font(.system(size: 12 * scale))
            .padding(.leading, 18)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                Text(inline(String(line.dropFirst(2))))
            }
            .font(.system(size: 12 * scale))
            .padding(.leading, 4)
        } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
            Color.clear.frame(height: 2)
        } else {
            Text(inline(line)).font(.system(size: 12 * scale))
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
