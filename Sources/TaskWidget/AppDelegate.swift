import AppKit
import Combine
import SwiftUI
import UserNotifications
import TaskWidgetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let state = AppState()
    private var defaultsObserver: Any?
    private var settingsObserver: Any?
    private var hotKeyRecObserver: Any?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var onboardingObserver: Any?
    private var panelKeyObserver: Any?
    private var scheduler: Scheduler!
    private var updateTask: Task<Void, Never>?
    private var hotKey: GlobalHotKey!
    private var hotKeyRecording = false
    private var todosSub: AnyCancellable?
    private var badgeTimer: Timer?
    private var sigterm: DispatchSourceSignal?
    private let notificationDelegate = NotificationDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // make install / 업데이트의 pkill(SIGTERM) 도 정상 종료로 처리해 Teleport 터널을 정리한다.
        signal(SIGTERM, SIG_IGN)
        sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm?.setEventHandler { NSApp.terminate(nil) }
        sigterm?.resume()
        installMainMenu()
        try? Paths.ensureDirectories()

        let host = NSHostingView(rootView: RootView().environmentObject(state).themedPanel())
        // 패널 크기는 FloatingPanel 이 직접 관리 (minSize/maxSize). SwiftUI 콘텐츠 크기를 창 제약으로 올리지 않는다.
        host.sizingOptions = []
        panel = FloatingPanel(content: host)
        let updateAccessory = NSTitlebarAccessoryViewController()
        updateAccessory.layoutAttribute = .trailing
        let updateHost = NSHostingView(rootView: UpdateTitlebarButton().environmentObject(state).themedPanel())
        updateHost.frame = NSRect(x: 0, y: 0, width: 120, height: 32)
        updateAccessory.view = updateHost
        panel.addTitlebarAccessoryViewController(updateAccessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "ATM")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // queue: .main 이라 항상 메인 스레드. Sendable 클로저에서 MainActor 프로퍼티 접근 경고를 피한다.
            MainActor.assumeIsolated {
                self?.panel.applyAppearance()
                if let w = self?.onboardingWindow, w.isVisible { self?.styleOnboardingWindow(w) }
                self?.syncHotKey()
            }
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .openSettings, object: nil, queue: .main
        ) { [weak self] note in
            let pane = note.object as? String
            MainActor.assumeIsolated { self?.showSettingsWindow(pane: pane) }
        }

        onboardingObserver = NotificationCenter.default.addObserver(
            forName: .openOnboarding, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showOnboardingWindow() }
        }

        hotKey = GlobalHotKey { [weak self] in self?.hotKeyToggle() }
        hotKeyRecObserver = NotificationCenter.default.addObserver(
            forName: .hotKeyRecording, object: nil, queue: .main
        ) { [weak self] note in
            let on = note.object as? Bool ?? false
            MainActor.assumeIsolated { self?.hotKeyRecording = on; self?.syncHotKey() }
        }
        syncHotKey()

        // 메뉴바 배지: 할 일이 바뀔 때 + 1분마다(날짜 넘어감)
        todosSub = state.$todos.sink { [weak self] todos in self?.updateBadge(todos) }
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if let self { self.updateBadge(self.state.todos) } }
        }

        state.startInbox()
        state.teleport.start()
        // UI 가 뜬 뒤 지난번에 켜 둔 Teleport DB 를 다시 연결
        Task { [state] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let on = TabConfig.enabled(from: Settings.shared.enabledTabs, all: allTabs.map(\.id)).contains("teleport")
            await state.teleport.restoreWanted(tabEnabled: on)
        }
        scheduler = Scheduler(state: state)
        scheduler.start()
        // 알림을 눌렀을 때 PR 주소를 열고, 앞에 떠 있을 때도 배너를 보여준다. 번들 없이 실행하면 UNUserNotificationCenter 가 죽는다.
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = notificationDelegate }
        state.pr.startLoop()

        // 시작 10초 후 한 번, 이후 30분마다 업데이트 확인 (소스 폴더 정보가 없으면 checkForUpdates 가 무시)
        updateTask = Task { [state] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            while !Task.isCancelled {
                await state.checkForUpdates()
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
            }
        }

        // 패널을 열 때 최신 업데이트 상태를 보이도록 확인. 너무 잦은 fetch 를 막으려 10분 간격.
        panelKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let state = self?.state else { return }
                Task { await state.checkForUpdatesIfStale(minInterval: 10 * 60) }
            }
        }

        panel.makeKeyAndOrderFront(nil)

        // 처음 쓰는 사람에게만 설정 도우미. 이미 쓰던 흔적이 있으면 조용히 끝난 것으로 둔다.
        let fm = FileManager.default
        if !Settings.shared.onboardingDone {
            if Onboarding.shouldShow(done: false, todosExists: fm.fileExists(atPath: Paths.todosFile.path),
                                     jiraEmail: Settings.shared.jiraEmail,
                                     teleportExists: fm.fileExists(atPath: Paths.teleportFile.path),
                                     notesExists: fm.fileExists(atPath: Paths.notesFile.path)) {
                showOnboardingWindow()
            } else {
                Settings.shared.onboardingDone = true
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.teleport.shutdown()
        state.notes.flushPending()
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

        let viewItem = NSMenuItem()
        let view = NSMenu(title: "보기")
        view.addItem(withTitle: "새 할 일", action: #selector(newTodo), keyEquivalent: "n").target = self
        view.addItem(.separator())
        for i in allTabs.indices {
            let item = view.addItem(withTitle: "탭 \(i + 1)", action: #selector(selectTab(_:)), keyEquivalent: "\(i + 1)")
            item.target = self
            item.tag = i
        }
        viewItem.submenu = view
        main.addItem(viewItem)

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

    private func syncHotKey() {
        if Settings.shared.globalHotKeyEnabled && !hotKeyRecording {
            hotKey.register(Settings.shared.globalHotKey)
        } else {
            hotKey.unregister()
        }
    }

    private func hotKeyToggle() {
        panel.toggle()
        if panel.isVisible { NSApp.activate(ignoringOtherApps: true) }
    }

    private func showPanel() {
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func newTodo() {
        panel.keepFocusOnce = true   // 열면서 입력칸 포커스를 자동 해제하지 않게
        showPanel()
        UserDefaults.standard.set("tasks", forKey: SettingsKey.lastTab)
        state.focusNewTodo = true
    }

    /// 켜진 탭 중 n번째로 전환. 범위 밖이면 무시.
    @objc private func selectTab(_ sender: NSMenuItem) {
        let enabled = TabConfig.enabled(from: Settings.shared.enabledTabs, all: allTabs.map(\.id))
        guard enabled.indices.contains(sender.tag) else { return }
        showPanel()
        UserDefaults.standard.set(enabled[sender.tag], forKey: SettingsKey.lastTab)
    }

    private func updateBadge(_ todos: [Todo]) {
        let n = DueBadge.urgentCount(todos: todos, now: Date())
        guard let b = statusItem.button else { return }
        b.title = n > 0 ? " \(n)" : ""
        b.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        b.imagePosition = n > 0 ? .imageLeading : .imageOnly
        statusItem.length = n > 0 ? NSStatusItem.variableLength : NSStatusItem.squareLength
    }

    @objc private func generateNow() {
        panel.makeKeyAndOrderFront(nil)
        UserDefaults.standard.set("summary", forKey: SettingsKey.lastTab)
        Task { await state.generateSummary(for: Date(), force: true) }
    }

    @objc private func openSettings() { showSettingsWindow() }

    /// 패널에 붙은 시트는 key 가 못 돼 컨트롤이 비활성 색(회색 토글)으로 그려진다. 독립 창으로 띄운다.
    private func showSettingsWindow(pane: String? = nil) {
        let window = settingsWindow ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "ATM 설정"
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
            return w
        }()
        // 열 때마다 새로 그려 훅/스킬/토큰 상태를 다시 읽는다.
        window.contentViewController = NSHostingController(rootView: SettingsView(initialPane: pane).environmentObject(state))
        // 패널이 '항상 위'면 일반 레벨 창은 그 밑에 깔린다.
        window.level = Settings.shared.alwaysOnTop ? .floating : .normal
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// 패널과 같은 테마 배경·외형을 설정 도우미 창에 입힌다 (FloatingPanel.applyAppearance 와 같은 규칙).
    private func styleOnboardingWindow(_ w: NSWindow) {
        let s = Settings.shared
        w.level = s.alwaysOnTop ? .floating : .normal
        if let c = s.themeColors, let bg = HexColor.rgb(c.background) {
            w.backgroundColor = NSColor(srgbRed: bg.r, green: bg.g, blue: bg.b, alpha: 1)
            w.appearance = NSAppearance(named: c.isDark ? .darkAqua : .aqua)
        } else {
            w.backgroundColor = .windowBackgroundColor
            switch s.theme {
            case "light": w.appearance = NSAppearance(named: .aqua)
            case "dark": w.appearance = NSAppearance(named: .darkAqua)
            default: w.appearance = nil
            }
        }
    }

    /// 설정 도우미. 설정 창처럼 독립 창. 닫기만 하면 done 은 그대로라 다음 실행에 다시 뜬다.
    private func showOnboardingWindow() {
        // 이미 진행 중이면 진행 상황을 지우지 말고 앞으로만 가져온다.
        if let w = onboardingWindow, w.isVisible, w.contentViewController != nil {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let window = onboardingWindow ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "ATM 설정 도우미"
            w.isReleasedWhenClosed = false
            w.center()
            // 닫히면 화면 상태(토큰·비밀번호·OTP 키 입력값)가 메모리에 남지 않게 내용을 뗀다.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak w] _ in
                MainActor.assumeIsolated { w?.contentViewController = nil }
            }
            onboardingWindow = w
            return w
        }()
        let view = OnboardingView(
            onClose: { [weak window] in window?.close() },
            onFinish: { [weak self] in self?.showPanel() }
        ).environmentObject(state).themedPanel()
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        let wasEmpty = window.frame.width < 100
        window.contentViewController = host
        // sizingOptions 를 비우면 contentViewController 를 붙일 때 창이 0×0 으로 줄어든다. 크기를 다시 정한다.
        window.setContentSize(NSSize(width: 560, height: 520))
        if wasEmpty { window.center() }
        styleOnboardingWindow(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// 알림 클릭 → userInfo["url"] 열기 (PR 알림). 앱이 PR 알림은 앞에 있어도 배너를 띄운다.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let s = response.notification.request.content.userInfo["url"] as? String,
           let u = URL(string: s), u.scheme == "https" {
            DispatchQueue.main.async { NSWorkspace.shared.open(u) }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // PR 알림(url 이 있는 것)만 앞에 떠 있을 때도 배너로. 요약 알림 등은 예전처럼 앞에서는 띄우지 않는다.
        completionHandler(notification.request.content.userInfo["url"] != nil ? [.banner, .sound] : [])
    }
}
