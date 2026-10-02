import AppKit
import TaskWidgetCore

final class FloatingPanel: NSPanel, NSWindowDelegate {
    private var hovering = false

    convenience init(content: NSView) {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 520),
                  styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
                  backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 280, height: 360)
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        contentView = content
        delegate = self

        setFrameAutosaveName("TaskWidgetPanel")
        if !setFrameUsingName("TaskWidgetPanel") { center() }

        let tracking = NSTrackingArea(rect: .zero,
                                      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
        content.addTrackingArea(tracking)
        applyAppearance()
    }

    /// nonactivating 패널에서도 텍스트 입력을 받으려면 key 가 될 수 있어야 한다.
    override var canBecomeKey: Bool { true }

    func applyAppearance() {
        let s = Settings.shared
        level = s.alwaysOnTop ? .floating : .normal
        collectionBehavior = s.allSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace]
        alphaValue = (hovering && s.hoverOpaque) ? 1.0 : s.opacity
        switch s.theme {
        case "light": appearance = NSAppearance(named: .aqua)
        case "dark": appearance = NSAppearance(named: .darkAqua)
        default: appearance = nil
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        applyAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        applyAppearance()
    }

    func toggle() {
        if isVisible { hovering = false; orderOut(nil) } else { makeKeyAndOrderFront(nil) }
    }

    /// 닫기 버튼 = 숨기기. 앱은 메뉴바에 계속 산다.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hovering = false
        orderOut(nil)
        return false
    }
}
