import AppKit
import CryptoKit
import LocalAuthentication
import TaskWidgetCore

extension Notification.Name {
    /// FloatingPanel.orderOut 이 보낸다. 잠긴 메모를 다시 잠그는 신호.
    static let panelDidHide = Notification.Name("TaskWidget.panelDidHide")
}

enum NotesError: LocalizedError {
    case tooShort, mismatch, wrongPassword, noLock, failed(String)

    var errorDescription: String? {
        switch self {
        case .tooShort: return "비밀번호는 4자 이상이어야 해요"
        case .mismatch: return "두 비밀번호가 달라요"
        case .wrongPassword: return "비밀번호가 맞지 않아요"
        case .noLock: return "잠금 비밀번호가 없어요"
        case .failed(let m): return m
        }
    }
}

/// 노트 탭 상태: 메모·링크 저장, 잠금(열쇠는 메모리에만), Confluence 별표 문서.
/// 잠긴 메모의 평문은 `unlocked` 에만 있고 디스크에는 봉인본만 남는다. 비밀번호·열쇠·평문은 로그에 남기지 않는다.
@MainActor
final class NotesModel: ObservableObject {
    @Published private(set) var data: NotesData
    /// 열어 둔 잠긴 메모의 평문 (메모리 전용).
    @Published private(set) var unlocked: [UUID: String] = [:]
    @Published var expanded: Set<UUID> = []
    /// 방금 만든 메모처럼 본문 편집기에 포커스를 줄 메모.
    @Published var focusMemo: UUID?
    @Published private(set) var relockAt: Date?
    @Published private(set) var starred: [StarredPage] = []
    @Published private(set) var starredError: String?
    @Published private(set) var starredUpdatedAt: Date?
    @Published private(set) var starredLoading = false

    private let store: NoteStore
    private var key: SymmetricKey?
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// 자동으로 다시 잠기기까지 (마지막 열기/편집 뒤)
    static let relockInterval: TimeInterval = 5 * 60

