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
