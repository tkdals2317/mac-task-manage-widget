import AppKit
import SwiftUI
import TaskWidgetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let state = AppState()
    private var defaultsObserver: Any?
    private var scheduler: Scheduler!

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        try? Paths.ensureDirectories()

        let host = NSHostingView(rootView: RootView().environmentObject(state))
        panel = FloatingPanel(content: host)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "TaskWidget")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // queue: .main 이라 항상 메인 스레드. Sendable 클로저에서 MainActor 프로퍼티 접근 경고를 피한다.
            MainActor.assumeIsolated { self?.panel.applyAppearance() }
        }

        scheduler = Scheduler(state: state)
        scheduler.start()

        panel.makeKeyAndOrderFront(nil)
    }

    /// LSUIElement 앱이라 메뉴바에 안 보이지만, ⌘V/⌘C/⌘X/⌘A/⌘Z 는 메인 메뉴의 Edit 항목을 통해서만 동작한다.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "TaskWidget 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    @objc private func openSettings() {
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }
}
