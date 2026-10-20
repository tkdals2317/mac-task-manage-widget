import AppKit
import SwiftUI
import TaskWidgetCore

private struct AtmAccentKey: EnvironmentKey { static let defaultValue = Color.accentColor }
private struct AtmThemedKey: EnvironmentKey { static let defaultValue = false }
private struct AtmBackgroundKey: EnvironmentKey { static let defaultValue: Color? = nil }

extension EnvironmentValues {
    /// 패널 강조색. 테마 색을 쓰지 않으면 시스템 강조색.
    var atmAccent: Color {
        get { self[AtmAccentKey.self] }
        set { self[AtmAccentKey.self] = newValue }
    }
    /// 테마 색 사용 중인지 (NSSegmentedControl 처럼 환경 tint 를 못 받는 AppKit 뷰용).
    var atmThemed: Bool {
        get { self[AtmThemedKey.self] }
        set { self[AtmThemedKey.self] = newValue }
    }
    /// 테마 배경색 (팝오버 배경을 패널과 맞출 때). 테마를 안 쓰면 nil → 시스템 팝오버 배경.
    var atmBackground: Color? {
        get { self[AtmBackgroundKey.self] }
        set { self[AtmBackgroundKey.self] = newValue }
    }
}

/// 패널 루트에 붙여 강조색을 주입한다. 설정이 바뀌면 AppStorage 로 바로 갱신된다.
struct ThemedPanel: ViewModifier {
    @AppStorage(SettingsKey.themePreset) private var preset = "default"
    @AppStorage(SettingsKey.customBackground) private var customBackground = ThemePalette.defaultBackground
    @AppStorage(SettingsKey.customAccent) private var customAccent = ThemePalette.defaultAccent

    @ViewBuilder
    func body(content: Content) -> some View {
        if let c = ThemePalette.resolve(id: preset, customBackground: customBackground, customAccent: customAccent) {
            let accent = Color(hex: c.accent)
            content.environment(\.atmAccent, accent).environment(\.atmThemed, true)
                .environment(\.atmBackground, Color(hex: c.background)).tint(accent)
        } else {
            content
        }
    }
}

extension View {
    func themedPanel() -> some View { modifier(ThemedPanel()) }
}

extension View {
    /// 비밀번호 칸 자동완성 말풍선 막기. macOS 15 이상은 그냥 두면 "Passwords…" 말풍선이 떠서 oneTimeCode 로 막는다.
    /// macOS 14 는 oneTimeCode 를 주면 빈 "보안 코드" 제안 창이 떠서 아무것도 지정하지 않는다.
    @ViewBuilder
    func noPasswordSuggestions() -> some View {
        if #available(macOS 15, *) { textContentType(.oneTimeCode) } else { self }
    }
}

/// 팝오버 배경을 패널 테마 배경과 맞춘다 (기본은 회색 시스템 팝오버).
/// presentationBackground 는 말풍선 꼬리를 칠하지 못해서, 팝오버 창의 프레임 뷰(꼬리 포함) 맨 아래에 색 뷰를 깐다.
struct ThemedPopover: ViewModifier {
    @Environment(\.atmBackground) private var bg
    func body(content: Content) -> some View {
        if let bg { content.background(PopoverFrameColor(color: NSColor(bg))) } else { content }
    }
}

private struct PopoverFrameColor: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> NSView { Probe(color: color) }
    func updateNSView(_ v: NSView, context: Context) { (v as? Probe)?.apply(color) }

    final class Probe: NSView {
        private var color: NSColor
        private weak var fill: NSView?
        init(color: NSColor) { self.color = color; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply(color)
        }

        func apply(_ c: NSColor) {
            color = c
            // contentView 의 superview 가 꼬리까지 그리는 팝오버 프레임
            guard let frame = window?.contentView?.superview else { return }
            let v = fill ?? {
                let v = NSView(frame: frame.bounds)
                v.autoresizingMask = [.width, .height]
                v.wantsLayer = true
                frame.addSubview(v, positioned: .below, relativeTo: frame.subviews.first)
                fill = v
                return v
            }()
            v.layer?.backgroundColor = c.cgColor
        }
    }
}

extension View {
    func themedPopover() -> some View { modifier(ThemedPopover()) }
}

/// 할 일 추가칸과 같은 모양의 입력칸: 옅은 바탕, 선택하면 테마 강조색 테두리. 팝오버·패널 안 입력칸 공용.
struct ThemedTextField: View {
    let prompt: String
    @Binding var text: String
    var secure = false
    var autofocus = false
    var onSubmit: () -> Void = {}
    @Environment(\.fontScale) private var scale
    @Environment(\.atmAccent) private var accent
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField(prompt, text: $text).noPasswordSuggestions()
            } else {
                TextField(prompt, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 12 * scale))
        .focused($focused)
        .onSubmit(onSubmit)
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(focused ? accent : Color.primary.opacity(0.12), lineWidth: focused ? 1.5 : 0.5))
        .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
    }
}

