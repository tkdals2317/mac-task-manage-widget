import AppKit
import SwiftUI

/// 줄 단위 간이 Markdown. `# `, `## `, `- `/`* `(한 단계 들여쓰기 포함) 만 블록으로 처리, 나머지는 인라인 강조만.
/// 줄마다 Text 를 따로 두면 선택이 한 줄 안에서만 되고, 틈에서 시작한 드래그는 패널을 움직인다.
/// 그래서 전체를 읽기 전용 NSTextView 하나로 그려 여러 줄 드래그·⌘A·⌘C 가 되게 한다.
struct MarkdownText: NSViewRepresentable {
    let markdown: String
    @Environment(\.fontScale) private var scale

    func makeNSView(context: Context) -> SelectableTextView {
        let v = SelectableTextView()
        v.isEditable = false
        v.isSelectable = true
        v.drawsBackground = false
        v.textContainerInset = .zero
        v.textContainer?.lineFragmentPadding = 0
        v.textContainer?.widthTracksTextView = true
        v.isVerticallyResizable = false
        v.isHorizontallyResizable = false
        return v
    }

    func updateNSView(_ v: SelectableTextView, context: Context) {
        let key = "\(scale)|\(markdown)"
        guard v.renderedKey != key else { return }
        v.renderedKey = key
        v.textStorage?.setAttributedString(Self.render(markdown, scale: scale))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: SelectableTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        guard let tc = v.textContainer, let lm = v.layoutManager else { return nil }
        tc.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        return CGSize(width: width, height: ceil(lm.usedRect(for: tc).height))
    }

    // MARK: - 렌더링

    static func render(_ markdown: String, scale: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 12 * scale)
        let lines = markdown.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            var text = line, font = body, prefix = "", indent: CGFloat = 0
            var before: CGFloat = 0, after: CGFloat = 3
            if line.hasPrefix("# ") {
                text = String(line.dropFirst(2)); font = .systemFont(ofSize: 14 * scale, weight: .bold); after = 7
            } else if line.hasPrefix("## ") {
                text = String(line.dropFirst(3)); font = .systemFont(ofSize: 12.5 * scale, weight: .semibold); before = 8
            } else if line.hasPrefix("  - ") || line.hasPrefix("  * ") {
                text = String(line.dropFirst(4)); prefix = "◦"; indent = 18
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                text = String(line.dropFirst(2)); prefix = "•"; indent = 4
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                text = ""; after = 0; font = .systemFont(ofSize: 2)   // 빈 줄은 기존처럼 얇은 간격만
            }

            // 글머리표 뒤 탭 위치에 둘째 줄부터 맞춘다 (기존 HStack 모양 유지)
            let p = NSMutableParagraphStyle()
            p.paragraphSpacingBefore = before
            p.paragraphSpacing = after
            if !prefix.isEmpty {
                let bulletW = (prefix as NSString).size(withAttributes: [.font: font]).width
                let textStart = indent + bulletW + 6
                p.firstLineHeadIndent = indent
                p.headIndent = textStart
                p.tabStops = [NSTextTab(textAlignment: .left, location: textStart)]
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: p]
            let para = NSMutableAttributedString(string: prefix.isEmpty ? "" : prefix + "\t", attributes: attrs)
            para.append(inline(text, base: attrs))
            if i < lines.count - 1 { para.append(NSAttributedString(string: "\n", attributes: attrs)) }
            out.append(para)
        }
        return out
    }

    /// **굵게**, *기울임*, `코드`, [링크](url) 만 적용한다.
    private static func inline(_ s: String, base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        guard let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: s, attributes: base)
        }
        let font = base[.font] as! NSFont
        let out = NSMutableAttributedString()
        for run in a.runs {
            var attrs = base
            let intent = run.inlinePresentationIntent ?? []
            var f = font
            if intent.contains(.stronglyEmphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
            if intent.contains(.code) { f = .monospacedSystemFont(ofSize: font.pointSize * 0.95, weight: .regular) }
            attrs[.font] = f
            if let url = run.link { attrs[.link] = url }
            out.append(NSAttributedString(string: String(a[run.range].characters), attributes: attrs))
        }
        return out
    }
}

/// 위에서 시작한 드래그가 패널 이동이 아니라 글자 선택이 되게 한다.
final class SelectableTextView: NSTextView {
    var renderedKey = ""
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
