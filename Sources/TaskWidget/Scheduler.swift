import AppKit
import UserNotifications
import TaskWidgetCore

@MainActor
final class Scheduler {
    private let state: AppState
    private var timer: Timer?
    private var scheduledKey = ""
    private var catchUpTask: Task<Void, Never>?
    private var observers: [Any] = []

    init(state: AppState) {
        self.state = state
    }

    func start() {
        requestNotificationPermission()
        reschedule()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Timer(fire:) 데드라인은 잠자는 동안 멈춘다. 깨어나면 다시 걸어야 다음 날 요약이 일찍 생성되지 않는다.
            Task { @MainActor in
                self?.reschedule()
                self?.catchUp()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.settingsChanged() }
        })
        catchUp()
    }

    private var currentKey: String {
        let s = Settings.shared
        return "\(s.summaryHour):\(s.summaryMinute)"
    }

    private func settingsChanged() {
        guard currentKey != scheduledKey else { return }
        reschedule()
        // 시·분은 피커가 따로라 중간 값(과거 시각)이 잠깐 설정될 수 있다. 멈춘 뒤에만 catch-up.
        catchUpTask?.cancel()
        catchUpTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.catchUp()
        }
    }

    func reschedule() {
        let s = Settings.shared
        scheduledKey = currentKey
        timer?.invalidate()
        let fire = Schedule.nextFireDate(after: Date(), hour: s.summaryHour, minute: s.summaryMinute)
        let t = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.fire() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NSLog("summary scheduled at \(fire)")
    }

    private func fire() async {
        await generateIfMissing()
        reschedule()
    }

    /// 지금이 오늘 예정 시각 이후인데 오늘 파일이 없으면 즉시 생성 (앱 시작, 깨어남, 시각 변경 시).
    func catchUp() {
        let s = Settings.shared
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = s.summaryHour
        c.minute = s.summaryMinute
        guard let scheduled = Calendar.current.date(from: c), Date() >= scheduled else { return }
        Task { await generateIfMissing() }
    }

    private func generateIfMissing() async {
        let today = Date()
        // 타이머 + 깨어남 + 설정 변경이 겹쳐도 한 번만. 이미 생성 중이면 조용히 빠진다.
        guard !state.summaryGenerating,
              state.summaryService.existing(for: today) == nil else { return }
        let ok = await state.generateSummary(for: today, force: false)
        if Settings.shared.summaryNotify {
            if ok {
                notify("오늘 요약 완료", body: "")
            } else if let e = state.summaryError {
                notify("요약 실패", body: e)
            }
        }
        if Calendar.current.isDate(state.summaryDay, inSameDayAs: today) {
            state.loadSummary(for: today)
        }
    }

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