/// 팝오버 아래 버튼 줄: 취소(흐림) + 주 버튼(강조색). 주 버튼은 ↩ 로도 눌린다.
struct PopoverButtons: View {
    let primary: String
    var busy = false
    let cancel: () -> Void
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Spacer()
            Button(action: cancel) { AccentChip(icon: "xmark", text: "취소", style: .plain) }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            Button(action: submit) { AccentChip(icon: "checkmark", text: primary, style: .solid) }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(busy)
        }
    }
}

// MARK: - 스크롤 막대

/// macOS 설정이 "스크롤 막대 항상 보기"면 흰 트랙과 회색 막대가 늘 보여 패널이 지저분하고,
/// 오버레이 막대는 macOS 가 보였다 숨겼다를 직접 해서 마우스를 올려도 늦게 뜨거나 금방 사라진다.
/// 그래서 시스템 막대는 끄고, 테마 강조색 얇은 막대를 직접 그린다: 마우스가 스크롤 영역 위에 있거나 스크롤하는 동안 보이고,
/// 끌어서 스크롤할 수 있다. ScrollView 에 `.themedScrollbar()` 를 붙인다.
extension View {
    func themedScrollbar() -> some View { modifier(ThemedScrollbarModifier()) }
}

private struct ThemedScrollbarModifier: ViewModifier {
    @Environment(\.atmAccent) private var accent
    func body(content: Content) -> some View {
        // 시스템 막대는 SwiftUI 쪽에서 숨겨야 한다 (NSScrollView 에서만 끄면 갱신 때 다시 켜진다). .hidden 은 "항상 보기" 설정이면 무시돼서 .never.
        content.scrollIndicators(.never).background(ScrollerHook(color: NSColor(accent)))
    }
}

private struct ScrollerHook: NSViewRepresentable {
    let color: NSColor
    func makeNSView(context: Context) -> ScrollerHookView { ScrollerHookView() }
    func updateNSView(_ v: ScrollerHookView, context: Context) {
        v.color = color
        v.attach()
    }
}

/// ScrollView 옆(background)에 붙는 빈 뷰. 옆의 NSScrollView 를 찾아 막대를 붙인다.
final class ScrollerHookView: NSView {
    var color: NSColor = .controlAccentColor { didSet { bar?.color = color } }
    private weak var bar: AccentScrollBar?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // SwiftUI 가 NSScrollView 를 만든 뒤라야 찾을 수 있다
        DispatchQueue.main.async { [weak self] in self?.attach() }
    }

    func attach() {
        guard let sv = enclosingScrollView ?? siblingScrollView() else { return }
        if let b = bar, b.superview === sv { b.color = color; return }
        if let existing = sv.subviews.first(where: { $0 is AccentScrollBar }) as? AccentScrollBar {
            bar = existing
        } else {
            let b = AccentScrollBar(scrollView: sv)
            sv.addSubview(b)
            bar = b
        }
        bar?.color = color
    }

    /// background 로 붙으면 ScrollView 와 형제가 된다. 가까운 조상부터 올라가며 같은 자리의 NSScrollView 를 찾는다.
    private func siblingScrollView() -> NSScrollView? {
        var node = superview
        for _ in 0..<4 {
            guard let n = node else { return nil }
            if let sv = Self.firstScrollView(in: n, near: convert(bounds, to: n)) { return sv }
            node = n.superview
        }
        return nil
    }

    private static func firstScrollView(in v: NSView, near r: NSRect) -> NSScrollView? {
        for sub in v.subviews {
            if let sv = sub as? NSScrollView, sv.frame.intersects(r) { return sv }
            if !(sub is NSScrollView), let found = firstScrollView(in: sub, near: v.convert(r, to: sub)) { return found }
        }
        return nil
    }
}

/// NSScrollView 오른쪽 끝에 겹쳐 놓는 얇은 막대. 바탕은 투명, 막대만 강조색.
final class AccentScrollBar: NSView {
    var color: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    private weak var scrollView: NSScrollView?
    private var observers: [NSObjectProtocol] = []
    private var hovering = false
    private var dragging: (startY: CGFloat, startOrigin: CGFloat)?
    private var hideWork: DispatchWorkItem?
    private static let width: CGFloat = 10

