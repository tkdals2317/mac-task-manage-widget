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
        await catchUpMissed()
        reschedule()
    }

    /// 앱 시작, 깨어남, 시각 변경 시: 놓친 날의 요약을 채운다 (아래 catchUpMissed).
    func catchUp() {
        Task { await self.catchUpMissed() }
    }

    /// 최근 7일 + (예정 시각이 지났으면) 오늘 중 요약 파일이 없는 날을 오래된 날부터 하나씩 생성.
    /// 과거 날 실패는 나머지 과거 날만 건너뛰고, 오늘은 항상 시도한다.
    private func catchUpMissed() async {
        let s = Settings.shared
        let service = state.summaryService
        var skipPastDays = false
        var triedToday = false
        for day in Schedule.catchUpDays(now: Date(), hour: s.summaryHour, minute: s.summaryMinute) {
            let isToday = Calendar.current.isDateInToday(day)
            if skipPastDays && !isToday { continue }
            // 다른 생성이 진행 중이면 중단. 다음 트리거(타이머, 깨어남, 설정 변경)가 이어서 처리한다.
            guard !state.summaryGenerating else { return }
            guard service.existing(for: day) == nil else { continue }

            if isToday {
                triedToday = true
                await generateIfMissing()
                continue
            }

            // 과거 날은 입력이 있을 때만 생성. "기록 없음" 파일은 남기지 않는다.
            let input = await Task.detached { service.collect(for: day) }.value
            if SummaryPrompt.isEmpty(input) { continue }
            guard !state.summaryGenerating else { return }  // collect 를 기다리는 사이 다른 생성이 시작됐을 수 있다
            let ok = await state.generateSummary(for: day, force: false)
            let key = DayKey.string(from: day)
            if Settings.shared.summaryNotify {
                if ok {
                    notify("\(key) 요약 완료", body: "")
                } else if let e = state.summaryError {
                    notify("요약 실패", body: "\(key): \(e)")
                }
            }
            // 실패 원인(claude 없음, 시간 초과 등)은 대개 다음 과거 날짜에도 같다. 알림이 쌓이지 않게 나머지 과거 날은 건너뛴다.
            if !ok { skipPastDays = true }
        }

        // 과거 날을 처리하는 동안 예정 시각이 지났을 수 있다. 그 사이 발화한 타이머는 busy 가드에 걸려 빠졌으므로 오늘을 다시 확인한다.
        if !triedToday, let last = Schedule.catchUpDays(now: Date(), hour: s.summaryHour, minute: s.summaryMinute).last,
           Calendar.current.isDateInToday(last) {
            await generateIfMissing()  // 이미 있거나 생성 중이면 조용히 빠진다
        }
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