    init(store: NoteStore = NoteStore()) {
        self.store = store
        self.data = store.load()
        // 패널 숨김 · 시스템 잠자기 · 화면 잠금이면 즉시 다시 잠근다.
        observe(NotificationCenter.default, .panelDidHide)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification)
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"))
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let at = self.relockAt, Date() >= at else { return }
                self.relockAll()
            }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let o = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relockAll() }
        }
        observers.append((center, o))
    }

    // MARK: - 탭 도입 (한 번)

    /// 노트 탭이 생긴 버전으로 처음 올라온 사용자에게 탭을 한 번 켜 준다. 이후 끄면 다시 켜지 않는다.
    static func introduceTabIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: SettingsKey.notesTabIntroduced) else { return }
        let s = Settings.shared
        let ids = allTabs.map(\.id)
        if !TabConfig.enabled(from: s.enabledTabs, all: ids).contains("notes") {
            s.enabledTabs = TabConfig.toggled("notes", in: s.enabledTabs, all: ids)
        }
        d.set(true, forKey: SettingsKey.notesTabIntroduced)
    }

    // MARK: - 조회

    var hasLock: Bool { data.lock != nil }
    var hasKey: Bool { key != nil }
    var orderedMemos: [Memo] { NotesOrder.memos(data.memos) }

    func memo(_ id: UUID) -> Memo? { data.memos.first { $0.id == id } }

    /// 평문을 볼 수 있는가 (안 잠겼거나, 잠겼지만 열려 있음)
    func isReadable(_ m: Memo) -> Bool { !m.locked || unlocked[m.id] != nil }

    func text(_ m: Memo) -> String { m.locked ? (unlocked[m.id] ?? "") : m.body }

    /// 목록 둘째 줄 미리보기. 잠긴 메모는 열려 있어도 보여주지 않는다.
    func preview(_ m: Memo) -> String? { m.locked ? nil : m.preview }

    static var touchIDAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }
    var touchIDEnabled: Bool { UserDefaults.standard.bool(forKey: SettingsKey.notesTouchID) }

    private var dirty = false
    private var saveTask: Task<Void, Never>?

    private func persist() {
        saveTask?.cancel(); saveTask = nil
        dirty = false
        do { try store.save(data) } catch { NSLog("notes save failed: \(error.localizedDescription)") }
    }

    /// 글자를 칠 때마다 디스크에 쓰지 않고 잠깐 모아서 쓴다. 메모리(data)는 즉시 최신.
    private func persistSoon() {
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled { self?.flushPending() }
        }
    }

    /// 아직 안 쓴 변경이 있으면 지금 쓴다 (재잠금·종료 직전).
    func flushPending() { if dirty { persist() } }

    private func update(_ id: UUID, _ change: (inout Memo) -> Void) {
        guard let i = data.memos.firstIndex(where: { $0.id == id }) else { return }
        change(&data.memos[i])
        persist()
    }

    /// 열린 잠긴 메모가 있으면 자동 재잠금 시각을 뒤로 민다.
    private func touch() {
        relockAt = (key == nil && unlocked.isEmpty) ? nil : Date().addingTimeInterval(Self.relockInterval)
    }

    // MARK: - 메모

    @discardableResult
    func addMemo(_ title: String) -> UUID? {
        guard let t = Todo.normalizedTitle(title) else { return nil }
        let m = Memo(title: t)
        data.memos.append(m)
        persist()
        expanded.insert(m.id)
        focusMemo = m.id
        return m.id
    }

    func rename(_ id: UUID, _ title: String) {
        guard let t = Todo.normalizedTitle(title), memo(id)?.title != t else { return }
        update(id) { $0.title = t }
    }

    func togglePin(_ id: UUID) { update(id) { $0.pinned.toggle() } }

    func delete(_ id: UUID) {
        data.memos.removeAll { $0.id == id }
        unlocked[id] = nil
        expanded.remove(id)
        persist()
        touch()
    }

    func toggleExpanded(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// 본문 저장. 잠긴 메모는 열려 있을 때만, 평문은 메모리에 두고 봉인본을 디스크에 쓴다.
    func setBody(_ id: UUID, _ text: String) {
        guard let m = memo(id), text != self.text(m) else { return }
        if m.locked {
            guard unlocked[id] != nil, let key, let sealed = try? NoteCrypto.seal(text, key: key) else { return }
            unlocked[id] = text
            change(id) { $0.sealed = sealed; $0.updatedAt = Date() }
            touch()
        } else {
            change(id) { $0.body = text; $0.updatedAt = Date() }
        }
    }

    private func change(_ id: UUID, _ edit: (inout Memo) -> Void) {
        guard let i = data.memos.firstIndex(where: { $0.id == id }) else { return }
        edit(&data.memos[i])
        persistSoon()
    }

    // MARK: - 잠금

    /// 처음 비밀번호를 만든다. 끝나면 열쇠가 메모리에 있다.
    func createPassword(_ pw: String, confirm: String) async throws {
        guard pw.count >= 4 else { throw NotesError.tooShort }
        guard pw == confirm else { throw NotesError.mismatch }
        let made = try await Task.detached { try NoteCrypto.makeLock(password: pw) }.value
        data.lock = made.0
        key = made.1
        persist()
        touch()
    }

    /// 비밀번호를 확인하고 열쇠를 메모리에 올린다.
    @discardableResult
    private func derive(_ pw: String) async throws -> SymmetricKey {
        guard let lock = data.lock else { throw NotesError.noLock }
        guard !pw.isEmpty else { throw NotesError.wrongPassword }
        do { return try await Task.detached { try NoteCrypto.unlock(password: pw, lock: lock) }.value }
        catch NoteCryptoError.wrongPassword { throw NotesError.wrongPassword }
        catch NoteCryptoError.corrupt { throw NotesError.failed("잠금 정보가 손상됐어요") }
    }

    /// 열쇠가 있어야 한다 (없으면 verify/Touch ID 를 먼저).
    func lock(_ id: UUID) {
        guard let key, let m = memo(id), !m.locked, let sealed = try? NoteCrypto.seal(m.body, key: key) else { return }
        update(id) { $0.sealed = sealed; $0.body = "" }
        unlocked[id] = nil
        touch()
    }

    func verify(password: String) async throws {
        key = try await derive(password)
        touch()
    }

    /// 열쇠가 이미 메모리에 있으면 바로 열고 true.
    @discardableResult
    func openIfKeyed(_ id: UUID) -> Bool {
        guard let key, let m = memo(id), let s = m.sealed, let plain = try? NoteCrypto.open(s, key: key) else { return false }
        unlocked[id] = plain
        touch()
        return true
    }

    func unlock(_ id: UUID, password: String) async throws {
        try await verify(password: password)
        guard openIfKeyed(id) else { throw NotesError.failed("메모를 열지 못했어요") }
    }

    func unlockWithTouchID(_ id: UUID) async throws {
        guard let lock = data.lock else { throw NotesError.noLock }
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "비밀번호 입력"   // 누르면 LAError.userFallback → 비밀번호 팝오버
        guard try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "잠긴 메모 열기") else {
            throw NotesError.failed("Touch ID 실패")
        }
        let raw = await Task.detached { SecretStore.get(service: NoteCrypto.touchIDService, account: NoteCrypto.touchIDAccount) }.value
        guard let raw, let bytes = Data(base64Encoded: raw), NoteCrypto.verify(key: NoteCrypto.key(fromRaw: bytes), lock: lock) else {
            // 저장된 열쇠가 낡았다 (비밀번호 변경 등). 지우고 비밀번호로 열게 한다.
            await disableTouchID()
            throw NotesError.failed("Touch ID 열쇠가 낡았어요. 비밀번호로 여세요")
        }
        key = NoteCrypto.key(fromRaw: bytes)
        touch()
        guard openIfKeyed(id) else { throw NotesError.failed("메모를 열지 못했어요") }
    }

    /// 지금 잠그기: 열쇠와 평문을 메모리에서 지운다.
    func relockAll() {
        guard key != nil || !unlocked.isEmpty else { return }
        flushPending()
        unlocked = [:]
        key = nil
        relockAt = nil
    }

    /// 잠금 풀기(영구): 평문을 다시 본문에 쓰고 봉인을 없앤다.
    func unlockPermanently(_ id: UUID) {
        guard let m = memo(id), m.locked, let plain = unlocked[id] else { return }
        update(id) { $0.body = plain; $0.sealed = nil }
        unlocked[id] = nil
        touch()
    }

    func changePassword(old: String, new: String, confirm: String) async throws {
        guard new.count >= 4 else { throw NotesError.tooShort }
        guard new == confirm else { throw NotesError.mismatch }
        let oldKey = try await derive(old)
        let sealedMemos = data.memos.filter(\.locked)
        // 전부 새 열쇠로 다시 봉인하는 데 성공해야만 바꾼다 (중간 실패로 일부만 바뀌지 않게).
        let made = try await Task.detached { () -> (NoteLock, SymmetricKey, [UUID: String]) in
            let (lock, newKey) = try NoteCrypto.makeLock(password: new)
            var resealed: [UUID: String] = [:]
            for m in sealedMemos {
                resealed[m.id] = try NoteCrypto.seal(try NoteCrypto.open(m.sealed ?? "", key: oldKey), key: newKey)
            }
            return (lock, newKey, resealed)
        }.value
        for i in data.memos.indices {
            if let s = made.2[data.memos[i].id] { data.memos[i].sealed = s }
        }
        data.lock = made.0
        if key != nil { key = made.1; touch() }   // 열쇠가 없었으면 메모리에 올리지 않는다
        persist()
        if touchIDEnabled {
            let b64 = NoteCrypto.rawKey(made.1).base64EncodedString()
            let ok = await Task.detached { (try? SecretStore.set(b64, service: NoteCrypto.touchIDService, account: NoteCrypto.touchIDAccount)) != nil }.value
            if !ok { await disableTouchID() }
        }
    }

    /// 비밀번호 초기화: 잠긴 메모는 되살릴 수 없으므로 통째로 지운다.
    func resetPassword() async {
        let lockedIds = Set(data.memos.filter(\.locked).map(\.id))
        data.memos.removeAll { lockedIds.contains($0.id) }
        data.lock = nil
        unlocked = [:]
        key = nil
        relockAt = nil
        expanded.subtract(lockedIds)
        persist()
        await disableTouchID()
    }

    // MARK: - Touch ID

    /// 켜려면 비밀번호를 한 번 확인한다. 열쇠 원본을 앱 비밀 저장소에 둔다 (설정에서 안내).
    func enableTouchID(password: String) async throws {
        let k = try await derive(password)
        let b64 = NoteCrypto.rawKey(k).base64EncodedString()
        let ok = await Task.detached { (try? SecretStore.set(b64, service: NoteCrypto.touchIDService, account: NoteCrypto.touchIDAccount)) != nil }.value
        guard ok else { throw NotesError.failed("열쇠를 저장하지 못했어요") }
        UserDefaults.standard.set(true, forKey: SettingsKey.notesTouchID)
        objectWillChange.send()
    }

    func disableTouchID() async {
        UserDefaults.standard.set(false, forKey: SettingsKey.notesTouchID)
        await Task.detached { SecretStore.delete(service: NoteCrypto.touchIDService, account: NoteCrypto.touchIDAccount) }.value
        objectWillChange.send()
    }

    // MARK: - 링크

    /// 정규화해서 바로 넣고, 제목은 나중에 받아 온다. 주소로 볼 수 없으면 false.
    @discardableResult
    func addLink(_ input: String) -> Bool {
        guard let url = LinkTitle.normalize(input) else { return false }
        let placeholder = url.host ?? url.absoluteString
        let link = SavedLink(title: placeholder, url: url.absoluteString)
        data.links.append(link)
        persist()
        fetchTitle(link.id, url, placeholder: placeholder)
        return true
    }

    /// 페이지 제목을 받아 이름이 아직 placeholder 면 바꾼다 (그 사이 사용자가 이름을 바꿨으면 건드리지 않는다).
    private func fetchTitle(_ id: UUID, _ url: URL, placeholder: String) {
        guard !DemoFixtures.isOn else { return }
        Task { [weak self] in
            guard let title = await LinkTitle.fetch(url) else { return }
            guard let self, let cur = self.data.links.first(where: { $0.id == id }), cur.title == placeholder else { return }
            self.renameLink(id, title)
        }
    }

    /// 수정 창: 이름과 주소를 함께 바꾼다. 주소로 볼 수 없으면 false. 이름을 비우면 새 주소의 페이지 제목을 받아 온다.
    @discardableResult
    func updateLink(_ id: UUID, title: String, url input: String) -> Bool {
        guard let url = LinkTitle.normalize(input), let i = data.links.firstIndex(where: { $0.id == id }) else { return false }
        data.links[i].url = url.absoluteString
        if let t = Todo.normalizedTitle(title) {
            data.links[i].title = t
            persist()
        } else {
            let placeholder = url.host ?? url.absoluteString
            data.links[i].title = placeholder
            persist()
            fetchTitle(id, url, placeholder: placeholder)
        }
        return true
    }

    func renameLink(_ id: UUID, _ title: String) {
        guard let t = Todo.normalizedTitle(title), let i = data.links.firstIndex(where: { $0.id == id }), data.links[i].title != t else { return }
        data.links[i].title = t
        persist()
    }

    func deleteLink(_ id: UUID) {
        data.links.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Confluence

    func refreshConfluence(base: URL, email: String, token: String) async {
        guard !starredLoading else { return }
        starredLoading = true
        defer { starredLoading = false }
        do {
            starred = try await ConfluenceClient.fetchStarred(baseURL: base, email: email, token: token)
            starredError = nil
            starredUpdatedAt = Date()
        } catch {
            // 갱신 주기 변경/뷰 사라짐으로 취소된 경우는 오류가 아님 (refreshJira 와 같다)
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            starredError = (error as? ConfluenceError)?.userMessage ?? error.localizedDescription
        }
    }

    /// 데모 fixture 의 별표 문서.
    func setDemoStarred(_ pages: [StarredPage]) {
        starred = pages
        starredError = nil
        starredUpdatedAt = Date()
    }

    func setConfluenceError(_ message: String) { starredError = message }
}