    init(scrollView sv: NSScrollView) {
        scrollView = sv
        super.init(frame: .zero)
        wantsLayer = true
        alphaValue = 0
        sv.hasVerticalScroller = false
        sv.contentView.postsBoundsChangedNotifications = true
        sv.postsFrameChangedNotifications = true
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSView.boundsDidChangeNotification, object: sv.contentView, queue: .main) { [weak self] _ in
            self?.layoutBar(); self?.flash()
        })
        observers.append(nc.addObserver(forName: NSView.frameDidChangeNotification, object: sv, queue: .main) { [weak self] _ in
            self?.layoutBar()
        })
        // 스크롤 영역 전체에 마우스가 들어오고 나가는 것을 본다
        sv.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        DispatchQueue.main.async { [weak self] in self?.layoutBar() }
    }

    required init?(coder: NSCoder) { nil }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    // 막대는 화면 오른쪽 끝 세로 띠
    private func layoutBar() {
        guard let sv = scrollView else { return }
        let b = sv.bounds
        let f = NSRect(x: b.maxX - Self.width, y: b.minY, width: Self.width, height: b.height)
        if frame != f { frame = f }
        needsDisplay = true
    }

    private var metrics: (visible: CGFloat, total: CGFloat, offset: CGFloat)? {
        guard let sv = scrollView, let doc = sv.documentView else { return nil }
        let visible = sv.contentView.bounds.height
        let total = doc.frame.height
        // 레이아웃 도중엔 크기가 0·무한대일 수 있다. 그대로 쓰면 NaN 좌표로 그리다 앱이 죽는다.
        guard visible.isFinite, total.isFinite, visible > 0, total > visible + 1 else { return nil }
        // 문서가 뒤집힌 좌표면 위에서부터, 아니면 아래에서부터 잰다
        let y = sv.contentView.bounds.minY
        let offset = doc.isFlipped ? y : total - visible - y
        return (visible, total, max(0, min(offset, total - visible)))
    }

    private var knobRect: NSRect? {
        guard let m = metrics else { return nil }
        let track = bounds.insetBy(dx: 0, dy: 3)
        guard track.height > 24 else { return nil }
        let h = min(track.height, max(24, track.height * m.visible / m.total))
        let top = track.minY + (track.height - h) * m.offset / (m.total - m.visible)
        guard top.isFinite, h.isFinite else { return nil }
        // 이 뷰는 뒤집히지 않은 좌표라 위쪽이 maxY
        let y = isFlipped ? top : track.maxY - top - h
        let w: CGFloat = hovering || dragging != nil ? 6 : 4
        return NSRect(x: bounds.maxX - w - 2, y: y, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let r = knobRect else { return }
        color.withAlphaComponent(dragging != nil ? 0.9 : 0.6).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.width / 2, yRadius: r.width / 2).fill()
    }

    private func setShown(_ on: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = on ? 0.08 : 0.3
            animator().alphaValue = on ? 1 : 0
        }
    }

    /// 스크롤 중엔 보이고, 마우스가 밖에 있으면 1초 뒤 숨긴다
    private func flash() {
        guard metrics != nil else { return }
        setShown(true)
        scheduleHide()
    }

    private func scheduleHide() {
        hideWork?.cancel()
        guard !hovering, dragging == nil else { return }
        let w = DispatchWorkItem { [weak self] in self?.setShown(false) }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: w)
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        hideWork?.cancel()
        layoutBar()
        if metrics != nil { setShown(true) }
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
        scheduleHide()
    }

    // 막대 위에서만 클릭을 받고, 나머지는 아래 내용으로 흘려보낸다
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard alphaValue > 0.5, let r = knobRect else { return nil }
        let p = convert(point, from: superview)
        return r.insetBy(dx: -4, dy: 0).contains(p) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let sv = scrollView else { return }
        dragging = (convert(event.locationInWindow, from: nil).y, sv.contentView.bounds.minY)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = dragging, let sv = scrollView, let doc = sv.documentView, let m = metrics else { return }
        let track = bounds.height - 6
        let knobH = max(24, track * m.visible / m.total)
        let dy = convert(event.locationInWindow, from: nil).y - d.startY
        // 막대를 끈 거리만큼 문서를 비례해서 움직인다 (뒤집힌 문서는 아래로 끌면 y 가 커져야 한다)
        let scale = (m.total - m.visible) / max(1, track - knobH)
        let delta = (doc.isFlipped ? -dy : dy) * scale * (isFlipped ? -1 : 1)
        let newY = max(0, min(d.startOrigin + delta, m.total - m.visible))
        sv.contentView.scroll(to: NSPoint(x: sv.contentView.bounds.minX, y: newY))
        sv.reflectScrolledClipView(sv.contentView)
    }

    override func mouseUp(with event: NSEvent) {
        dragging = nil
        needsDisplay = true
        scheduleHide()
    }
}
