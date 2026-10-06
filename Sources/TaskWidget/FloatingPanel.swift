import AppKit
import TaskWidgetCore

final class FloatingPanel: NSPanel, NSWindowDelegate {
    private var hovering = false

    convenience init(content: NSView) {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 520),
                  styleMask: [.nonactivatingPanel, .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                  backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 280, height: 360)
        standardWindowButton(.zoomButton)?.isHidden = true
        contentView = content
        delegate = self

        setFrameAutosaveName("TaskWidgetPanel")
        if !setFrameUsingName("TaskWidgetPanel") { center() }
        if Settings.shared.panelCollapsed { setCollapsed(true, animate: false) }

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
        if isMiniaturized {
            deminiaturize(nil)
            makeKeyAndOrderFront(nil)
        } else if isVisible {
            orderOut(nil)
        } else {
            makeKeyAndOrderFront(nil)
        }
    }

    static let collapsedHeight: CGFloat = 80   // titlebar + tab header; tune so only the header row shows

    /// 접기: 탭 바만 남기고 높이를 줄인다. 위쪽 가장자리는 고정.
    func setCollapsed(_ collapsed: Bool, animate: Bool = true) {
        var f = frame
        let newHeight: CGFloat
        if collapsed {
            // 복원된 autosave 프레임이 이미 접힌 높이면 펼침 높이를 덮어쓰지 않는다.
            if f.height >= 360 { Settings.shared.panelExpandedHeight = Double(f.height) }
            minSize = NSSize(width: 280, height: Self.collapsedHeight)
            maxSize = NSSize(width: 10000, height: Self.collapsedHeight)
            newHeight = Self.collapsedHeight
        } else {
            maxSize = NSSize(width: 10000, height: 10000)
            minSize = NSSize(width: 280, height: 360)
            newHeight = max(360, CGFloat(Settings.shared.panelExpandedHeight))
        }
        f.origin.y += f.height - newHeight
        f.size.height = newHeight
        setFrame(f, display: true, animate: animate)
    }

    /// 어떤 경로로 숨겨지든 hover 상태와 alpha 를 함께 되돌려, 다시 보일 때 불투명으로 나오지 않게 한다.
    override func orderOut(_ sender: Any?) {
        hovering = false
        applyAppearance()
        super.orderOut(sender)
    }

    /// 닫기 버튼 = 숨기기. 앱은 메뉴바에 계속 산다.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        orderOut(nil)
        return false
    }
}
