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
        // 예전에 접힌 채 저장된 프레임이 복원돼도 패널이 작아지지 않게 한다 (위쪽 가장자리 유지).
        if frame.height < 360 { var f = frame; f.origin.y -= 520 - f.height; f.size.height = 520; setFrame(f, display: false) }

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
