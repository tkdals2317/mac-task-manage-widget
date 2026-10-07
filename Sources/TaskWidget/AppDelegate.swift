import AppKit
import SwiftUI
import TaskWidgetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let state = AppState()
    private var defaultsObserver: Any?
    private var settingsObserver: Any?
    private var settingsWindow: NSWindow?
    private var scheduler: Scheduler!

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        try? Paths.ensureDirectories()

        let host = NSHostingView(rootView: RootView().environmentObject(state))
        // 패널 크기는 FloatingPanel 이 직접 관리 (minSize/maxSize). SwiftUI 콘텐츠 크기를 창 제약으로 올리지 않는다.
        host.sizingOptions = []
        panel = FloatingPanel(content: host)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "ATM")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // queue: .main 이라 항상 메인 스레드. Sendable 클로저에서 MainActor 프로퍼티 접근 경고를 피한다.
            MainActor.assumeIsolated { self?.panel.applyAppearance() }
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .openSettings, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showSettingsWindow() }
        }

        scheduler = Scheduler(state: state)
        scheduler.start()

        panel.makeKeyAndOrderFront(nil)
    }

    /// ⌘V/⌘C/⌘X/⌘A/⌘Z 는 메인 메뉴의 Edit 항목을 통해서만 동작한다.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "ATM 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            panel.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "패널 보이기/숨기기", action: #selector(togglePanel), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        let genItem = NSMenuItem(title: "요약 지금 생성", action: #selector(generateNow), keyEquivalent: "")
        genItem.target = self
        menu.addItem(genItem)
        let settingsItem = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        // 좌클릭은 토글, 우클릭만 메뉴: 잠깐 메뉴를 달았다가 뗀다.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePanel() { panel.toggle() }

    @objc private func generateNow() {
        panel.makeKeyAndOrderFront(nil)
        UserDefaults.standard.set("summary", forKey: SettingsKey.lastTab)
        Task { await state.generateSummary(for: Date(), force: true) }
    }

    @objc private func openSettings() { showSettingsWindow() }

    /// 패널에 붙은 시트는 key 가 못 돼 컨트롤이 비활성 색(회색 토글)으로 그려진다. 독립 창으로 띄운다.
    private func showSettingsWindow() {
        let window = settingsWindow ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "ATM 설정"
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
            return w
        }()
        // 열 때마다 새로 그려 훅/스킬/토큰 상태를 다시 읽는다.
        window.contentViewController = NSHostingController(rootView: SettingsView().environmentObject(state))
        // 패널이 '항상 위'면 일반 레벨 창은 그 밑에 깔린다.
        window.level = Settings.shared.alwaysOnTop ? .floating : .normal
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
