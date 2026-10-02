# TaskWidget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS 메뉴바 상주 플로팅 위젯. 할 일(마감일) + Jira 미완료 이슈 + Claude Code 세션 기반 하루 업무 요약.

**Architecture:** SwiftPM 패키지 하나. `TaskWidgetCore`(순수 Foundation 라이브러리, 전부 테스트)와 `TaskWidget`(AppKit NSPanel + SwiftUI 실행 파일). 같은 바이너리가 `--hook` 인자로 실행되면 Claude Code 훅으로 동작해 `activity.jsonl`에 한 줄 append. 요약은 `claude -p` 프로세스 호출.

**Tech Stack:** Swift 5 language mode (tools 5.9), SwiftUI, AppKit, Security(Keychain), ServiceManagement, UserNotifications, XCTest. 외부 패키지 0.

**Spec:** `docs/superpowers/specs/2026-10-02-task-widget-design.md`

## Global Constraints

- `swift-tools-version: 5.9`, `platforms: [.macOS(.v14)]`, `swiftLanguageVersions: [.v5]`
- 외부 패키지 의존성 없음
- `TaskWidgetCore`는 `import Foundation`(및 `Security`)만. AppKit/SwiftUI import 금지
- 데이터 디렉터리: `~/Library/Application Support/TaskWidget/` (`todos.json`, `activity.jsonl`, `worklog/`, `summaries/`, `logs/`)
- Keychain service: `com.lsm0506.TaskWidget.jira`, account = Jira 이메일
- Bundle ID `com.lsm0506.TaskWidget`, `LSUIElement = true`
- 기본 JQL: `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`, `maxResults=100`
- 훅 캡: prompt 2,000자 / last_assistant_message 4,000자. 프롬프트 캡: prompt 400 / stop 1,200 / 총 80,000자
- claude 타임아웃 180초, git 10초, Jira 요청 20초
- UI 문자열 한국어. 코드 식별자/주석 영어 또는 한국어 자유
- Makefile 레시피는 반드시 TAB 들여쓰기
- 커밋 메시지 끝에 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`

## Review Focus

1. 훅 입력에서 `prompt`/`last_assistant_message`가 null이거나 `cwd`가 없을 때 → 크래시 없이 아무것도 안 쓰고 exit 0 (Task 8 `testNonStringFieldsIgnored`)
2. 활동 기록 시각이 로컬 자정 직후(00:30 KST = 전날 15:30Z)일 때 → 로컬 달력 기준으로 오늘에 포함 (Task 8 `testDayFilterUsesLocalCalendar`)
3. `settings.json`의 `hooks.Stop`이 배열이 아닌 잘못된 값일 때 → 설치가 크래시하지 않고 그 이벤트를 유효한 배열로 교체 (Task 12 `testMalformedEventValueReplaced`)
4. Jira 응답에 `priority: null`과 모르는 `statusCategory`가 섞여 있을 때 → 디코딩 성공, 모르는 카테고리는 맨 뒤 (Task 6 `testDecodeNullPriorityAndUnknownCategory`)
5. Todo `dueDate`가 `"2026-02-30"`, `"abc"` 같은 잘못된 문자열일 때 → 배지는 `.none`, 표시 깨지지 않음 (Task 3 `testInvalidDueDateIsNone`)

---

## File Structure

```
task-manager/
  Package.swift
  Makefile
  README.md
  Resources/Info.plist
  Sources/TaskWidgetCore/
    Paths.swift              데이터 디렉터리 URL 상수, ensureDirectories()
    Models.swift             Todo, JiraIssue, Summary, ActivityRecord, WorklogEntry, DayKey
    TodoStore.swift          todos.json 로드/저장/손상 백업
    DueBadge.swift           마감 배지 계산, 정렬
    Schedule.swift           nextFireDate
    Settings.swift           SettingsKey 상수 + UserDefaults 래퍼
    Keychain.swift           SecItem get/set/delete
    JiraClient.swift         Jira REST 호출, 디코딩, 정렬/그룹
    ProcessRunner.swift      Process 동기 실행 (stdin/stdout/stderr/timeout)
    GitActivity.swift        프로젝트별 오늘 커밋
    ActivityLog.swift        훅 입력 파싱, append, 날짜별 read, handleHook
    Worklog.swift            worklog md 읽기/파싱
    SummaryPrompt.swift      SummaryInput, 필터/캡, 프롬프트 조립
    ClaudeRunner.swift       claude 바이너리 탐색, -p 실행, SummaryError
    SummaryService.swift     수집→프롬프트→실행→저장
    ClaudeIntegration.swift  settings.json 훅 merge/제거/상태, SKILL.md 설치
  Sources/TaskWidget/
    main.swift               --hook 분기, NSApplication 실행
    AppDelegate.swift        상태바, 패널, 메뉴, 스케줄러 소유
    AppState.swift           ObservableObject: todos/jira/summary 상태와 동작
    FloatingPanel.swift      NSPanel 서브클래스
    Scheduler.swift          타이머/웨이크/catch-up/알림
    Views/FontScale.swift    환경값
    Views/RootView.swift
    Views/TasksView.swift
    Views/TodoRow.swift
    Views/DuePopover.swift
    Views/JiraSection.swift
    Views/SummaryView.swift
    Views/MarkdownText.swift
    Views/SettingsView.swift
  Tests/TaskWidgetCoreTests/
    Fixtures/activity-sample.jsonl
    Fixtures/worklog-sample.md
    Fixtures/settings-with-hooks.json
    Fixtures/jira-search.json
    *Tests.swift
```

---

### Task 1: 패키지 스캐폴드, Paths, Makefile, Info.plist

**Files:**
- Create: `Package.swift`
- Create: `Sources/TaskWidgetCore/Paths.swift`
- Create: `Sources/TaskWidget/main.swift`
- Create: `Tests/TaskWidgetCoreTests/PathsTests.swift`
- Create: `Resources/Info.plist`
- Create: `Makefile`

**Interfaces:**
- Produces: `Paths.dataDir`, `Paths.todosFile`, `Paths.activityFile`, `Paths.worklogDir`, `Paths.summariesDir`, `Paths.logsDir`, `Paths.claudeDir`, `Paths.ensureDirectories() throws`

- [ ] **Step 1: Package.swift 작성**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TaskWidget",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TaskWidgetCore"),
        .executableTarget(name: "TaskWidget", dependencies: ["TaskWidgetCore"]),
        .testTarget(
            name: "TaskWidgetCoreTests",
            dependencies: ["TaskWidgetCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
```

- [ ] **Step 2: 실패하는 테스트 작성** — `Tests/TaskWidgetCoreTests/PathsTests.swift`

```swift
import XCTest
@testable import TaskWidgetCore

final class PathsTests: XCTestCase {
    func testDataDirUnderApplicationSupport() {
        XCTAssertEqual(Paths.dataDir.lastPathComponent, "TaskWidget")
        XCTAssertTrue(Paths.dataDir.path.contains("/Library/Application Support/"))
    }

    func testFileLocations() {
        XCTAssertEqual(Paths.todosFile.lastPathComponent, "todos.json")
        XCTAssertEqual(Paths.activityFile.lastPathComponent, "activity.jsonl")
        XCTAssertEqual(Paths.worklogDir.lastPathComponent, "worklog")
        XCTAssertEqual(Paths.summariesDir.lastPathComponent, "summaries")
        XCTAssertEqual(Paths.logsDir.lastPathComponent, "logs")
        XCTAssertEqual(Paths.claudeDir.lastPathComponent, ".claude")
    }
}
```

`Tests/TaskWidgetCoreTests/Fixtures/.gitkeep` 빈 파일도 만든다 (resources 디렉터리가 있어야 빌드됨).

- [ ] **Step 3: 테스트 실패 확인**

Run: `swift test 2>&1 | tail -5`
Expected: 컴파일 에러 `cannot find 'Paths' in scope`

- [ ] **Step 4: Paths.swift 작성**

```swift
import Foundation

public enum Paths {
    public static var dataDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TaskWidget", isDirectory: true)
    }
    public static var todosFile: URL { dataDir.appendingPathComponent("todos.json") }
    public static var activityFile: URL { dataDir.appendingPathComponent("activity.jsonl") }
    public static var worklogDir: URL { dataDir.appendingPathComponent("worklog", isDirectory: true) }
    public static var summariesDir: URL { dataDir.appendingPathComponent("summaries", isDirectory: true) }
    public static var logsDir: URL { dataDir.appendingPathComponent("logs", isDirectory: true) }
    public static var claudeDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    public static func ensureDirectories() throws {
        for dir in [dataDir, worklogDir, summariesDir, logsDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
```

- [ ] **Step 5: main.swift 임시 작성**

```swift
import Foundation
import TaskWidgetCore

print("TaskWidget data dir: \(Paths.dataDir.path)")
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 2 tests, with 0 failures`

- [ ] **Step 7: Info.plist 작성** — `Resources/Info.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>TaskWidget</string>
	<key>CFBundleIdentifier</key>
	<string>com.lsm0506.TaskWidget</string>
	<key>CFBundleName</key>
	<string>TaskWidget</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 8: Makefile 작성** (레시피 줄은 TAB)

```make
APP := build/TaskWidget.app
BIN_DIR := $(shell swift build -c release --show-bin-path)

.PHONY: build test app install run clean

build:
	swift build

test:
	swift test

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN_DIR)/TaskWidget $(APP)/Contents/MacOS/TaskWidget
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

install: app
	-pkill -x TaskWidget
	rm -rf /Applications/TaskWidget.app
	cp -R $(APP) /Applications/

run: app
	open $(APP)

clean:
	rm -rf .build build
```

- [ ] **Step 9: make app 확인**

Run: `make app && ls build/TaskWidget.app/Contents/MacOS/ && build/TaskWidget.app/Contents/MacOS/TaskWidget`
Expected: `TaskWidget` 파일 존재, 실행 시 `TaskWidget data dir: /Users/.../Library/Application Support/TaskWidget` 출력

- [ ] **Step 10: 커밋**

```bash
git add Package.swift Sources Tests Resources Makefile
git commit -m "chore: SwiftPM 스캐폴드, Paths, Makefile, Info.plist

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Models, DayKey, TodoStore

**Files:**
- Create: `Sources/TaskWidgetCore/Models.swift`
- Create: `Sources/TaskWidgetCore/TodoStore.swift`
- Test: `Tests/TaskWidgetCoreTests/ModelsTests.swift`, `Tests/TaskWidgetCoreTests/TodoStoreTests.swift`

**Interfaces:**
- Produces: `Todo`, `Todo.normalizedTitle(_:) -> String?`, `JiraIssue`, `Summary`, `ActivityRecord` (+ `.project`), `WorklogEntry`, `DayKey.string(from:calendar:)`, `DayKey.date(from:calendar:)`, `TodoStore(fileURL:)`, `.load() -> [Todo]`, `.save(_:) throws`

- [ ] **Step 1: 실패하는 테스트 작성** — `Tests/TaskWidgetCoreTests/ModelsTests.swift`

```swift
import XCTest
@testable import TaskWidgetCore

final class ModelsTests: XCTestCase {
    let seoul: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func testDayKeyRoundTrip() {
        let d = DayKey.date(from: "2026-10-02", calendar: seoul)!
        XCTAssertEqual(DayKey.string(from: d, calendar: seoul), "2026-10-02")
    }

    func testDayKeyRejectsInvalid() {
        XCTAssertNil(DayKey.date(from: "2026-02-30", calendar: seoul))
        XCTAssertNil(DayKey.date(from: "abc", calendar: seoul))
        XCTAssertNil(DayKey.date(from: "2026-10", calendar: seoul))
    }

    func testNormalizedTitle() {
        XCTAssertEqual(Todo.normalizedTitle("  배포 문서  "), "배포 문서")
        XCTAssertNil(Todo.normalizedTitle("   "))
        XCTAssertNil(Todo.normalizedTitle(""))
    }

    func testActivityRecordProject() {
        let r = ActivityRecord(ts: Date(), event: "prompt", session: "s", cwd: "/Users/x/projects/mrs-cms", text: "t")
        XCTAssertEqual(r.project, "mrs-cms")
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter ModelsTests 2>&1 | tail -5`
Expected: 컴파일 에러 `cannot find 'DayKey'`

- [ ] **Step 3: Models.swift 작성**

```swift
import Foundation

public struct Todo: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var done: Bool
    public var createdAt: Date
    public var completedAt: Date?
    /// "yyyy-MM-dd" 로컬 날짜. 시각 없음.
    public var dueDate: String?

    public init(id: UUID = UUID(), title: String, done: Bool = false, createdAt: Date = Date(),
                completedAt: Date? = nil, dueDate: String? = nil) {
        self.id = id
        self.title = title
        self.done = done
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.dueDate = dueDate
    }

    /// 앞뒤 공백 제거. 비면 nil.
    public static func normalizedTitle(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

public struct JiraIssue: Codable, Identifiable, Equatable {
    public var id: String              // issue key
    public var summary: String
    public var status: String          // fields.status.name
    public var statusCategory: String  // new | indeterminate | done | (unknown)
    public var priority: String?
    public var updated: Date

    public init(id: String, summary: String, status: String, statusCategory: String,
                priority: String?, updated: Date) {
        self.id = id
        self.summary = summary
        self.status = status
        self.statusCategory = statusCategory
        self.priority = priority
        self.updated = updated
    }
}

public struct Summary: Equatable {
    public var dayKey: String
    public var markdown: String
    public var generatedAt: Date

    public init(dayKey: String, markdown: String, generatedAt: Date) {
        self.dayKey = dayKey
        self.markdown = markdown
        self.generatedAt = generatedAt
    }
}

public struct ActivityRecord: Codable, Equatable {
    public var ts: Date
    public var event: String   // "prompt" | "stop"
    public var session: String
    public var cwd: String
    public var text: String

    public init(ts: Date, event: String, session: String, cwd: String, text: String) {
        self.ts = ts
        self.event = event
        self.session = session
        self.cwd = cwd
        self.text = text
    }

    public var project: String { (cwd as NSString).lastPathComponent }
}

public struct WorklogEntry: Equatable {
    public var time: String     // "HH:mm"
    public var project: String
    public var body: String

    public init(time: String, project: String, body: String) {
        self.time = time
        self.project = project
        self.body = body
    }
}

public enum DayKey {
    public static func string(from date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        guard let d = calendar.date(from: c) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: d)
        guard back.year == parts[0], back.month == parts[1], back.day == parts[2] else { return nil }
        return d
    }
}
```

- [ ] **Step 4: ModelsTests 통과 확인**

Run: `swift test --filter ModelsTests 2>&1 | tail -3`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: TodoStore 실패 테스트 작성** — `Tests/TaskWidgetCoreTests/TodoStoreTests.swift`

```swift
import XCTest
@testable import TaskWidgetCore

final class TodoStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMissingFileIsEmpty() {
        let store = TodoStore(fileURL: dir.appendingPathComponent("todos.json"))
        XCTAssertEqual(store.load(), [])
    }

    func testRoundTrip() throws {
        let store = TodoStore(fileURL: dir.appendingPathComponent("todos.json"))
        let todos = [
            Todo(title: "a", dueDate: "2026-10-03"),
            Todo(title: "b", done: true, completedAt: Date(timeIntervalSince1970: 1_700_000_000)),
        ]
        try store.save(todos)
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].title, "a")
        XCTAssertEqual(loaded[0].dueDate, "2026-10-03")
        XCTAssertTrue(loaded[1].done)
        XCTAssertEqual(loaded[1].completedAt?.timeIntervalSince1970 ?? 0, 1_700_000_000, accuracy: 1)
    }

    func testCorruptFileIsBackedUpAndEmpty() throws {
        let file = dir.appendingPathComponent("todos.json")
        try "not json".write(to: file, atomically: true, encoding: .utf8)
        let store = TodoStore(fileURL: file)
        XCTAssertEqual(store.load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("todos.corrupt-") }
        XCTAssertEqual(backups.count, 1)
    }

    func testSaveCreatesParentDirectory() throws {
        let store = TodoStore(fileURL: dir.appendingPathComponent("nested/todos.json"))
        try store.save([Todo(title: "x")])
        XCTAssertEqual(store.load().count, 1)
    }
}
```

- [ ] **Step 6: 테스트 실패 확인**

Run: `swift test --filter TodoStoreTests 2>&1 | tail -3`
Expected: 컴파일 에러 `cannot find 'TodoStore'`

- [ ] **Step 7: TodoStore.swift 작성**

```swift
import Foundation

public struct TodoStore {
    public let fileURL: URL

    public init(fileURL: URL = Paths.todosFile) {
        self.fileURL = fileURL
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// 파일 없으면 []. 파싱 실패면 todos.corrupt-<ts>.json 으로 옮기고 [].
    public func load() -> [Todo] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        if let todos = try? Self.decoder.decode([Todo].self, from: data) { return todos }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("todos.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        return []
    }

    public func save(_ todos: [Todo]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(todos)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 8: 테스트 통과 확인**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 10 tests, with 0 failures`

- [ ] **Step 9: 커밋**

```bash
git add Sources/TaskWidgetCore/Models.swift Sources/TaskWidgetCore/TodoStore.swift Tests
git commit -m "feat(core): 모델, DayKey, TodoStore

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: DueBadge (마감 배지, 정렬)

**Files:**
- Create: `Sources/TaskWidgetCore/DueBadge.swift`
- Test: `Tests/TaskWidgetCoreTests/DueBadgeTests.swift`

**Interfaces:**
- Consumes: `Todo`, `DayKey`
- Produces: `DueStyle { none, overdue, today, normal }`, `DueBadge.badge(due: String?, today: Date, calendar:) -> (text: String, style: DueStyle)`, `DueBadge.sorted(_ todos: [Todo]) -> [Todo]`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import TaskWidgetCore

final class DueBadgeTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    var today: Date { DayKey.date(from: "2026-10-02", calendar: cal)! }

    func badge(_ due: String?) -> (text: String, style: DueStyle) {
        DueBadge.badge(due: due, today: today, calendar: cal)
    }

    func testNil() { XCTAssertEqual(badge(nil).style, .none) }

    func testOverdue() {
        let b = badge("2026-10-01")
        XCTAssertEqual(b.text, "D+1")
        XCTAssertEqual(b.style, .overdue)
    }

    func testToday() {
        let b = badge("2026-10-02")
        XCTAssertEqual(b.text, "오늘")
        XCTAssertEqual(b.style, .today)
    }

    func testWithinWeek() {
        XCTAssertEqual(badge("2026-10-03").text, "D-1")
        XCTAssertEqual(badge("2026-10-09").text, "D-7")
        XCTAssertEqual(badge("2026-10-09").style, .normal)
    }

    func testBeyondWeekShowsMonthDay() {
        XCTAssertEqual(badge("2026-10-10").text, "10/10")
        XCTAssertEqual(badge("2026-11-05").text, "11/5")
    }

    func testTodayParameterIsNotMidnightSensitive() {
        // today 가 23:50 이어도 같은 날이면 "오늘"
        let late = cal.date(byAdding: .minute, value: 23 * 60 + 50, to: today)!
        XCTAssertEqual(DueBadge.badge(due: "2026-10-02", today: late, calendar: cal).style, .today)
    }

    func testInvalidDueDateIsNone() {
        XCTAssertEqual(badge("2026-02-30").style, .none)
        XCTAssertEqual(badge("abc").style, .none)
    }

    func testSortedDueFirstThenNilThenCreated() {
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 10)
        let a = Todo(title: "a", createdAt: t1, dueDate: nil)
        let b = Todo(title: "b", createdAt: t0, dueDate: nil)
        let c = Todo(title: "c", createdAt: t1, dueDate: "2026-10-05")
        let d = Todo(title: "d", createdAt: t0, dueDate: "2026-10-05")
        let e = Todo(title: "e", createdAt: t1, dueDate: "2026-10-01")
        let sorted = DueBadge.sorted([a, b, c, d, e]).map(\.title)
        XCTAssertEqual(sorted, ["e", "d", "c", "b", "a"])
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter DueBadgeTests 2>&1 | tail -3`
Expected: 컴파일 에러 `cannot find 'DueBadge'`

- [ ] **Step 3: DueBadge.swift 작성**

```swift
import Foundation

public enum DueStyle: Equatable {
    case none, overdue, today, normal
}

public enum DueBadge {
    /// 잘못된 dueDate 문자열은 nil 처럼 취급.
    public static func badge(due: String?, today: Date, calendar: Calendar = .current) -> (text: String, style: DueStyle) {
        guard let due, let dueDate = DayKey.date(from: due, calendar: calendar) else { return ("", .none) }
        let start = calendar.startOfDay(for: today)
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: dueDate)).day ?? 0
        switch days {
        case ..<0:
            return ("D+\(-days)", .overdue)
        case 0:
            return ("오늘", .today)
        case 1...7:
            return ("D-\(days)", .normal)
        default:
            let c = calendar.dateComponents([.month, .day], from: dueDate)
            return ("\(c.month!)/\(c.day!)", .normal)
        }
    }

    /// dueDate 오름차순, nil 은 뒤, 동률은 createdAt 오름차순. "yyyy-MM-dd" 는 문자열 비교로 충분.
    public static func sorted(_ todos: [Todo]) -> [Todo] {
        todos.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case (nil, nil): return a.createdAt < b.createdAt
            case (nil, _): return false
            case (_, nil): return true
            case let (x?, y?): return x == y ? a.createdAt < b.createdAt : x < y
            }
        }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter DueBadgeTests 2>&1 | tail -3`
Expected: `Executed 8 tests, with 0 failures`

- [ ] **Step 5: 커밋**

```bash
git add Sources/TaskWidgetCore/DueBadge.swift Tests/TaskWidgetCoreTests/DueBadgeTests.swift
git commit -m "feat(core): 마감 배지 계산과 정렬

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Schedule.nextFireDate

**Files:**
- Create: `Sources/TaskWidgetCore/Schedule.swift`
- Test: `Tests/TaskWidgetCoreTests/ScheduleTests.swift`

**Interfaces:**
- Produces: `Schedule.nextFireDate(after now: Date, hour: Int, minute: Int, calendar: Calendar) -> Date`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import TaskWidgetCore

final class ScheduleTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func at(_ day: String, _ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        var c = cal.dateComponents([.year, .month, .day], from: DayKey.date(from: day, calendar: cal)!)
        c.hour = h; c.minute = m; c.second = s
        return cal.date(from: c)!
    }

    func testBeforeScheduledTimeFiresToday() {
        let next = Schedule.nextFireDate(after: at("2026-10-02", 17, 59), hour: 18, minute: 0, calendar: cal)
        XCTAssertEqual(next, at("2026-10-02", 18, 0))
    }

    func testAfterScheduledTimeFiresTomorrow() {
        let next = Schedule.nextFireDate(after: at("2026-10-02", 18, 1), hour: 18, minute: 0, calendar: cal)
        XCTAssertEqual(next, at("2026-10-03", 18, 0))
    }

    func testExactlyAtScheduledTimeFiresTomorrow() {
        let next = Schedule.nextFireDate(after: at("2026-10-02", 18, 0, 0), hour: 18, minute: 0, calendar: cal)
        XCTAssertEqual(next, at("2026-10-03", 18, 0))
    }

    func testMonthBoundary() {
        let next = Schedule.nextFireDate(after: at("2026-10-31", 20, 0), hour: 18, minute: 30, calendar: cal)
        XCTAssertEqual(next, at("2026-11-01", 18, 30))
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter ScheduleTests 2>&1 | tail -3`
Expected: 컴파일 에러 `cannot find 'Schedule'`

- [ ] **Step 3: Schedule.swift 작성**

```swift
import Foundation

public enum Schedule {
    /// 오늘 hour:minute 가 now 보다 뒤면 오늘, 아니면(같거나 지났으면) 내일.
    public static func nextFireDate(after now: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date {
        var c = calendar.dateComponents([.year, .month, .day], from: now)
        c.hour = hour
        c.minute = minute
        c.second = 0
        let today = calendar.date(from: c)!
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today)!
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter ScheduleTests 2>&1 | tail -3`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: 커밋**

```bash
git add Sources/TaskWidgetCore/Schedule.swift Tests/TaskWidgetCoreTests/ScheduleTests.swift
git commit -m "feat(core): 요약 스케줄 다음 발화 시각 계산

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Settings (UserDefaults) + Keychain

**Files:**
- Create: `Sources/TaskWidgetCore/Settings.swift`
- Create: `Sources/TaskWidgetCore/Keychain.swift`
- Test: `Tests/TaskWidgetCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces: `SettingsKey.*` 문자열 상수 (SwiftUI `@AppStorage`와 공유), `Settings.shared`, `Settings(defaults:)`, 프로퍼티 `opacity, hoverOpaque, theme, fontScale, alwaysOnTop, allSpaces, jiraBaseURL, jiraEmail, jiraRefreshMinutes, jiraJQL, summaryHour, summaryMinute, summaryNotify, claudeModel, claudePath, lastTab`, `Settings.defaultJiraBaseURL`
- Produces: `Keychain.get(account:) -> String?`, `Keychain.set(_:account:) throws`, `Keychain.delete(account:)`, `KeychainError.status(OSStatus)`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import TaskWidgetCore

final class SettingsTests: XCTestCase {
    var suite: String!
    var defaults: UserDefaults!

    override func setUp() {
        suite = "TaskWidgetTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaults() {
        let s = Settings(defaults: defaults)
        XCTAssertEqual(s.opacity, 1.0)
        XCTAssertTrue(s.hoverOpaque)
        XCTAssertEqual(s.theme, "system")
        XCTAssertEqual(s.fontScale, 1.0)
        XCTAssertTrue(s.alwaysOnTop)
        XCTAssertTrue(s.allSpaces)
        XCTAssertEqual(s.jiraBaseURL, "https://midasitweb-jira.atlassian.net")
        XCTAssertEqual(s.jiraEmail, "")
        XCTAssertEqual(s.jiraRefreshMinutes, 5)
        XCTAssertEqual(s.jiraJQL, "")
        XCTAssertEqual(s.summaryHour, 18)
        XCTAssertEqual(s.summaryMinute, 0)
        XCTAssertTrue(s.summaryNotify)
        XCTAssertEqual(s.claudeModel, "")
        XCTAssertEqual(s.claudePath, "")
        XCTAssertEqual(s.lastTab, "tasks")
    }

    func testSetAndGet() {
        let s = Settings(defaults: defaults)
        s.opacity = 0.7
        s.summaryHour = 9
        s.summaryMinute = 30
        s.jiraEmail = "a@b.c"
        s.hoverOpaque = false
        XCTAssertEqual(s.opacity, 0.7)
        XCTAssertEqual(s.summaryHour, 9)
        XCTAssertEqual(s.summaryMinute, 30)
        XCTAssertEqual(s.jiraEmail, "a@b.c")
        XCTAssertFalse(s.hoverOpaque)
    }

    func testKeysMatchAppStorageNames() {
        // SwiftUI 쪽 @AppStorage 가 같은 문자열을 쓰므로 상수 값이 바뀌면 안 된다
        XCTAssertEqual(SettingsKey.opacity, "opacity")
        XCTAssertEqual(SettingsKey.summaryHour, "summaryHour")
        XCTAssertEqual(SettingsKey.jiraJQL, "jiraJQL")
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter SettingsTests 2>&1 | tail -3`
Expected: 컴파일 에러 `cannot find 'Settings'`

- [ ] **Step 3: Settings.swift 작성**

```swift
import Foundation

public enum SettingsKey {
    public static let opacity = "opacity"
    public static let hoverOpaque = "hoverOpaque"
    public static let theme = "theme"
    public static let fontScale = "fontScale"
    public static let alwaysOnTop = "alwaysOnTop"
    public static let allSpaces = "allSpaces"
    public static let jiraBaseURL = "jiraBaseURL"
    public static let jiraEmail = "jiraEmail"
    public static let jiraRefreshMinutes = "jiraRefreshMinutes"
    public static let jiraJQL = "jiraJQL"
    public static let summaryHour = "summaryHour"
    public static let summaryMinute = "summaryMinute"
    public static let summaryNotify = "summaryNotify"
    public static let claudeModel = "claudeModel"
    public static let claudePath = "claudePath"
    public static let lastTab = "lastTab"
    public static let todoSectionCollapsed = "todoSectionCollapsed"
    public static let jiraSectionCollapsed = "jiraSectionCollapsed"
}

public final class Settings {
    public static let shared = Settings()
    public static let defaultJiraBaseURL = "https://midasitweb-jira.atlassian.net"

    private let d: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.d = defaults
    }

    private func double(_ k: String, _ def: Double) -> Double { d.object(forKey: k) as? Double ?? def }
    private func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
    private func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }
    private func string(_ k: String, _ def: String) -> String { d.string(forKey: k) ?? def }

    public var opacity: Double {
        get { double(SettingsKey.opacity, 1.0) }
        set { d.set(newValue, forKey: SettingsKey.opacity) }
    }
    public var hoverOpaque: Bool {
        get { bool(SettingsKey.hoverOpaque, true) }
        set { d.set(newValue, forKey: SettingsKey.hoverOpaque) }
    }
    public var theme: String {
        get { string(SettingsKey.theme, "system") }
        set { d.set(newValue, forKey: SettingsKey.theme) }
    }
    public var fontScale: Double {
        get { double(SettingsKey.fontScale, 1.0) }
        set { d.set(newValue, forKey: SettingsKey.fontScale) }
    }
    public var alwaysOnTop: Bool {
        get { bool(SettingsKey.alwaysOnTop, true) }
        set { d.set(newValue, forKey: SettingsKey.alwaysOnTop) }
    }
    public var allSpaces: Bool {
        get { bool(SettingsKey.allSpaces, true) }
        set { d.set(newValue, forKey: SettingsKey.allSpaces) }
    }
    public var jiraBaseURL: String {
        get { string(SettingsKey.jiraBaseURL, Self.defaultJiraBaseURL) }
        set { d.set(newValue, forKey: SettingsKey.jiraBaseURL) }
    }
    public var jiraEmail: String {
        get { string(SettingsKey.jiraEmail, "") }
        set { d.set(newValue, forKey: SettingsKey.jiraEmail) }
    }
    public var jiraRefreshMinutes: Int {
        get { int(SettingsKey.jiraRefreshMinutes, 5) }
        set { d.set(newValue, forKey: SettingsKey.jiraRefreshMinutes) }
    }
    public var jiraJQL: String {
        get { string(SettingsKey.jiraJQL, "") }
        set { d.set(newValue, forKey: SettingsKey.jiraJQL) }
    }
    public var summaryHour: Int {
        get { int(SettingsKey.summaryHour, 18) }
        set { d.set(newValue, forKey: SettingsKey.summaryHour) }
    }
    public var summaryMinute: Int {
        get { int(SettingsKey.summaryMinute, 0) }
        set { d.set(newValue, forKey: SettingsKey.summaryMinute) }
    }
    public var summaryNotify: Bool {
        get { bool(SettingsKey.summaryNotify, true) }
        set { d.set(newValue, forKey: SettingsKey.summaryNotify) }
    }
    public var claudeModel: String {
        get { string(SettingsKey.claudeModel, "") }
        set { d.set(newValue, forKey: SettingsKey.claudeModel) }
    }
    public var claudePath: String {
        get { string(SettingsKey.claudePath, "") }
        set { d.set(newValue, forKey: SettingsKey.claudePath) }
    }
    public var lastTab: String {
        get { string(SettingsKey.lastTab, "tasks") }
        set { d.set(newValue, forKey: SettingsKey.lastTab) }
    }
}
```

- [ ] **Step 4: Keychain.swift 작성** (단위 테스트 없음. 로그인 키체인 접근은 Task 17 수동 확인)

```swift
import Foundation
import Security

public enum KeychainError: Error, Equatable {
    case status(OSStatus)
}

public enum Keychain {
    public static let service = "com.lsm0506.TaskWidget.jira"

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public static func get(account: String) -> String? {
        var q = baseQuery(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let q = baseQuery(account: account)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test --filter SettingsTests 2>&1 | tail -3`
Expected: `Executed 3 tests, with 0 failures`

- [ ] **Step 6: 커밋**

```bash
git add Sources/TaskWidgetCore/Settings.swift Sources/TaskWidgetCore/Keychain.swift Tests/TaskWidgetCoreTests/SettingsTests.swift
git commit -m "feat(core): 설정 래퍼와 Keychain

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: JiraClient

**Files:**
- Create: `Sources/TaskWidgetCore/JiraClient.swift`
- Create: `Tests/TaskWidgetCoreTests/Fixtures/jira-search.json`
- Test: `Tests/TaskWidgetCoreTests/JiraClientTests.swift`

**Interfaces:**
- Consumes: `JiraIssue`
- Produces: `JiraError { unauthorized, badQuery(String), http(Int), network(String) }` + `.userMessage`, `JiraClient(baseURL:email:token:session:)`, `JiraClient.defaultJQL`, `JiraClient.effectiveJQL(custom:) -> String`, `fetchMyOpenIssues(jql:) async throws -> [JiraIssue]`, `whoAmI() async throws -> String`, `JiraClient.decodeSearch(_ data: Data) throws -> [JiraIssue]`, `JiraClient.sortedForDisplay(_:) -> [JiraIssue]`, `JiraClient.Group { status, issues }`, `JiraClient.grouped(_:) -> [Group]`

- [ ] **Step 1: fixture 작성** — `Tests/TaskWidgetCoreTests/Fixtures/jira-search.json`

```json
{
  "isLast": true,
  "issues": [
    {
      "key": "NMRS-20450",
      "fields": {
        "summary": "CDC 로그 Athena 조회 스크립트 정리",
        "status": { "name": "할 일", "statusCategory": { "key": "new" } },
        "priority": { "name": "High" },
        "updated": "2026-10-01T09:00:00.000+0900"
      }
    },
    {
      "key": "NMRS-20414",
      "fields": {
        "summary": "지원서 PDF 다운로드 성능 개선",
        "status": { "name": "진행 중", "statusCategory": { "key": "indeterminate" } },
        "priority": { "name": "Highest" },
        "updated": "2026-10-02T11:30:00.000+0900"
      }
    },
    {
      "key": "NMRS-20388",
      "fields": {
        "summary": "공고 복사 시 전형 단계 누락",
        "status": { "name": "진행 중", "statusCategory": { "key": "indeterminate" } },
        "priority": null,
        "updated": "2026-10-02T08:00:00.000+0900"
      }
    },
    {
      "key": "NMRS-20001",
      "fields": {
        "summary": "알 수 없는 카테고리",
        "status": { "name": "보류", "statusCategory": { "key": "weird" } },
        "priority": { "name": "Low" },
        "updated": "2026-10-02T12:00:00.000+0900"
      }
    }
  ]
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

```swift
import XCTest
@testable import TaskWidgetCore

final class JiraClientTests: XCTestCase {
    func fixture() throws -> Data {
        let url = Bundle.module.url(forResource: "jira-search", withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testDecodeNullPriorityAndUnknownCategory() throws {
        let issues = try JiraClient.decodeSearch(try fixture())
        XCTAssertEqual(issues.count, 4)
        let i = issues.first { $0.id == "NMRS-20388" }!
        XCTAssertNil(i.priority)
        XCTAssertEqual(i.status, "진행 중")
        XCTAssertEqual(i.statusCategory, "indeterminate")
        XCTAssertEqual(issues.first { $0.id == "NMRS-20001" }!.statusCategory, "weird")
    }

    func testDecodeUpdatedDate() throws {
        let issues = try JiraClient.decodeSearch(try fixture())
        let i = issues.first { $0.id == "NMRS-20414" }!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: i.updated)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 10, 2, 11, 30])
    }

    func testSortedForDisplay() throws {
        let sorted = JiraClient.sortedForDisplay(try JiraClient.decodeSearch(try fixture())).map(\.id)
        // 진행 중(updated desc) -> 할 일 -> 모르는 카테고리
        XCTAssertEqual(sorted, ["NMRS-20414", "NMRS-20388", "NMRS-20450", "NMRS-20001"])
    }

    func testGrouped() throws {
        let groups = JiraClient.grouped(try JiraClient.decodeSearch(try fixture()))
        XCTAssertEqual(groups.map(\.status), ["진행 중", "할 일", "보류"])
        XCTAssertEqual(groups[0].issues.count, 2)
    }

    func testEffectiveJQL() {
        XCTAssertEqual(JiraClient.effectiveJQL(custom: ""), JiraClient.defaultJQL)
        XCTAssertEqual(JiraClient.effectiveJQL(custom: "   \n"), JiraClient.defaultJQL)
        XCTAssertEqual(JiraClient.effectiveJQL(custom: "project = NMRS"), "project = NMRS")
    }

    func testErrorMessages() {
        XCTAssertEqual(JiraError.unauthorized.userMessage, "토큰 확인 필요 (401/403)")
        XCTAssertEqual(JiraError.badQuery("x").userMessage, "JQL 오류: x")
        XCTAssertEqual(JiraError.http(500).userMessage, "HTTP 500")
        XCTAssertEqual(JiraError.network("n").userMessage, "네트워크: n")
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `swift test --filter JiraClientTests 2>&1 | tail -3`
Expected: 컴파일 에러 `cannot find 'JiraClient'`

- [ ] **Step 4: JiraClient.swift 작성**

```swift
import Foundation

public enum JiraError: Error, Equatable {
    case unauthorized
    case badQuery(String)
    case http(Int)
    case network(String)

    public var userMessage: String {
        switch self {
        case .unauthorized: return "토큰 확인 필요 (401/403)"
        case .badQuery(let m): return "JQL 오류: \(m)"
        case .http(let c): return "HTTP \(c)"
        case .network(let m): return "네트워크: \(m)"
        }
    }
}

public struct JiraClient {
    public let baseURL: URL
    public let email: String
    public let token: String
    let session: URLSession

    public init(baseURL: URL, email: String, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.email = email
        self.token = token
        self.session = session
    }

    public static let defaultJQL = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"

    public static func effectiveJQL(custom: String) -> String {
        let t = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? defaultJQL : t
    }

    // MARK: - Network

    public func fetchMyOpenIssues(jql: String) async throws -> [JiraIssue] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("rest/api/3/search/jql"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "fields", value: "summary,status,priority,updated"),
            URLQueryItem(name: "maxResults", value: "100"),
        ]
        let data = try await get(comps.url!)
        return try Self.decodeSearch(data)
    }

    public func whoAmI() async throws -> String {
        struct Me: Decodable { let displayName: String }
        let data = try await get(baseURL.appendingPathComponent("rest/api/3/myself"))
        return try JSONDecoder().decode(Me.self, from: data).displayName
    }

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("Basic " + Data("\(email):\(token)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw JiraError.network(error.localizedDescription)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200...299: return data
        case 401, 403: throw JiraError.unauthorized
        case 400: throw JiraError.badQuery(Self.errorMessage(data))
        default: throw JiraError.http(code)
        }
    }

    static func errorMessage(_ data: Data) -> String {
        struct E: Decodable { let errorMessages: [String]? }
        return (try? JSONDecoder().decode(E.self, from: data))?.errorMessages?.first ?? "요청 오류"
    }

    // MARK: - Decoding

    struct SearchResponse: Decodable { let issues: [Issue] }
    struct Issue: Decodable { let key: String; let fields: Fields }
    struct Fields: Decodable {
        let summary: String
        let status: Status
        let priority: Priority?
        let updated: String
    }
    struct Status: Decodable { let name: String; let statusCategory: Category }
    struct Category: Decodable { let key: String }
    struct Priority: Decodable { let name: String }

    static let jiraDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return f
    }()

    public static func decodeSearch(_ data: Data) throws -> [JiraIssue] {
        let r = try JSONDecoder().decode(SearchResponse.self, from: data)
        return r.issues.map { i in
            JiraIssue(id: i.key,
                      summary: i.fields.summary,
                      status: i.fields.status.name,
                      statusCategory: i.fields.status.statusCategory.key,
                      priority: i.fields.priority?.name,
                      updated: jiraDate.date(from: i.fields.updated) ?? .distantPast)
        }
    }

    // MARK: - Display order

    static func categoryRank(_ key: String) -> Int {
        switch key {
        case "indeterminate": return 0
        case "new": return 1
        default: return 2
        }
    }

    public static func sortedForDisplay(_ issues: [JiraIssue]) -> [JiraIssue] {
        issues.sorted { a, b in
            let ra = categoryRank(a.statusCategory), rb = categoryRank(b.statusCategory)
            if ra != rb { return ra < rb }
            if a.status != b.status { return a.status < b.status }
            return a.updated > b.updated
        }
    }

    public struct Group: Equatable {
        public let status: String
        public let issues: [JiraIssue]
    }

    public static func grouped(_ issues: [JiraIssue]) -> [Group] {
        var out: [Group] = []
        for i in sortedForDisplay(issues) {
            if let last = out.last, last.status == i.status {
                out[out.count - 1] = Group(status: last.status, issues: last.issues + [i])
            } else {
                out.append(Group(status: i.status, issues: [i]))
            }
        }
        return out
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test --filter JiraClientTests 2>&1 | tail -3`
Expected: `Executed 6 tests, with 0 failures`

- [ ] **Step 6: 커밋**

```bash
git add Sources/TaskWidgetCore/JiraClient.swift Tests/TaskWidgetCoreTests/JiraClientTests.swift Tests/TaskWidgetCoreTests/Fixtures/jira-search.json
git commit -m "feat(core): Jira 클라이언트, 디코딩, 표시 정렬

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: ProcessRunner + GitActivity

**Files:**
- Create: `Sources/TaskWidgetCore/ProcessRunner.swift`
- Create: `Sources/TaskWidgetCore/GitActivity.swift`
- Test: `Tests/TaskWidgetCoreTests/ProcessRunnerTests.swift`, `Tests/TaskWidgetCoreTests/GitActivityTests.swift`

**Interfaces:**
- Produces: `ProcessResult { status: Int32, stdout: String, stderr: String, timedOut: Bool }`, `ProcessRunner.run(executable:arguments:stdin:currentDirectory:environment:timeout:) -> ProcessResult`, `GitActivity.commits(in cwd: String, on day: Date, calendar:timeout:) -> [String]`

- [ ] **Step 1: ProcessRunner 실패 테스트 작성**

```swift
import XCTest
@testable import TaskWidgetCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesStdout() {
        let r = ProcessRunner.run(executable: "/bin/echo", arguments: ["hi"], timeout: 5)
        XCTAssertEqual(r.status, 0)
        XCTAssertEqual(r.stdout, "hi\n")
        XCTAssertFalse(r.timedOut)
    }

    func testPassesStdin() {
        let r = ProcessRunner.run(executable: "/bin/cat", arguments: [], stdin: "abc\n한글", timeout: 5)
        XCTAssertEqual(r.stdout, "abc\n한글")
    }

    func testLargeStdinDoesNotDeadlock() {
        let big = String(repeating: "x", count: 300_000)
        let r = ProcessRunner.run(executable: "/bin/cat", arguments: [], stdin: big, timeout: 10)
        XCTAssertEqual(r.stdout.count, 300_000)
    }

    func testTimeout() {
        let r = ProcessRunner.run(executable: "/bin/sleep", arguments: ["5"], timeout: 0.3)
        XCTAssertTrue(r.timedOut)
    }

    func testNonZeroExitAndStderr() {
        let r = ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "echo err 1>&2; exit 3"], timeout: 5)
        XCTAssertEqual(r.status, 3)
        XCTAssertEqual(r.stderr, "err\n")
    }

    func testMissingExecutable() {
        let r = ProcessRunner.run(executable: "/nonexistent/bin", arguments: [], timeout: 5)
        XCTAssertEqual(r.status, -1)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter ProcessRunnerTests 2>&1 | tail -3`
Expected: 컴파일 에러 `cannot find 'ProcessRunner'`

- [ ] **Step 3: ProcessRunner.swift 작성**

```swift
import Foundation

public struct ProcessResult {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool
}

public enum ProcessRunner {
    /// 자식이 stdin 을 닫은 뒤 write 하면 SIGPIPE 로 프로세스가 죽는다. 한 번만 무시 설정.
    private static let ignoreSigpipe: Void = { signal(SIGPIPE, SIG_IGN) }()

    public static func run(executable: String,
                           arguments: [String],
                           stdin: String? = nil,
                           currentDirectory: URL? = nil,
                           environment: [String: String]? = nil,
                           timeout: TimeInterval) -> ProcessResult {
        _ = ignoreSigpipe
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        if let cwd = currentDirectory { p.currentDirectoryURL = cwd }
        if let env = environment { p.environment = env }

        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = inPipe

        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }

        do {
            try p.run()
        } catch {
            return ProcessResult(status: -1, stdout: "", stderr: "\(error)", timedOut: false)
        }

        // 읽기를 먼저 시작해야 큰 stdin 쓰기와 자식 stdout 쓰기가 서로 막히지 않는다.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        if let s = stdin { try? inPipe.fileHandleForWriting.write(contentsOf: Data(s.utf8)) }
        try? inPipe.fileHandleForWriting.close()

        let timedOut = done.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            p.terminate()
            _ = done.wait(timeout: .now() + 2)
        }
        group.wait()

        return ProcessResult(status: p.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self),
                             timedOut: timedOut)
    }
}
```

- [ ] **Step 4: ProcessRunner 테스트 통과 확인**

Run: `swift test --filter ProcessRunnerTests 2>&1 | tail -3`
Expected: `Executed 6 tests, with 0 failures`

- [ ] **Step 5: GitActivity 실패 테스트 작성**

```swift
import XCTest
@testable import TaskWidgetCore

final class GitActivityTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func git(_ args: [String]) {
        let r = ProcessRunner.run(executable: "/usr/bin/git", arguments: ["-C", dir.path] + args, timeout: 10)
        XCTAssertEqual(r.status, 0, r.stderr)
    }

    func testNonGitDirectoryIsEmpty() {
        XCTAssertEqual(GitActivity.commits(in: dir.path, on: Date()), [])
    }

    func testMissingDirectoryIsEmpty() {
        XCTAssertEqual(GitActivity.commits(in: "/nonexistent/path", on: Date()), [])
    }

    func testTodayCommitListed() throws {
        git(["init", "-q"])
        try "a".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        git(["add", "."])
        git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "feat: first commit"])
        let lines = GitActivity.commits(in: dir.path, on: Date())
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].hasSuffix(" feat: first commit"), lines[0])
    }

    func testYesterdayExcluded() throws {
        git(["init", "-q"])
        try "a".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        git(["add", "."])
        git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "old"])
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertEqual(GitActivity.commits(in: dir.path, on: yesterday), [])
    }
}
```

- [ ] **Step 6: 테스트 실패 확인**

Run: `swift test --filter GitActivityTests 2>&1 | tail -3`
Expected: 컴파일 에러 `cannot find 'GitActivity'`

- [ ] **Step 7: GitActivity.swift 작성**

```swift
import Foundation

public enum GitActivity {
    /// cwd 가 git 작업 트리면 그날의 커밋을 "<short-hash> <subject>" 줄로 최대 30개. 아니면 [].
    public static func commits(in cwd: String, on day: Date, calendar: Calendar = .current, timeout: TimeInterval = 10) -> [String] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir), isDir.boolValue else { return [] }

        let probe = ProcessRunner.run(executable: "/usr/bin/git",
                                      arguments: ["-C", cwd, "rev-parse", "--is-inside-work-tree"],
                                      timeout: timeout)
        guard probe.status == 0, probe.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else { return [] }

        let key = DayKey.string(from: day, calendar: calendar)
        let r = ProcessRunner.run(executable: "/usr/bin/git",
                                  arguments: ["-C", cwd, "log",
                                              "--since=\(key) 00:00:00", "--until=\(key) 23:59:59",
                                              "--format=%h %s", "-n", "30"],
                                  timeout: timeout)
        guard r.status == 0 else { return [] }
        return r.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
```

- [ ] **Step 8: 테스트 통과 확인**

Run: `swift test --filter GitActivityTests 2>&1 | tail -3`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 9: 커밋**

```bash
git add Sources/TaskWidgetCore/ProcessRunner.swift Sources/TaskWidgetCore/GitActivity.swift Tests/TaskWidgetCoreTests/ProcessRunnerTests.swift Tests/TaskWidgetCoreTests/GitActivityTests.swift
git commit -m "feat(core): 프로세스 실행기와 오늘 커밋 조회

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: ActivityLog + `--hook` 모드

**Files:**
- Create: `Sources/TaskWidgetCore/ActivityLog.swift`
- Modify: `Sources/TaskWidget/main.swift`
- Create: `Tests/TaskWidgetCoreTests/Fixtures/activity-sample.jsonl`
- Test: `Tests/TaskWidgetCoreTests/ActivityLogTests.swift`

**Interfaces:**
- Consumes: `ActivityRecord`, `Paths`
- Produces: `ActivityLog.promptCap`, `ActivityLog.stopCap`, `ActivityLog.record(fromHookInput: Data, excludingCwdPrefix: String, now: Date) -> ActivityRecord?`, `ActivityLog.append(_:to:) throws`, `ActivityLog.records(on day: Date, from url: URL, calendar:) -> [ActivityRecord]`, `ActivityLog.handleHook(input: Data, dataDir: URL, now: Date)`

- [ ] **Step 1: fixture 작성** — `Tests/TaskWidgetCoreTests/Fixtures/activity-sample.jsonl` (정확히 5줄, 4번째는 일부러 깨진 줄)

```
{"cwd":"/Users/x/projects/mrs-cms","event":"prompt","session":"s1","text":"PDF 다운로드 느린 거 봐줘","ts":"2026-10-02T09:12:33+09:00"}
{"cwd":"/Users/x/projects/mrs-cms","event":"stop","session":"s1","text":"N+1 쿼리 제거함. 응답 2.1s → 0.4s","ts":"2026-10-02T09:40:10+09:00"}
{"cwd":"/Users/x/projects/task-manager","event":"prompt","session":"s2","text":"위젯 설계","ts":"2026-10-02T00:30:00+09:00"}
{this is not json}
{"cwd":"/Users/x/projects/mrs-cms","event":"prompt","session":"s0","text":"어제 작업","ts":"2026-10-01T18:00:00+09:00"}
```

- [ ] **Step 2: 실패하는 테스트 작성**

```swift
import XCTest
@testable import TaskWidgetCore

final class ActivityLogTests: XCTestCase {
    let seoul: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func hook(_ json: String) -> Data { Data(json.utf8) }
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: record(fromHookInput:)

    func testPromptRecord() {
        let r = ActivityLog.record(fromHookInput: hook(#"{"hook_event_name":"UserPromptSubmit","session_id":"abc","cwd":"/p/x","prompt":"  hi  "}"#),
                                   excludingCwdPrefix: "/data", now: now)!
        XCTAssertEqual(r.event, "prompt")
        XCTAssertEqual(r.session, "abc")
        XCTAssertEqual(r.cwd, "/p/x")
        XCTAssertEqual(r.text, "hi")
        XCTAssertEqual(r.ts, now)
    }

    func testStopRecordUsesLastAssistantMessage() {
        let r = ActivityLog.record(fromHookInput: hook(#"{"hook_event_name":"Stop","session_id":"abc","cwd":"/p/x","last_assistant_message":"done"}"#),
                                   excludingCwdPrefix: "/data", now: now)!
        XCTAssertEqual(r.event, "stop")
        XCTAssertEqual(r.text, "done")
    }

    func testOtherEventsIgnored() {
        XCTAssertNil(ActivityLog.record(fromHookInput: hook(#"{"hook_event_name":"SessionStart","cwd":"/p"}"#), excludingCwdPrefix: "", now: now))
        XCTAssertNil(ActivityLog.record(fromHookInput: hook(#"{"hook_event_name":"SubagentStop","cwd":"/p","last_assistant_message":"x"}"#), excludingCwdPrefix: "", now: now))
    }

    func testExcludedCwdPrefix() {
        XCTAssertNil(ActivityLog.record(fromHookInput: hook(#"{"hook_event_name":"Stop","cwd":"/data/TaskWidget","last_assistant_message":"x"}"#),
                                        excludingCwdPrefix: "/data/TaskWidget", now: now))
    }

    func testEmptyTextIgnored() {
        XCTAssertNil(ActivityLog.record(fromHookInput: hook(#"{"hook_event_name":"UserPromptSubmit","cwd":"/p","prompt":"   "}"#), excludingCwdPrefix: "", now: now))
    }

    func testNonStringFieldsIgnored() {
        // prompt 가 null, cwd 없음, 깨진 JSON — 전부 nil, 크래시 없음
        XCTAssertNil(ActivityLog.record(fromHookInput: hook(#"{"hook_event_name":"UserPromptSubmit","prompt":null}"#), excludingCwdPrefix: "", now: now))
        XCTAssertNil(ActivityLog.record(fromHookInput: hook(#"{"hook_event_name":"Stop","last_assistant_message":123}"#), excludingCwdPrefix: "", now: now))
        XCTAssertNil(ActivityLog.record(fromHookInput: hook("not json"), excludingCwdPrefix: "", now: now))
        XCTAssertNil(ActivityLog.record(fromHookInput: hook("[1,2]"), excludingCwdPrefix: "", now: now))
    }

    func testCaps() {
        let longPrompt = String(repeating: "p", count: 5000)
        let r1 = ActivityLog.record(fromHookInput: hook(#"{"hook_event_name":"UserPromptSubmit","cwd":"/p","prompt":"\#(longPrompt)"}"#), excludingCwdPrefix: "", now: now)!
        XCTAssertEqual(r1.text.count, ActivityLog.promptCap)
        let longStop = String(repeating: "s", count: 9000)
        let r2 = ActivityLog.record(fromHookInput: hook(#"{"hook_event_name":"Stop","cwd":"/p","last_assistant_message":"\#(longStop)"}"#), excludingCwdPrefix: "", now: now)!
        XCTAssertEqual(r2.text.count, ActivityLog.stopCap)
    }

    // MARK: append / records

    func testAppendAndReadBack() throws {
        let file = dir.appendingPathComponent("activity.jsonl")
        let r = ActivityRecord(ts: now, event: "prompt", session: "s", cwd: "/p/x", text: "한글 \"quoted\" /slash")
        try ActivityLog.append(r, to: file)
        try ActivityLog.append(r, to: file)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(text.components(separatedBy: "\n").filter { !$0.isEmpty }.count, 2)
        XCTAssertFalse(text.contains("\\/"), "슬래시는 이스케이프하지 않는다")
        let back = ActivityLog.records(on: now, from: file, calendar: .current)
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back[0].text, r.text)
        XCTAssertEqual(back[0].ts.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
    }

    func testRecordsFromFixtureSkipsBrokenAndOtherDays() throws {
        let url = Bundle.module.url(forResource: "activity-sample", withExtension: "jsonl", subdirectory: "Fixtures")!
        let day = DayKey.date(from: "2026-10-02", calendar: seoul)!
        let recs = ActivityLog.records(on: day, from: url, calendar: seoul)
        XCTAssertEqual(recs.map(\.session), ["s2", "s1", "s1"], "ts 오름차순, 깨진 줄과 10-01 제외")
    }

    func testDayFilterUsesLocalCalendar() throws {
        // 2026-10-02T00:30+09:00 == 2026-10-01T15:30Z
        let url = Bundle.module.url(forResource: "activity-sample", withExtension: "jsonl", subdirectory: "Fixtures")!
        let oct2Seoul = DayKey.date(from: "2026-10-02", calendar: seoul)!
        XCTAssertTrue(ActivityLog.records(on: oct2Seoul, from: url, calendar: seoul).contains { $0.session == "s2" })
        let oct2Utc = DayKey.date(from: "2026-10-02", calendar: utc)!
        XCTAssertFalse(ActivityLog.records(on: oct2Utc, from: url, calendar: utc).contains { $0.session == "s2" })
    }

    func testMissingFileIsEmpty() {
        XCTAssertEqual(ActivityLog.records(on: now, from: dir.appendingPathComponent("none.jsonl")), [])
    }

    // MARK: handleHook

    func testHandleHookAppendsToDataDir() throws {
        ActivityLog.handleHook(input: hook(#"{"hook_event_name":"Stop","session_id":"s","cwd":"/p","last_assistant_message":"ok"}"#), dataDir: dir, now: now)
        let recs = ActivityLog.records(on: now, from: dir.appendingPathComponent("activity.jsonl"))
        XCTAssertEqual(recs.map(\.text), ["ok"])
    }

    func testHandleHookIgnoresOwnDataDirCwd() throws {
        ActivityLog.handleHook(input: hook(#"{"hook_event_name":"Stop","cwd":"\#(dir.path)","last_assistant_message":"ok"}"#), dataDir: dir, now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("activity.jsonl").path))
    }

    func testHandleHookNeverThrowsOnGarbage() {
        ActivityLog.handleHook(input: Data([0xff, 0xfe]), dataDir: dir, now: now)
        ActivityLog.handleHook(input: Data(), dataDir: dir, now: now)
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `swift test --filter ActivityLogTests 2>&1 | tail -3`
Expected: 컴파일 에러 `cannot find 'ActivityLog'`

- [ ] **Step 4: ActivityLog.swift 작성**

```swift
import Foundation

public enum ActivityLog {
    public static let promptCap = 2000
    public static let stopCap = 4000

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(iso.string(from: date))
        }
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Claude Code 훅 stdin JSON → 레코드. 대상 이벤트가 아니거나 텍스트가 없으면 nil.
    public static func record(fromHookInput data: Data, excludingCwdPrefix: String, now: Date = Date()) -> ActivityRecord? {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any],
              let event = dict["hook_event_name"] as? String else { return nil }
        let cwd = dict["cwd"] as? String ?? ""
        if !excludingCwdPrefix.isEmpty, cwd.hasPrefix(excludingCwdPrefix) { return nil }

        let kind: String
        let raw: String
        let cap: Int
        switch event {
        case "UserPromptSubmit":
            kind = "prompt"; raw = dict["prompt"] as? String ?? ""; cap = promptCap
        case "Stop":
            kind = "stop"; raw = dict["last_assistant_message"] as? String ?? ""; cap = stopCap
        default:
            return nil
        }
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(cap))
        guard !text.isEmpty else { return nil }
        return ActivityRecord(ts: now, event: kind, session: dict["session_id"] as? String ?? "", cwd: cwd, text: text)
    }

    /// O_APPEND 로 한 줄 append. 동시에 여러 세션이 써도 줄이 섞이지 않는다.
    public static func append(_ record: ActivityRecord, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var line = try encoder.encode(record)
        line.append(0x0A)
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        try line.withUnsafeBytes { buf in
            var off = 0
            while off < buf.count {
                let n = write(fd, buf.baseAddress! + off, buf.count - off)
                guard n > 0 else { throw POSIXError(.EIO) }
                off += n
            }
        }
    }

    /// 그날(로컬 달력) 레코드만, ts 오름차순. 깨진 줄은 건너뜀.
    public static func records(on day: Date, from url: URL, calendar: Calendar = .current) -> [ActivityRecord] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        // ponytail: 파일 전체 로드. 수십 MB 넘으면 뒤에서부터 읽는 스트리밍으로 교체.
        return text.split(separator: "\n")
            .compactMap { try? decoder.decode(ActivityRecord.self, from: Data($0.utf8)) }
            .filter { calendar.isDate($0.ts, inSameDayAs: day) }
            .sorted { $0.ts < $1.ts }
    }

    /// `TaskWidget --hook` 진입점. 어떤 입력에도 throw/crash 하지 않는다.
    public static func handleHook(input: Data, dataDir: URL = Paths.dataDir, now: Date = Date()) {
        guard let rec = record(fromHookInput: input, excludingCwdPrefix: dataDir.path, now: now) else { return }
        do {
            try append(rec, to: dataDir.appendingPathComponent("activity.jsonl"))
        } catch {
            let log = dataDir.appendingPathComponent("logs/hook.log")
            try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            let msg = "\(iso.string(from: now)) append failed: \(error)\n"
            if let h = try? FileHandle(forWritingTo: log) {
                try? h.seekToEnd()
                try? h.write(contentsOf: Data(msg.utf8))
                try? h.close()
            } else {
                try? msg.write(to: log, atomically: true, encoding: .utf8)
            }
        }
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test --filter ActivityLogTests 2>&1 | tail -3`
Expected: `Executed 14 tests, with 0 failures`

- [ ] **Step 6: main.swift에 --hook 분기 추가** (전체 교체)

```swift
import Foundation
import TaskWidgetCore

if CommandLine.arguments.contains("--hook") {
    ActivityLog.handleHook(input: FileHandle.standardInput.readDataToEndOfFile())
    exit(0)
}

print("TaskWidget data dir: \(Paths.dataDir.path)")
```

- [ ] **Step 7: 훅 모드 수동 확인**

Run:
```bash
swift build 2>&1 | tail -1 && echo '{"hook_event_name":"Stop","session_id":"manual","cwd":"/tmp/x","last_assistant_message":"hook smoke test"}' | .build/debug/TaskWidget --hook; echo "exit=$?"; tail -1 ~/Library/Application\ Support/TaskWidget/activity.jsonl
```
Expected: `exit=0`, 마지막 줄에 `"text":"hook smoke test"` 포함, `"ts"`가 `+09:00` 오프셋.

- [ ] **Step 8: 커밋**

```bash
git add Sources/TaskWidgetCore/ActivityLog.swift Sources/TaskWidget/main.swift Tests/TaskWidgetCoreTests/ActivityLogTests.swift Tests/TaskWidgetCoreTests/Fixtures/activity-sample.jsonl
git commit -m "feat(core): 훅 활동 기록 append/read, --hook 모드

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Worklog 읽기/파싱

**Files:**
- Create: `Sources/TaskWidgetCore/Worklog.swift`
- Create: `Tests/TaskWidgetCoreTests/Fixtures/worklog-sample.md`
- Test: `Tests/TaskWidgetCoreTests/WorklogTests.swift`

**Interfaces:**
- Consumes: `WorklogEntry`, `DayKey`, `Paths.worklogDir`
- Produces: `Worklog.fileURL(for:dir:calendar:) -> URL`, `Worklog.raw(on:dir:calendar:) -> String?`, `Worklog.entries(on:dir:calendar:) -> [WorklogEntry]`, `Worklog.parse(_ markdown: String) -> [WorklogEntry]`

- [ ] **Step 1: fixture 작성** — `Tests/TaskWidgetCoreTests/Fixtures/worklog-sample.md`

```markdown
# 2026-10-02 업무 일지

## 09:40 · mrs-cms
- 지원서 PDF 다운로드 N+1 제거, 2.1s → 0.4s
- 미완료: 배포 문서

## 이건 헤더지만 구분자 없음

## 15:10 · task-manager
- 위젯 설계 스펙 작성
```

- [ ] **Step 2: 실패하는 테스트 작성**

```swift
import XCTest
@testable import TaskWidgetCore

final class WorklogTests: XCTestCase {
    let seoul: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func testParseFixture() throws {
        let url = Bundle.module.url(forResource: "worklog-sample", withExtension: "md", subdirectory: "Fixtures")!
        let entries = Worklog.parse(try String(contentsOf: url, encoding: .utf8))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].time, "09:40")
        XCTAssertEqual(entries[0].project, "mrs-cms")
        XCTAssertTrue(entries[0].body.hasPrefix("- 지원서 PDF"))
        XCTAssertTrue(entries[0].body.contains("## 이건 헤더지만 구분자 없음"), "구분자 없는 ## 줄은 본문으로 취급")
        XCTAssertEqual(entries[1].project, "task-manager")
        XCTAssertEqual(entries[1].body, "- 위젯 설계 스펙 작성")
    }

    func testParseEmptyAndNoHeaders() {
        XCTAssertEqual(Worklog.parse(""), [])
        XCTAssertEqual(Worklog.parse("# 제목만\n\n본문"), [])
    }

    func testParseCRLF() {
        let md = "## 10:00 · proj\r\n- a\r\n- b\r\n"
        let e = Worklog.parse(md)
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].body, "- a\n- b")
    }

    func testFileURLAndMissing() {
        let dir = URL(fileURLWithPath: "/tmp/wl")
        let day = DayKey.date(from: "2026-10-02", calendar: seoul)!
        XCTAssertEqual(Worklog.fileURL(for: day, dir: dir, calendar: seoul).lastPathComponent, "2026-10-02.md")
        XCTAssertNil(Worklog.raw(on: day, dir: dir, calendar: seoul))
        XCTAssertEqual(Worklog.entries(on: day, dir: dir, calendar: seoul), [])
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `swift test --filter WorklogTests 2>&1 | tail -3`
Expected: 컴파일 에러 `cannot find 'Worklog'`

- [ ] **Step 4: Worklog.swift 작성**

```swift
import Foundation

public enum Worklog {
    public static func fileURL(for day: Date, dir: URL = Paths.worklogDir, calendar: Calendar = .current) -> URL {
        dir.appendingPathComponent(DayKey.string(from: day, calendar: calendar) + ".md")
    }

    public static func raw(on day: Date, dir: URL = Paths.worklogDir, calendar: Calendar = .current) -> String? {
        try? String(contentsOf: fileURL(for: day, dir: dir, calendar: calendar), encoding: .utf8)
    }

    public static func entries(on day: Date, dir: URL = Paths.worklogDir, calendar: Calendar = .current) -> [WorklogEntry] {
        raw(on: day, dir: dir, calendar: calendar).map(parse) ?? []
    }

    /// `## HH:mm · project` 헤더로 분할. 구분자 없는 `##` 줄은 본문.
    public static func parse(_ markdown: String) -> [WorklogEntry] {
        var out: [WorklogEntry] = []
        var time = "", project = "", lines: [String] = []
        var open = false

        func flush() {
            guard open else { return }
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(WorklogEntry(time: time, project: project, body: body))
        }

        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("## "), let sep = line.range(of: " · ") {
                flush()
                time = String(line[line.index(line.startIndex, offsetBy: 3)..<sep.lowerBound]).trimmingCharacters(in: .whitespaces)
                project = String(line[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
                lines = []
                open = true
            } else if open {
                lines.append(line)
            }
        }
        flush()
        return out
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test --filter WorklogTests 2>&1 | tail -3`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 6: 커밋**

```bash
git add Sources/TaskWidgetCore/Worklog.swift Tests/TaskWidgetCoreTests/WorklogTests.swift Tests/TaskWidgetCoreTests/Fixtures/worklog-sample.md
git commit -m "feat(core): 업무 일지 파일 읽기와 섹션 파싱

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: SummaryPrompt (입력 필터, 캡, 프롬프트 조립)

**Files:**
- Create: `Sources/TaskWidgetCore/SummaryPrompt.swift`
- Test: `Tests/TaskWidgetCoreTests/SummaryPromptTests.swift`

**Interfaces:**
- Consumes: `ActivityRecord`
- Produces: `SummaryInput { dayKey, worklogRaw: String?, worklogProjects: Set<String>, activity: [ActivityRecord], commits: [String: [String]] }`, `SummaryPrompt.promptCap/stopCap/totalCap`, `SummaryPrompt.filterActivity(_:coveredProjects:) -> [ActivityRecord]`, `SummaryPrompt.isEmpty(_:) -> Bool`, `SummaryPrompt.build(_:calendar:) -> String`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import TaskWidgetCore

final class SummaryPromptTests: XCTestCase {
    let seoul: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func rec(_ project: String, _ event: String, _ text: String, _ offset: TimeInterval = 0) -> ActivityRecord {
        ActivityRecord(ts: Date(timeIntervalSince1970: 1_790_000_000 + offset), event: event, session: "s",
                       cwd: "/Users/x/projects/\(project)", text: text)
    }

    func testIsEmpty() {
        XCTAssertTrue(SummaryPrompt.isEmpty(SummaryInput(dayKey: "2026-10-02", worklogRaw: nil, worklogProjects: [], activity: [], commits: [:])))
        XCTAssertTrue(SummaryPrompt.isEmpty(SummaryInput(dayKey: "2026-10-02", worklogRaw: "  \n", worklogProjects: [], activity: [], commits: ["p": []])))
        XCTAssertFalse(SummaryPrompt.isEmpty(SummaryInput(dayKey: "2026-10-02", worklogRaw: "# x", worklogProjects: [], activity: [], commits: [:])))
        XCTAssertFalse(SummaryPrompt.isEmpty(SummaryInput(dayKey: "2026-10-02", worklogRaw: nil, worklogProjects: [], activity: [rec("a", "prompt", "x")], commits: [:])))
        XCTAssertFalse(SummaryPrompt.isEmpty(SummaryInput(dayKey: "2026-10-02", worklogRaw: nil, worklogProjects: [], activity: [], commits: ["p": ["abc feat"]])))
    }

    func testFilterDropsCoveredProjects() {
        let out = SummaryPrompt.filterActivity([rec("mrs-cms", "prompt", "a"), rec("task-manager", "prompt", "b")], coveredProjects: ["mrs-cms"])
        XCTAssertEqual(out.map(\.text), ["b"])
    }

    func testFilterCapsPerMessage() {
        let out = SummaryPrompt.filterActivity([
            rec("p", "prompt", String(repeating: "u", count: 1000)),
            rec("p", "stop", String(repeating: "a", count: 5000)),
        ], coveredProjects: [])
        XCTAssertEqual(out[0].text.count, SummaryPrompt.promptCap + 1)   // + "…"
        XCTAssertTrue(out[0].text.hasSuffix("…"))
        XCTAssertEqual(out[1].text.count, SummaryPrompt.stopCap + 1)
    }

    func testFilterDropsOldestWhenOverTotal() {
        // 1200자짜리 stop 100개 = 120,000 > 80,000 → 앞에서부터 제거
        let recs = (0..<100).map { i in rec("p", "stop", String(repeating: "x", count: 1200), TimeInterval(i)) }
        let out = SummaryPrompt.filterActivity(recs, coveredProjects: [])
        XCTAssertLessThanOrEqual(out.reduce(0) { $0 + $1.text.count }, SummaryPrompt.totalCap)
        XCTAssertEqual(out.last?.ts, recs.last?.ts, "최신 것이 남는다")
    }

    func testBuildSections() {
        let input = SummaryInput(
            dayKey: "2026-10-02",
            worklogRaw: "## 09:40 · mrs-cms\n- 일지 내용",
            worklogProjects: ["mrs-cms"],
            activity: [rec("task-manager", "prompt", "위젯 설계"), rec("task-manager", "stop", "스펙 작성함", 60)],
            commits: ["task-manager": ["abc1234 docs: 스펙"], "mrs-cms": []]
        )
        let p = SummaryPrompt.build(input, calendar: seoul)
        XCTAssertTrue(p.contains("날짜: 2026-10-02"))
        XCTAssertTrue(p.contains("=== 1) 업무 일지 ===\n## 09:40 · mrs-cms"))
        XCTAssertTrue(p.contains("=== 2) 대화 기록: task-manager (/Users/x/projects/task-manager) ==="))
        XCTAssertTrue(p.contains("] user: 위젯 설계"))
        XCTAssertTrue(p.contains("] assistant: 스펙 작성함"))
        XCTAssertTrue(p.contains("=== 3) 커밋: task-manager ===\nabc1234 docs: 스펙"))
        XCTAssertFalse(p.contains("커밋: mrs-cms"), "빈 커밋 목록은 섹션 생략")
        XCTAssertTrue(p.contains("도구를 사용하지 말고"))
    }

    func testBuildEmptySectionsSayNone() {
        let input = SummaryInput(dayKey: "2026-10-02", worklogRaw: nil, worklogProjects: [], activity: [], commits: [:])
        let p = SummaryPrompt.build(input, calendar: seoul)
        XCTAssertTrue(p.contains("=== 1) 업무 일지 ===\n(없음)"))
        XCTAssertTrue(p.contains("=== 2) 대화 기록 ===\n(없음)"))
        XCTAssertTrue(p.contains("=== 3) 커밋 ===\n(없음)"))
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter SummaryPromptTests 2>&1 | tail -3`
Expected: 컴파일 에러 `cannot find 'SummaryPrompt'`

- [ ] **Step 3: SummaryPrompt.swift 작성**

```swift
import Foundation

public struct SummaryInput: Equatable {
    public var dayKey: String
    public var worklogRaw: String?
    public var worklogProjects: Set<String>
    public var activity: [ActivityRecord]
    public var commits: [String: [String]]   // project -> "<hash> <subject>" lines

    public init(dayKey: String, worklogRaw: String?, worklogProjects: Set<String>,
                activity: [ActivityRecord], commits: [String: [String]]) {
        self.dayKey = dayKey
        self.worklogRaw = worklogRaw
        self.worklogProjects = worklogProjects
        self.activity = activity
        self.commits = commits
    }
}

public enum SummaryPrompt {
    public static let promptCap = 400
    public static let stopCap = 1200
    public static let totalCap = 80_000

    /// 일지가 있는 프로젝트의 raw 는 버리고, 메시지별 캡 적용 후, 총량 초과분은 오래된 것부터 제거.
    public static func filterActivity(_ records: [ActivityRecord], coveredProjects: Set<String>) -> [ActivityRecord] {
        var kept: [ActivityRecord] = records
            .filter { !coveredProjects.contains($0.project) }
            .map { r in
                var r = r
                let cap = r.event == "prompt" ? promptCap : stopCap
                if r.text.count > cap { r.text = String(r.text.prefix(cap)) + "…" }
                return r
            }
        var total = kept.reduce(0) { $0 + $1.text.count }
        while total > totalCap, !kept.isEmpty {
            total -= kept.removeFirst().text.count
        }
        return kept
    }

    public static func isEmpty(_ i: SummaryInput) -> Bool {
        let worklogEmpty = i.worklogRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        return worklogEmpty && i.activity.isEmpty && i.commits.values.allSatisfy { $0.isEmpty }
    }

    static func hhmm(_ d: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    public static func build(_ i: SummaryInput, calendar: Calendar = .current) -> String {
        var s = """
        당신은 개발자의 하루 업무 일지를 작성합니다. 날짜: \(i.dayKey)

        입력은 세 종류입니다.
        1) 개발자가 세션 중 직접 기록한 업무 일지 — 가장 신뢰도 높음. 이 내용을 우선합니다.
        2) 일지가 없는 프로젝트의 Claude Code 대화 기록(raw) — 보완용.
        3) git 커밋 — 사실 확인용.

        도구를 사용하지 말고, 아래 데이터만 근거로 한국어 Markdown을 출력하세요. 데이터에 없는 일은 쓰지 않습니다. 다른 설명 없이 Markdown만 출력합니다.

        형식:
        # \(i.dayKey) 업무 요약
        ## {프로젝트명}
        - 한 일 (성과/결과 위주, 3~7개, 각 1~2문장)
        (프로젝트마다 반복)
        ## 미완료 / 내일
        - 일지나 대화에서 드러난 미완료 작업, 다음 단계
        """

        let worklog = i.worklogRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        s += "\n\n=== 1) 업무 일지 ===\n" + (worklog.isEmpty ? "(없음)" : worklog)

        let groups = Dictionary(grouping: i.activity, by: { $0.project })
        if groups.isEmpty {
            s += "\n\n=== 2) 대화 기록 ===\n(없음)"
        }
        for project in groups.keys.sorted() {
            let recs = groups[project]!.sorted { $0.ts < $1.ts }
            s += "\n\n=== 2) 대화 기록: \(project) (\(recs[0].cwd)) ==="
            for r in recs {
                let role = r.event == "prompt" ? "user" : "assistant"
                s += "\n[\(hhmm(r.ts, calendar))] \(role): \(r.text)"
            }
        }

        let commits = i.commits.filter { !$0.value.isEmpty }
        if commits.isEmpty {
            s += "\n\n=== 3) 커밋 ===\n(없음)"
        }
        for project in commits.keys.sorted() {
            s += "\n\n=== 3) 커밋: \(project) ===\n" + commits[project]!.joined(separator: "\n")
        }
        return s + "\n"
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter SummaryPromptTests 2>&1 | tail -3`
Expected: `Executed 6 tests, with 0 failures`

- [ ] **Step 5: 커밋**

```bash
git add Sources/TaskWidgetCore/SummaryPrompt.swift Tests/TaskWidgetCoreTests/SummaryPromptTests.swift
git commit -m "feat(core): 요약 입력 필터와 프롬프트 조립

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: ClaudeRunner + SummaryService

**Files:**
- Create: `Sources/TaskWidgetCore/ClaudeRunner.swift`
- Create: `Sources/TaskWidgetCore/SummaryService.swift`
- Test: `Tests/TaskWidgetCoreTests/ClaudeRunnerTests.swift`, `Tests/TaskWidgetCoreTests/SummaryServiceTests.swift`

**Interfaces:**
- Consumes: `ProcessRunner`, `ActivityLog.records`, `Worklog.raw/entries`, `GitActivity.commits`, `SummaryPrompt`, `Summary`, `DayKey`
- Produces: `SummaryError { claudeNotFound, timeout, claudeFailed(Int32, String), emptyOutput, busy }` + `.userMessage`, `ClaudeRunner(configuredPath:model:timeout:)`, `ClaudeRunner.locate(configured:home:) -> String?`, `ClaudeRunner.run(prompt:workingDirectory:) throws -> String`, `SummaryService(dataDir:calendar:runner:)`, `SummaryService.Runner = (String) throws -> String`, `summaryURL(for:)`, `existing(for:) -> Summary?`, `collect(for:) -> SummaryInput`, `generate(for:force:) throws -> Summary`, `SummaryService.noRecordMarkdown(dayKey:)`

- [ ] **Step 1: ClaudeRunner 실패 테스트 작성**

```swift
import XCTest
@testable import TaskWidgetCore

final class ClaudeRunnerTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".local/bin"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func makeExecutable(_ url: URL, script: String) throws {
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func testLocatePrefersConfiguredPath() throws {
        let custom = dir.appendingPathComponent("my-claude")
        try makeExecutable(custom, script: "#!/bin/sh\necho x\n")
        XCTAssertEqual(ClaudeRunner.locate(configured: custom.path, home: dir), custom.path)
    }

    func testLocateFallsBackToHomeLocalBin() throws {
        let local = dir.appendingPathComponent(".local/bin/claude")
        try makeExecutable(local, script: "#!/bin/sh\necho x\n")
        XCTAssertEqual(ClaudeRunner.locate(configured: "/nonexistent/claude", home: dir), local.path)
    }

    func testLocateSkipsNonExecutable() throws {
        let local = dir.appendingPathComponent(".local/bin/claude")
        try "not exec".write(to: local, atomically: true, encoding: .utf8)
        // 홈에 실행 파일이 없으면 시스템 경로로 넘어간다 (이 머신에 claude 가 있을 수 있으므로 local 이 아닌 것만 확인)
        XCTAssertNotEqual(ClaudeRunner.locate(configured: "", home: dir), local.path)
    }

    func testRunPassesPromptOnStdinAndReturnsStdout() throws {
        let fake = dir.appendingPathComponent("claude")
        try makeExecutable(fake, script: "#!/bin/sh\n# 인자 확인 후 stdin 을 그대로 출력\ncase \"$*\" in *'-p --output-format text'*) ;; *) echo bad-args 1>&2; exit 9;; esac\ncat\n")
        let out = try ClaudeRunner(configuredPath: fake.path).run(prompt: "hello prompt", workingDirectory: dir)
        XCTAssertEqual(out, "hello prompt")
    }

    func testRunAddsModelFlag() throws {
        let fake = dir.appendingPathComponent("claude")
        try makeExecutable(fake, script: "#!/bin/sh\necho \"$*\"\n")
        let out = try ClaudeRunner(configuredPath: fake.path, model: "claude-sonnet-5-5").run(prompt: "x", workingDirectory: dir)
        XCTAssertEqual(out, "-p --output-format text --model claude-sonnet-5-5")
    }

    func testRunRemovesNestingEnv() throws {
        let fake = dir.appendingPathComponent("claude")
        try makeExecutable(fake, script: "#!/bin/sh\necho \"CLAUDECODE=${CLAUDECODE:-unset}\"\n")
        setenv("CLAUDECODE", "1", 1)
        defer { unsetenv("CLAUDECODE") }
        let out = try ClaudeRunner(configuredPath: fake.path).run(prompt: "x", workingDirectory: dir)
        XCTAssertEqual(out, "CLAUDECODE=unset")
    }

    func testRunFailures() throws {
        let fake = dir.appendingPathComponent("claude")
        try makeExecutable(fake, script: "#!/bin/sh\necho boom 1>&2\nexit 2\n")
        XCTAssertThrowsError(try ClaudeRunner(configuredPath: fake.path).run(prompt: "x", workingDirectory: dir)) { e in
            XCTAssertEqual(e as? SummaryError, .claudeFailed(2, "boom\n"))
        }
        try makeExecutable(fake, script: "#!/bin/sh\nexit 0\n")
        XCTAssertThrowsError(try ClaudeRunner(configuredPath: fake.path).run(prompt: "x", workingDirectory: dir)) { e in
            XCTAssertEqual(e as? SummaryError, .emptyOutput)
        }
        try makeExecutable(fake, script: "#!/bin/sh\nsleep 5\n")
        XCTAssertThrowsError(try ClaudeRunner(configuredPath: fake.path, timeout: 0.3).run(prompt: "x", workingDirectory: dir)) { e in
            XCTAssertEqual(e as? SummaryError, .timeout)
        }
    }

    func testNotFound() {
        XCTAssertThrowsError(try ClaudeRunner(configuredPath: "/nonexistent/claude").runLocated(prompt: "x", home: dir, workingDirectory: dir)) { e in
            XCTAssertEqual(e as? SummaryError, .claudeNotFound)
        }
    }

    func testUserMessages() {
        XCTAssertEqual(SummaryError.claudeNotFound.userMessage, "claude CLI 없음. 설정에서 경로 지정")
        XCTAssertEqual(SummaryError.timeout.userMessage, "claude 응답 시간 초과")
        XCTAssertEqual(SummaryError.claudeFailed(2, "a\nlast line\n").userMessage, "claude 실패 (exit 2): last line")
        XCTAssertEqual(SummaryError.emptyOutput.userMessage, "claude 출력이 비어 있음")
        XCTAssertEqual(SummaryError.busy.userMessage, "이미 생성 중")
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter ClaudeRunnerTests 2>&1 | tail -3`
Expected: 컴파일 에러 `cannot find 'ClaudeRunner'`

- [ ] **Step 3: ClaudeRunner.swift 작성**

```swift
import Foundation

public enum SummaryError: Error, Equatable {
    case claudeNotFound
    case timeout
    case claudeFailed(Int32, String)
    case emptyOutput
    case busy

    public var userMessage: String {
        switch self {
        case .claudeNotFound: return "claude CLI 없음. 설정에서 경로 지정"
        case .timeout: return "claude 응답 시간 초과"
        case .claudeFailed(let code, let tail):
            let last = tail.split(separator: "\n").last.map(String.init) ?? ""
            return "claude 실패 (exit \(code)): \(last)"
        case .emptyOutput: return "claude 출력이 비어 있음"
        case .busy: return "이미 생성 중"
        }
    }
}

public struct ClaudeRunner {
    public var configuredPath: String
    public var model: String
    public var timeout: TimeInterval

    public init(configuredPath: String = "", model: String = "", timeout: TimeInterval = 180) {
        self.configuredPath = configuredPath
        self.model = model
        self.timeout = timeout
    }

    /// 설정 경로 → ~/.local/bin → /opt/homebrew/bin → /usr/local/bin 순. 실행 가능한 첫 번째.
    public static func locate(configured: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        var candidates: [String] = []
        if !configured.isEmpty { candidates.append(configured) }
        candidates += [
            home.appendingPathComponent(".local/bin/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func run(prompt: String, workingDirectory: URL = Paths.dataDir) throws -> String {
        try runLocated(prompt: prompt, home: FileManager.default.homeDirectoryForCurrentUser, workingDirectory: workingDirectory)
    }

    func runLocated(prompt: String, home: URL, workingDirectory: URL) throws -> String {
        guard let exe = Self.locate(configured: configuredPath, home: home) else { throw SummaryError.claudeNotFound }
        var args = ["-p", "--output-format", "text"]
        if !model.isEmpty { args += ["--model", model] }

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(homePath)/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")

        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let r = ProcessRunner.run(executable: exe, arguments: args, stdin: prompt,
                                  currentDirectory: workingDirectory, environment: env, timeout: timeout)
        if r.timedOut { throw SummaryError.timeout }
        guard r.status == 0 else { throw SummaryError.claudeFailed(r.status, String(r.stderr.suffix(2000))) }
        let out = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { throw SummaryError.emptyOutput }
        return out
    }
}
```

- [ ] **Step 4: ClaudeRunner 테스트 통과 확인**

Run: `swift test --filter ClaudeRunnerTests 2>&1 | tail -3`
Expected: `Executed 9 tests, with 0 failures`

- [ ] **Step 5: SummaryService 실패 테스트 작성**

```swift
import XCTest
@testable import TaskWidgetCore

final class SummaryServiceTests: XCTestCase {
    let seoul: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    var dir: URL!
    var day: Date { DayKey.date(from: "2026-10-02", calendar: seoul)! }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func writeActivity(_ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent("activity.jsonl"), atomically: true, encoding: .utf8)
    }

    func testNoRecordsWritesPlaceholderWithoutCallingRunner() throws {
        var called = false
        let svc = SummaryService(dataDir: dir, calendar: seoul) { _ in called = true; return "x" }
        let s = try svc.generate(for: day, force: false)
        XCTAssertFalse(called)
        XCTAssertEqual(s.markdown, SummaryService.noRecordMarkdown(dayKey: "2026-10-02"))
        XCTAssertTrue(s.markdown.contains("오늘 기록 없음"))
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("summaries/2026-10-02.md"), encoding: .utf8), s.markdown)
    }

    func testGenerateFromActivityAndWritesFileAndLog() throws {
        try writeActivity([
            #"{"cwd":"/Users/x/projects/mrs-cms","event":"prompt","session":"s1","text":"PDF 느림","ts":"2026-10-02T09:12:33+09:00"}"#,
            #"{"cwd":"/Users/x/projects/mrs-cms","event":"stop","session":"s1","text":"N+1 제거","ts":"2026-10-02T09:40:10+09:00"}"#,
        ])
        var received = ""
        let svc = SummaryService(dataDir: dir, calendar: seoul) { prompt in received = prompt; return "# 2026-10-02 업무 요약\n## mrs-cms\n- N+1 제거" }
        let s = try svc.generate(for: day, force: false)
        XCTAssertTrue(received.contains("대화 기록: mrs-cms"))
        XCTAssertTrue(received.contains("PDF 느림"))
        XCTAssertEqual(s.markdown, "# 2026-10-02 업무 요약\n## mrs-cms\n- N+1 제거")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("summaries/2026-10-02.md").path))
        let log = try String(contentsOf: dir.appendingPathComponent("logs/summary-2026-10-02.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("activity=2"))
        XCTAssertTrue(log.contains("ok"))
    }

    func testWorklogCoversProjectSoRawDropped() throws {
        try writeActivity([
            #"{"cwd":"/Users/x/projects/mrs-cms","event":"prompt","session":"s1","text":"RAW-SHOULD-DROP","ts":"2026-10-02T09:12:33+09:00"}"#,
            #"{"cwd":"/Users/x/projects/other","event":"prompt","session":"s2","text":"RAW-KEEP","ts":"2026-10-02T10:00:00+09:00"}"#,
        ])
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("worklog"), withIntermediateDirectories: true)
        try "## 09:40 · mrs-cms\n- 일지".write(to: dir.appendingPathComponent("worklog/2026-10-02.md"), atomically: true, encoding: .utf8)
        var received = ""
        let svc = SummaryService(dataDir: dir, calendar: seoul) { p in received = p; return "ok" }
        _ = try svc.generate(for: day, force: false)
        XCTAssertTrue(received.contains("- 일지"))
        XCTAssertFalse(received.contains("RAW-SHOULD-DROP"))
        XCTAssertTrue(received.contains("RAW-KEEP"))
    }

    func testExistingReturnedWithoutRunnerUnlessForce() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("summaries"), withIntermediateDirectories: true)
        try "old".write(to: dir.appendingPathComponent("summaries/2026-10-02.md"), atomically: true, encoding: .utf8)
        try writeActivity([#"{"cwd":"/p","event":"prompt","session":"s","text":"t","ts":"2026-10-02T09:00:00+09:00"}"#])
        var calls = 0
        let svc = SummaryService(dataDir: dir, calendar: seoul) { _ in calls += 1; return "new" }
        XCTAssertEqual(try svc.generate(for: day, force: false).markdown, "old")
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(try svc.generate(for: day, force: true).markdown, "new")
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(svc.existing(for: day)?.markdown, "new")
    }

    func testRunnerErrorLeavesNoFileAndLogsError() throws {
        try writeActivity([#"{"cwd":"/p","event":"prompt","session":"s","text":"t","ts":"2026-10-02T09:00:00+09:00"}"#])
        let svc = SummaryService(dataDir: dir, calendar: seoul) { _ in throw SummaryError.timeout }
        XCTAssertThrowsError(try svc.generate(for: day, force: false)) { XCTAssertEqual($0 as? SummaryError, .timeout) }
        XCTAssertNil(svc.existing(for: day))
        let log = try String(contentsOf: dir.appendingPathComponent("logs/summary-2026-10-02.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("error: timeout"))
    }

    func testExistingNilWhenMissing() {
        let svc = SummaryService(dataDir: dir, calendar: seoul) { _ in "x" }
        XCTAssertNil(svc.existing(for: day))
    }
}
```

- [ ] **Step 6: 테스트 실패 확인**

Run: `swift test --filter SummaryServiceTests 2>&1 | tail -3`
Expected: 컴파일 에러 `cannot find 'SummaryService'`

- [ ] **Step 7: SummaryService.swift 작성**

```swift
import Foundation

public final class SummaryService {
    public typealias Runner = (String) throws -> String

    public let dataDir: URL
    public let calendar: Calendar
    private let runner: Runner
    private let lock = NSLock()

    public init(dataDir: URL = Paths.dataDir, calendar: Calendar = .current, runner: @escaping Runner) {
        self.dataDir = dataDir
        self.calendar = calendar
        self.runner = runner
    }

    public func summaryURL(for day: Date) -> URL {
        dataDir.appendingPathComponent("summaries/\(DayKey.string(from: day, calendar: calendar)).md")
    }

    public func existing(for day: Date) -> Summary? {
        let url = summaryURL(for: day)
        guard let md = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
        return Summary(dayKey: DayKey.string(from: day, calendar: calendar), markdown: md, generatedAt: mtime)
    }

    public static func noRecordMarkdown(dayKey: String) -> String {
        "# \(dayKey) 업무 요약\n\n오늘 기록 없음\n"
    }

    /// 일지 → 활동(일지 없는 프로젝트만) → 커밋(활동에서 본 모든 cwd) 수집.
    public func collect(for day: Date) -> SummaryInput {
        let key = DayKey.string(from: day, calendar: calendar)
        let worklogDir = dataDir.appendingPathComponent("worklog", isDirectory: true)
        let raw = Worklog.raw(on: day, dir: worklogDir, calendar: calendar)
        let covered = Set(Worklog.entries(on: day, dir: worklogDir, calendar: calendar).map(\.project))

        let all = ActivityLog.records(on: day, from: dataDir.appendingPathComponent("activity.jsonl"), calendar: calendar)

        var commits: [String: [String]] = [:]
        for cwd in Set(all.map(\.cwd)).filter({ !$0.isEmpty }).sorted() {
            let lines = GitActivity.commits(in: cwd, on: day, calendar: calendar)
            if !lines.isEmpty {
                commits[(cwd as NSString).lastPathComponent, default: []] += lines
            }
        }

        let activity = SummaryPrompt.filterActivity(all, coveredProjects: covered)
        return SummaryInput(dayKey: key, worklogRaw: raw, worklogProjects: covered, activity: activity, commits: commits)
    }

    @discardableResult
    public func generate(for day: Date, force: Bool) throws -> Summary {
        if !force, let s = existing(for: day) { return s }
        guard lock.try() else { throw SummaryError.busy }
        defer { lock.unlock() }

        let input = collect(for: day)
        let key = input.dayKey
        var log = "[\(key)] worklog=\(input.worklogProjects.count) activity=\(input.activity.count) commits=\(input.commits.values.map(\.count).reduce(0, +))\n"

        let markdown: String
        if SummaryPrompt.isEmpty(input) {
            markdown = Self.noRecordMarkdown(dayKey: key)
            log += "no records\n"
        } else {
            do {
                markdown = try runner(SummaryPrompt.build(input, calendar: calendar))
            } catch {
                log += "error: \(error)\n"
                writeLog(key, log)
                throw error
            }
        }

        let url = summaryURL(for: day)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        writeLog(key, log + "ok\n")
        return Summary(dayKey: key, markdown: markdown, generatedAt: Date())
    }

    private func writeLog(_ key: String, _ text: String) {
        let url = dataDir.appendingPathComponent("logs/summary-\(key).log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 8: 테스트 통과 확인**

Run: `swift test 2>&1 | tail -3`
Expected: 모든 테스트 `0 failures`

- [ ] **Step 9: 커밋**

```bash
git add Sources/TaskWidgetCore/ClaudeRunner.swift Sources/TaskWidgetCore/SummaryService.swift Tests/TaskWidgetCoreTests/ClaudeRunnerTests.swift Tests/TaskWidgetCoreTests/SummaryServiceTests.swift
git commit -m "feat(core): claude -p 실행기와 요약 서비스

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 12: ClaudeIntegration (settings.json 훅 설치/제거, SKILL.md)

**Files:**
- Create: `Sources/TaskWidgetCore/ClaudeIntegration.swift`
- Create: `Tests/TaskWidgetCoreTests/Fixtures/settings-with-hooks.json`
- Test: `Tests/TaskWidgetCoreTests/ClaudeIntegrationTests.swift`

**Interfaces:**
- Consumes: `Paths.claudeDir`
- Produces: `HookStatus { installed, notInstalled, pathMismatch }`, `IntegrationError { invalidSettingsJSON }`, `ClaudeIntegration(claudeDir:executablePath:)`, `.settingsURL`, `.skillURL`, `.hookCommand`, `.hookStatus() -> HookStatus`, `.installHook() throws`, `.removeHook() throws`, `.skillInstalled() -> Bool`, `.installSkill() throws`, `.removeSkill() throws`, `ClaudeIntegration.skillMarkdown`

- [ ] **Step 1: fixture 작성** — `Tests/TaskWidgetCoreTests/Fixtures/settings-with-hooks.json`

```json
{
  "permissions": { "allow": ["Bash(ls:*)"] },
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "node /Users/x/.claude/hooks/other.js", "timeout": 5 } ] }
    ],
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "node /Users/x/.claude/hooks/start.js" } ] }
    ]
  }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

```swift
import XCTest
@testable import TaskWidgetCore

final class ClaudeIntegrationTests: XCTestCase {
    var dir: URL!
    let exeA = "/Applications/TaskWidget.app/Contents/MacOS/TaskWidget"
    let exeB = "/Users/x/projects/task-manager/build/TaskWidget.app/Contents/MacOS/TaskWidget"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func copyFixture() throws {
        let src = Bundle.module.url(forResource: "settings-with-hooks", withExtension: "json", subdirectory: "Fixtures")!
        try FileManager.default.copyItem(at: src, to: dir.appendingPathComponent("settings.json"))
    }

    func readJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: dir.appendingPathComponent("settings.json"))
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func ourCommands(_ root: [String: Any], _ event: String) -> [String] {
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let groups = hooks[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
            .filter { $0.contains("TaskWidget") }
    }

    func testStatusNotInstalledWhenMissingFile() {
        XCTAssertEqual(ClaudeIntegration(claudeDir: dir, executablePath: exeA).hookStatus(), .notInstalled)
    }

    func testInstallPreservesOtherHooksAndKeys() throws {
        try copyFixture()
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        try ci.installHook()
        let root = try readJSON()
        XCTAssertNotNil(root["permissions"], "다른 키 보존")
        let hooks = root["hooks"] as! [String: Any]
        XCTAssertEqual((hooks["SessionStart"] as! [[String: Any]]).count, 1, "다른 이벤트 보존")
        let ups = hooks["UserPromptSubmit"] as! [[String: Any]]
        XCTAssertEqual(ups.count, 2, "기존 그룹 + 우리 그룹")
        XCTAssertEqual(ourCommands(root, "UserPromptSubmit"), [ci.hookCommand])
        XCTAssertEqual(ourCommands(root, "Stop"), [ci.hookCommand])
        XCTAssertEqual(ci.hookStatus(), .installed)
        let text = try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8)
        XCTAssertFalse(text.contains("\\/"), "슬래시 이스케이프 금지")
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("settings.json.bak-") }
        XCTAssertEqual(backups.count, 1)
    }

    func testInstallIsIdempotent() throws {
        try copyFixture()
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        try ci.installHook()
        try ci.installHook()
        let root = try readJSON()
        XCTAssertEqual(ourCommands(root, "UserPromptSubmit").count, 1)
        XCTAssertEqual(ourCommands(root, "Stop").count, 1)
    }

    func testPathMismatchAndReinstall() throws {
        try copyFixture()
        try ClaudeIntegration(claudeDir: dir, executablePath: exeB).installHook()
        let ciA = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        XCTAssertEqual(ciA.hookStatus(), .pathMismatch)
        try ciA.installHook()
        XCTAssertEqual(ciA.hookStatus(), .installed)
        XCTAssertEqual(ourCommands(try readJSON(), "Stop"), [ciA.hookCommand])
    }

    func testRemoveRestoresOthers() throws {
        try copyFixture()
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        try ci.installHook()
        try ci.removeHook()
        let root = try readJSON()
        let hooks = root["hooks"] as! [String: Any]
        XCTAssertNil(hooks["Stop"], "우리만 있던 이벤트는 키 삭제")
        XCTAssertEqual((hooks["UserPromptSubmit"] as! [[String: Any]]).count, 1, "남의 그룹만 남음")
        XCTAssertEqual(ourCommands(root, "UserPromptSubmit"), [])
        XCTAssertEqual(ci.hookStatus(), .notInstalled)
    }

    func testInstallCreatesFileWhenMissing() throws {
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        try ci.installHook()
        XCTAssertEqual(ci.hookStatus(), .installed)
        XCTAssertEqual(ourCommands(try readJSON(), "UserPromptSubmit").count, 1)
    }

    func testInvalidJSONThrowsAndLeavesFile() throws {
        try "{ not json".write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        XCTAssertThrowsError(try ci.installHook()) { XCTAssertEqual($0 as? IntegrationError, .invalidSettingsJSON) }
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8), "{ not json")
        XCTAssertEqual(ci.hookStatus(), .notInstalled)
    }

    func testMalformedEventValueReplaced() throws {
        try #"{"hooks":{"Stop":"oops","UserPromptSubmit":[]}}"#.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        try ci.installHook()
        XCTAssertEqual(ci.hookStatus(), .installed)
        XCTAssertEqual(ourCommands(try readJSON(), "Stop").count, 1)
    }

    func testHookCommandQuotesPath() {
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: "/Users/me/My Apps/TaskWidget.app/Contents/MacOS/TaskWidget")
        XCTAssertEqual(ci.hookCommand, "\"/Users/me/My Apps/TaskWidget.app/Contents/MacOS/TaskWidget\" --hook")
    }

    func testSkillInstallRemove() throws {
        let ci = ClaudeIntegration(claudeDir: dir, executablePath: exeA)
        XCTAssertFalse(ci.skillInstalled())
        try ci.installSkill()
        XCTAssertTrue(ci.skillInstalled())
        let md = try String(contentsOf: ci.skillURL, encoding: .utf8)
        XCTAssertTrue(md.hasPrefix("---\nname: worklog\n"))
        XCTAssertTrue(md.contains("~/Library/Application Support/TaskWidget/worklog/YYYY-MM-DD.md"))
        XCTAssertTrue(md.contains("## HH:mm · <프로젝트명>"))
        try ci.removeSkill()
        XCTAssertFalse(ci.skillInstalled())
        XCTAssertFalse(FileManager.default.fileExists(atPath: ci.skillURL.deletingLastPathComponent().path))
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `swift test --filter ClaudeIntegrationTests 2>&1 | tail -3`
Expected: 컴파일 에러 `cannot find 'ClaudeIntegration'`

- [ ] **Step 4: ClaudeIntegration.swift 작성**

```swift
import Foundation

public enum HookStatus: Equatable {
    case installed, notInstalled, pathMismatch
}

public enum IntegrationError: Error, Equatable {
    case invalidSettingsJSON
}

public struct ClaudeIntegration {
    public let claudeDir: URL
    public let executablePath: String

    public init(claudeDir: URL = Paths.claudeDir, executablePath: String) {
        self.claudeDir = claudeDir
        self.executablePath = executablePath
    }

    public var settingsURL: URL { claudeDir.appendingPathComponent("settings.json") }
    public var skillURL: URL { claudeDir.appendingPathComponent("skills/worklog/SKILL.md") }
    public var hookCommand: String { "\"\(executablePath)\" --hook" }

    static let events = ["UserPromptSubmit", "Stop"]

    static func isOurs(_ command: Any?) -> Bool {
        guard let c = command as? String else { return false }
        return c.contains("TaskWidget") && c.hasSuffix("--hook")
    }

    // MARK: settings.json

    func readSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data), let dict = obj as? [String: Any] else {
            throw IntegrationError.invalidSettingsJSON
        }
        return dict
    }

    func writeSettings(_ root: [String: Any]) throws {
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let backup = settingsURL.appendingPathExtension("bak-" + f.string(from: Date()))
            try? FileManager.default.copyItem(at: settingsURL, to: backup)
        }
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }

    public func hookStatus() -> HookStatus {
        guard let root = try? readSettings(), let hooks = root["hooks"] as? [String: Any] else { return .notInstalled }
        var found = 0, exact = 0
        for ev in Self.events {
            for group in hooks[ev] as? [[String: Any]] ?? [] {
                for h in group["hooks"] as? [[String: Any]] ?? [] where Self.isOurs(h["command"]) {
                    found += 1
                    if (h["command"] as? String) == hookCommand { exact += 1 }
                }
            }
        }
        if found == 0 { return .notInstalled }
        return (found == Self.events.count && exact == found) ? .installed : .pathMismatch
    }

    /// 두 이벤트에 우리 훅을 넣는다. 이미 있으면 command 만 현재 경로로 갱신. 다른 훅/키는 보존.
    public func installHook() throws {
        var root = try readSettings()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for ev in Self.events {
            var groups = hooks[ev] as? [[String: Any]] ?? []   // 잘못된 값이면 빈 배열로 교체
            var found = false
            for gi in groups.indices {
                var inner = groups[gi]["hooks"] as? [[String: Any]] ?? []
                for hi in inner.indices where Self.isOurs(inner[hi]["command"]) {
                    inner[hi]["command"] = hookCommand
                    found = true
                }
                groups[gi]["hooks"] = inner
            }
            if !found {
                groups.append(["hooks": [["type": "command", "command": hookCommand, "timeout": 5]]])
            }
            hooks[ev] = groups
        }
        root["hooks"] = hooks
        try writeSettings(root)
    }

    /// 우리 훅만 제거. 비게 된 그룹/이벤트/hooks 키는 삭제.
    public func removeHook() throws {
        var root = try readSettings()
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for ev in Self.events {
            guard let groups = hooks[ev] as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { g in
                var g = g
                let inner = (g["hooks"] as? [[String: Any]] ?? []).filter { !Self.isOurs($0["command"]) }
                if inner.isEmpty { return nil }
                g["hooks"] = inner
                return g
            }
            if kept.isEmpty { hooks.removeValue(forKey: ev) } else { hooks[ev] = kept }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try writeSettings(root)
    }

    // MARK: SKILL.md

    public func skillInstalled() -> Bool {
        FileManager.default.fileExists(atPath: skillURL.path)
    }

    public func installSkill() throws {
        try FileManager.default.createDirectory(at: skillURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.skillMarkdown.write(to: skillURL, atomically: true, encoding: .utf8)
    }

    public func removeSkill() throws {
        let dir = skillURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    public static let skillMarkdown = """
    ---
    name: worklog
    description: 현재 세션에서 한 일을 정리해 TaskWidget 업무 일지에 기록한다. "/worklog", "오늘 한 거 기록해", "업무 일지 남겨", "worklog" 요청 시 사용.
    ---

    현재 세션에서 지금까지 한 일을 정리해 아래 파일 끝에 append 한다.

    파일: `~/Library/Application Support/TaskWidget/worklog/YYYY-MM-DD.md` (오늘 로컬 날짜. 디렉터리 없으면 만든다)

    형식:

    ## HH:mm · <프로젝트명>
    - 한 일 (성과/결과 위주) 3~7개, 각 1~2문장
    - 미완료: (있을 때만, 한 줄)

    규칙:
    - 프로젝트명 = 현재 작업 디렉터리의 마지막 경로 요소.
    - 파일이 없으면 첫 줄 `# YYYY-MM-DD 업무 일지` 후 빈 줄, 그 다음 섹션.
    - 기존 내용은 수정하지 않는다. 끝에 append만.
    - `$ARGUMENTS`가 있으면 그 범위나 관점을 반영한다 (예: "오전 작업만", "버그 수정 위주").
    - 추측하지 않는다. 이 세션에서 실제로 한 일만 쓴다.
    - 기록 후 추가한 섹션을 그대로 보여준다.

    """
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test --filter ClaudeIntegrationTests 2>&1 | tail -3`
Expected: `Executed 10 tests, with 0 failures`

- [ ] **Step 6: 전체 테스트**

Run: `swift test 2>&1 | tail -3`
Expected: `0 failures`

- [ ] **Step 7: 커밋**

```bash
git add Sources/TaskWidgetCore/ClaudeIntegration.swift Tests/TaskWidgetCoreTests/ClaudeIntegrationTests.swift Tests/TaskWidgetCoreTests/Fixtures/settings-with-hooks.json
git commit -m "feat(core): Claude Code 훅/스킬 설치·제거·상태

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 13: 앱 셸 — main, AppDelegate, FloatingPanel, AppState, RootView 골격

이 태스크부터는 UI. 단위 테스트 대신 빌드 + 수동 확인.

**Files:**
- Modify: `Sources/TaskWidget/main.swift`
- Create: `Sources/TaskWidget/AppDelegate.swift`
- Create: `Sources/TaskWidget/AppState.swift`
- Create: `Sources/TaskWidget/FloatingPanel.swift`
- Create: `Sources/TaskWidget/Views/FontScale.swift`
- Create: `Sources/TaskWidget/Views/RootView.swift`
- Create: `Sources/TaskWidget/Views/TasksView.swift` (placeholder)
- Create: `Sources/TaskWidget/Views/SummaryView.swift` (placeholder)
- Create: `Sources/TaskWidget/Views/SettingsView.swift` (placeholder)

**Interfaces:**
- Consumes: `Paths`, `Settings`, `TodoStore`, `Todo`, `ActivityLog.handleHook`
- Produces: `AppState: ObservableObject` (`todos`, `todoStore`), `FloatingPanel(content:)`, `.applyAppearance()`, `.toggle()`, `EnvironmentValues.fontScale`, `Notification.Name.openSettings`, `RootView`, placeholder `TasksView`, `SummaryView`, `SettingsView`

- [ ] **Step 1: main.swift 교체**

```swift
import AppKit
import TaskWidgetCore

if CommandLine.arguments.contains("--hook") {
    ActivityLog.handleHook(input: FileHandle.standardInput.readDataToEndOfFile())
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 2: FontScale.swift**

```swift
import SwiftUI

private struct FontScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var fontScale: Double {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("TaskWidget.openSettings")
}
```

- [ ] **Step 3: AppState.swift (이 태스크에서는 todos 로드만)**

```swift
import SwiftUI
import TaskWidgetCore

@MainActor
final class AppState: ObservableObject {
    @Published var todos: [Todo]
    let todoStore: TodoStore

    init(todoStore: TodoStore = TodoStore()) {
        self.todoStore = todoStore
        self.todos = todoStore.load()
    }
}
```

- [ ] **Step 4: FloatingPanel.swift**

```swift
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
        if isVisible { orderOut(nil) } else { makeKeyAndOrderFront(nil) }
    }

    /// 닫기 버튼 = 숨기기. 앱은 메뉴바에 계속 산다.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        orderOut(nil)
        return false
    }
}
```

- [ ] **Step 5: AppDelegate.swift**

```swift
import AppKit
import SwiftUI
import TaskWidgetCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let state = AppState()
    private var defaultsObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            self?.panel.applyAppearance()
        }

        panel.makeKeyAndOrderFront(nil)
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

    @objc private func openSettings() {
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }
}
```

- [ ] **Step 6: RootView.swift**

```swift
import SwiftUI
import TaskWidgetCore

struct RootView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsKey.lastTab) private var tab = "tasks"
    @AppStorage(SettingsKey.fontScale) private var fontScale = 1.0
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $tab) {
                    Text("할 일").tag("tasks")
                    Text("요약").tag("summary")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("설정")
            }
            .padding(.leading, 26)   // 닫기 버튼 자리
            .padding(.trailing, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)
            Divider()
            Group {
                if tab == "summary" {
                    SummaryView()
                } else {
                    TasksView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.fontScale, fontScale)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            showSettings = true
        }
    }
}
```

- [ ] **Step 7: placeholder 뷰 3개** (각각 별 파일)

`Views/TasksView.swift`
```swift
import SwiftUI

struct TasksView: View {
    var body: some View {
        Text("할 일 (Task 14)").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

`Views/SummaryView.swift`
```swift
import SwiftUI

struct SummaryView: View {
    var body: some View {
        Text("요약 (Task 16)").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

`Views/SettingsView.swift`
```swift
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            Text("설정 (Task 17)")
            Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(width: 300, height: 160)
    }
}
```

- [ ] **Step 8: 빌드 + 수동 확인**

Run: `swift build 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" | tail -5 && make run`
Expected:
- 메뉴바에 체크리스트 아이콘. Dock 아이콘 없음.
- 320×520 패널이 떠 있고 다른 앱 창(예: 이 터미널) 위에 그대로 보임.
- 상단 세그먼트 "할 일 | 요약" 전환됨, 기어 클릭 시 설정 시트 열리고 "닫기"로 닫힘.
- 패널 좌상단 닫기 버튼 → 패널 숨김. 메뉴바 아이콘 좌클릭 → 다시 보임. 우클릭 → 메뉴 (패널 토글 / 설정… / 종료).
- 패널을 드래그해 옮긴 뒤 종료(`pkill -x TaskWidget`)하고 다시 `make run` → 같은 위치에 뜸.
- `swift build` 출력에 `error` 없음.

- [ ] **Step 9: 커밋**

```bash
git add Sources/TaskWidget
git commit -m "feat(app): 메뉴바 앱 셸, 플로팅 패널, 루트 탭 골격

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 14: 할 일 섹션 UI (TasksView, TodoRow, DuePopover) + AppState todo 동작

**Files:**
- Modify: `Sources/TaskWidget/AppState.swift`
- Modify: `Sources/TaskWidget/Views/TasksView.swift` (교체)
- Create: `Sources/TaskWidget/Views/TodoRow.swift`
- Create: `Sources/TaskWidget/Views/DuePopover.swift`
- Create: `Sources/TaskWidget/Views/SectionHeader.swift`

**Interfaces:**
- Consumes: `Todo`, `Todo.normalizedTitle`, `DueBadge.badge/sorted`, `DueStyle`, `DayKey`, `SettingsKey.todoSectionCollapsed/jiraSectionCollapsed`, `EnvironmentValues.fontScale`
- Produces: `AppState.openTodos`, `doneTodos`, `addTodo(_:)`, `toggle(_:)`, `setDue(_:_:)`, `delete(_:)`, `clearDone()`, `SectionHeader(title:count:collapsed:trailing:)`, `TodoRow(todo:)`, `DuePopover(due:onPick:)`

- [ ] **Step 1: AppState에 todo 동작 추가** (클래스 본문 끝에 추가)

```swift
    // MARK: - Todos

    var openTodos: [Todo] { DueBadge.sorted(todos.filter { !$0.done }) }

    var doneTodos: [Todo] {
        todos.filter(\.done).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    func addTodo(_ raw: String) {
        guard let title = Todo.normalizedTitle(raw) else { return }
        todos.append(Todo(title: title))
        persistTodos()
    }

    func toggle(_ todo: Todo) {
        update(todo.id) {
            $0.done.toggle()
            $0.completedAt = $0.done ? Date() : nil
        }
    }

    func setDue(_ todo: Todo, _ dayKey: String?) {
        update(todo.id) { $0.dueDate = dayKey }
    }

    func delete(_ todo: Todo) {
        todos.removeAll { $0.id == todo.id }
        persistTodos()
    }

    func clearDone() {
        todos.removeAll(where: \.done)
        persistTodos()
    }

    private func update(_ id: UUID, _ change: (inout Todo) -> Void) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        change(&todos[i])
        persistTodos()
    }

    private func persistTodos() {
        do { try todoStore.save(todos) } catch { NSLog("todos save failed: \(error)") }
    }
```

- [ ] **Step 2: SectionHeader.swift**

```swift
import SwiftUI

struct SectionHeader<Trailing: View>: View {
    let title: String
    let count: Int
    @Binding var collapsed: Bool
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.fontScale) private var scale

    init(title: String, count: Int, collapsed: Binding<Bool>, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.count = count
        self._collapsed = collapsed
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9 * scale, weight: .semibold))
                    Text(title).font(.system(size: 11 * scale, weight: .semibold))
                    Text("\(count)").font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            trailing()
        }
        .foregroundStyle(.secondary)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
```

- [ ] **Step 3: DuePopover.swift**

```swift
import SwiftUI
import TaskWidgetCore

struct DuePopover: View {
    @State private var date: Date
    let onPick: (String?) -> Void

    init(due: String?, onPick: @escaping (String?) -> Void) {
        _date = State(initialValue: due.flatMap { DayKey.date(from: $0) } ?? Date())
        self.onPick = onPick
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button("내일") { pick(Calendar.current.date(byAdding: .day, value: 1, to: Date())!) }
                Button("다음 주 월") {
                    pick(Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!)
                }
                Button("마감 없음") { onPick(nil) }
            }
            .controlSize(.small)
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            Button("확인") { pick(date) }
                .keyboardShortcut(.defaultAction)
                .controlSize(.small)
        }
        .padding(12)
        .frame(width: 260)
    }

    private func pick(_ d: Date) {
        onPick(DayKey.string(from: d))
    }
}
```

- [ ] **Step 4: TodoRow.swift**

```swift
import SwiftUI
import TaskWidgetCore

struct TodoRow: View {
    let todo: Todo
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale
    @State private var hovering = false
    @State private var showDue = false

    var body: some View {
        let badge = DueBadge.badge(due: todo.dueDate, today: Date())
        HStack(spacing: 8) {
            Button { state.toggle(todo) } label: {
                Image(systemName: todo.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(todo.done ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .font(.system(size: 12.5 * scale))
                .strikethrough(todo.done)
                .foregroundStyle(todo.done ? Color.secondary : Color.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Button { showDue = true } label: {
                if badge.style == .none {
                    Image(systemName: "calendar")
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(.quaternary)
                } else {
                    Text(badge.text)
                        .font(.system(size: 10.5 * scale, weight: .medium))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor(badge.style).opacity(0.18))
                        .foregroundStyle(badgeColor(badge.style))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDue) {
                DuePopover(due: todo.dueDate) { key in
                    state.setDue(todo, key)
                    showDue = false
                }
            }

            Button { state.delete(todo) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9 * scale, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        Divider()
    }

    private func badgeColor(_ style: DueStyle) -> Color {
        switch style {
        case .overdue: return .red
        case .today: return .orange
        default: return .secondary
        }
    }
}
```

- [ ] **Step 5: TasksView.swift 교체** (Jira 섹션은 Task 15 전까지 placeholder 텍스트)

```swift
import SwiftUI
import TaskWidgetCore

struct TasksView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsKey.todoSectionCollapsed) private var todoCollapsed = false
    @AppStorage(SettingsKey.jiraSectionCollapsed) private var jiraCollapsed = false
    @Environment(\.fontScale) private var scale
    @State private var newTitle = ""
    @State private var doneExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "내 할 일", count: state.openTodos.count, collapsed: $todoCollapsed)
                if !todoCollapsed { todoSection }

                SectionHeader(title: "Jira", count: 0, collapsed: $jiraCollapsed)
                if !jiraCollapsed {
                    Text("Jira (Task 15)").font(.system(size: 12 * scale)).foregroundStyle(.secondary).padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("할 일 추가…", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12 * scale))
                .onSubmit {
                    state.addTodo(newTitle)
                    newTitle = ""
                }
                .padding(.vertical, 4)

            ForEach(state.openTodos) { todo in
                TodoRow(todo: todo)
            }

            if state.openTodos.isEmpty {
                Text("할 일 없음").font(.system(size: 11.5 * scale)).foregroundStyle(.tertiary).padding(.vertical, 8)
            }

            if !state.doneTodos.isEmpty {
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { doneExpanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: doneExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8 * scale, weight: .semibold))
                            Text("완료 \(state.doneTodos.count)").font(.system(size: 10.5 * scale))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button("비우기") { state.clearDone() }
                        .controlSize(.mini)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.bottom, 2)

                if doneExpanded {
                    ForEach(state.doneTodos) { todo in
                        TodoRow(todo: todo)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 6: 빌드 + 수동 확인**

Run: `swift build 2>&1 | grep -E "error" ; make run`
Expected:
- 입력창에 "배포 문서 작성" + Enter → 행 추가, 입력창 비워짐. 공백만 입력 → 추가 안 됨.
- 행 우측 📅 클릭 → 팝오버. "내일" 클릭 → 배지 `D-1`. 다시 열어 "마감 없음" → 📅 로 복귀. 그래픽 달력에서 어제 날짜 선택 후 "확인" → 빨간 `D+1`. 오늘 → 주황 `오늘`.
- 마감 있는 항목이 위, 없는 항목이 아래로 정렬.
- 체크박스 클릭 → "완료 1" 접힘 섹션으로 이동. 펼치면 취소선 행. "비우기" → 사라짐.
- 행 hover 시 × 표시, 클릭 → 삭제.
- `pkill -x TaskWidget; make run` → 항목 그대로 복원. `cat ~/Library/Application\ Support/TaskWidget/todos.json` 에 `dueDate` 보임.
- "내 할 일" 헤더 클릭 → 접힘/펴짐, 재실행 후 유지.

- [ ] **Step 7: 커밋**

```bash
git add Sources/TaskWidget
git commit -m "feat(app): 할 일 섹션 — 추가/완료/삭제/마감 팝오버

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 15: Jira 섹션 UI + AppState Jira 갱신

**Files:**
- Modify: `Sources/TaskWidget/AppState.swift`
- Modify: `Sources/TaskWidget/Views/TasksView.swift` (Jira placeholder 교체)
- Create: `Sources/TaskWidget/Views/JiraSection.swift`

**Interfaces:**
- Consumes: `JiraClient`, `JiraError.userMessage`, `JiraIssue`, `Keychain.get`, `Settings.shared`, `Notification.Name.openSettings`, `SectionHeader`
- Produces: `AppState.jiraIssues`, `jiraError`, `jiraUpdatedAt`, `jiraLoading`, `jiraConfigured`, `refreshJira() async`, `JiraSection`, `JiraRow`

- [ ] **Step 1: AppState에 Jira 상태/동작 추가**

프로퍼티 (클래스 상단 `@Published var todos` 아래):
```swift
    @Published var jiraIssues: [JiraIssue] = []
    @Published var jiraError: String?
    @Published var jiraUpdatedAt: Date?
    @Published var jiraLoading = false
    @Published var jiraConfigured = false
```

메서드 (클래스 본문 끝):
```swift
    // MARK: - Jira

    func refreshJira() async {
        let s = Settings.shared
        let token = s.jiraEmail.isEmpty ? nil : Keychain.get(account: s.jiraEmail)
        jiraConfigured = token != nil
        guard let token, let url = URL(string: s.jiraBaseURL) else { return }
        guard !jiraLoading else { return }
        jiraLoading = true
        defer { jiraLoading = false }
        let client = JiraClient(baseURL: url, email: s.jiraEmail, token: token)
        do {
            let issues = try await client.fetchMyOpenIssues(jql: JiraClient.effectiveJQL(custom: s.jiraJQL))
            jiraIssues = JiraClient.sortedForDisplay(issues)
            jiraUpdatedAt = Date()
            jiraError = nil
        } catch let e as JiraError {
            jiraError = e.userMessage
        } catch {
            jiraError = error.localizedDescription
        }
    }
```

- [ ] **Step 2: JiraSection.swift**

```swift
import SwiftUI
import TaskWidgetCore

struct JiraSection: View {
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale
    @AppStorage(SettingsKey.jiraBaseURL) private var jiraBaseURL = Settings.defaultJiraBaseURL
    @AppStorage(SettingsKey.jiraRefreshMinutes) private var refreshMinutes = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !state.jiraConfigured {
                Button("설정에서 Jira 토큰 입력") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .controlSize(.small)
                .padding(.vertical, 8)
            } else {
                ForEach(JiraClient.grouped(state.jiraIssues), id: \.status) { group in
                    Text("\(group.status) · \(group.issues.count)")
                        .font(.system(size: 10.5 * scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    ForEach(group.issues) { issue in
                        JiraRow(issue: issue, baseURL: jiraBaseURL)
                    }
                }
                if state.jiraIssues.isEmpty && state.jiraError == nil && state.jiraUpdatedAt != nil {
                    Text("미완료 이슈 없음").font(.system(size: 11.5 * scale)).foregroundStyle(.tertiary).padding(.vertical, 8)
                }
                if state.jiraIssues.count >= 100 {
                    Text("100건까지만 표시").font(.system(size: 10 * scale)).foregroundStyle(.secondary).padding(.top, 4)
                }
                footer
            }
        }
        .task(id: refreshMinutes) {
            await state.refreshJira()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(1, refreshMinutes) * 60))
                await state.refreshJira()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let e = state.jiraError {
                Text(e).foregroundStyle(.red).lineLimit(1)
                Button("설정") { NotificationCenter.default.post(name: .openSettings, object: nil) }
                    .controlSize(.mini)
            } else if let t = state.jiraUpdatedAt {
                Text("↻ \(t.formatted(date: .omitted, time: .shortened)) 갱신")
            }
            Spacer()
            if state.jiraLoading {
                ProgressView().controlSize(.small)
            }
        }
        .font(.system(size: 10.5 * scale))
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }
}

struct JiraRow: View {
    let issue: JiraIssue
    let baseURL: String
    @Environment(\.fontScale) private var scale

    var body: some View {
        Button {
            if let u = URL(string: "\(baseURL)/browse/\(issue.id)") {
                NSWorkspace.shared.open(u)
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(priorityColor).frame(width: 6, height: 6)
                Text(issue.id)
                    .font(.system(size: 11 * scale, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                Text(issue.summary)
                    .font(.system(size: 12 * scale))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(issue.summary)
        Divider()
    }

    private var priorityColor: Color {
        switch issue.priority {
        case "Highest", "High": return .red
        case "Medium": return .orange
        default: return .gray
        }
    }
}
```

- [ ] **Step 3: TasksView의 Jira placeholder 교체**

`SectionHeader(title: "Jira", count: 0, ...)` 블록을 아래로 교체:
```swift
                SectionHeader(title: "Jira", count: state.jiraIssues.count, collapsed: $jiraCollapsed) {
                    Button {
                        Task { await state.refreshJira() }
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10 * scale))
                    }
                    .buttonStyle(.plain)
                    .help("새로고침")
                }
                if !jiraCollapsed { JiraSection() }
```

- [ ] **Step 4: 빌드 + 수동 확인** (토큰 저장 UI는 Task 17. 지금은 임시로 Keychain에 직접 넣어 확인)

```bash
swift build 2>&1 | grep -E "error"
# 임시: 이메일 설정 + 토큰을 Keychain 에 넣는다 (토큰은 ~/.claude/credentials.md 의 Atlassian API Token 값을 직접 입력 — 명령 기록에 남지 않게 read 사용)
defaults write com.lsm0506.TaskWidget jiraEmail lsm0506@midasin.com
read -s TOKEN && security add-generic-password -U -s com.lsm0506.TaskWidget.jira -a lsm0506@midasin.com -w "$TOKEN" && unset TOKEN
make run
```
Expected:
- Jira 섹션에 상태별 그룹("진행 중 · n" 등) + 이슈 행. 우선순위 점 색상.
- 행 클릭 → 브라우저에 `https://midasitweb-jira.atlassian.net/browse/NMRS-xxxxx` 열림.
- 푸터에 "↻ HH:mm 갱신". ↻ 버튼 클릭 → 스피너 잠깐 → 시각 갱신.
- 토큰을 틀린 값으로 바꾸고(`security add-generic-password -U ... -w wrong`) ↻ → 빨간 "토큰 확인 필요 (401/403)" + 기존 목록 유지.
- `defaults delete com.lsm0506.TaskWidget jiraEmail` 후 재실행 → "설정에서 Jira 토큰 입력" 버튼만 보임.

- [ ] **Step 5: 커밋**

```bash
git add Sources/TaskWidget
git commit -m "feat(app): Jira 섹션 — 상태별 목록, 자동 갱신, 브라우저 열기

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 16: 요약 탭 UI (SummaryView, MarkdownText) + AppState 요약 동작

**Files:**
- Modify: `Sources/TaskWidget/AppState.swift`
- Modify: `Sources/TaskWidget/Views/SummaryView.swift` (교체)
- Create: `Sources/TaskWidget/Views/MarkdownText.swift`

**Interfaces:**
- Consumes: `SummaryService`, `ClaudeRunner`, `SummaryError.userMessage`, `Summary`, `Worklog.raw/fileURL`, `Paths.logsDir`, `DayKey`
- Produces: `AppState.summaryService`, `summary`, `worklogRaw`, `summaryDay`, `summaryGenerating`, `summaryError`, `loadSummary(for:)`, `generateSummary(for:force:) async -> Bool`, `MarkdownText(markdown:)`

- [ ] **Step 1: AppState에 요약 상태/동작 추가**

프로퍼티:
```swift
    @Published var summary: Summary?
    @Published var worklogRaw: String?
    @Published var summaryDay = Date()
    @Published var summaryGenerating = false
    @Published var summaryError: String?

    /// runner 는 호출 시점의 설정(모델, 경로)을 읽는다.
    let summaryService = SummaryService { prompt in
        let s = Settings.shared
        return try ClaudeRunner(configuredPath: s.claudePath, model: s.claudeModel).run(prompt: prompt)
    }
```

메서드:
```swift
    // MARK: - Summary

    func loadSummary(for day: Date) {
        summaryDay = day
        summary = summaryService.existing(for: day)
        worklogRaw = Worklog.raw(on: day)
    }

    /// 성공하면 true. 실패는 summaryError 에.
    @discardableResult
    func generateSummary(for day: Date, force: Bool) async -> Bool {
        guard !summaryGenerating else { return false }
        summaryGenerating = true
        summaryError = nil
        defer { summaryGenerating = false }
        let service = summaryService
        do {
            let s = try await Task.detached { try service.generate(for: day, force: force) }.value
            if Calendar.current.isDate(day, inSameDayAs: summaryDay) { summary = s }
            return true
        } catch let e as SummaryError {
            summaryError = e.userMessage
        } catch {
            summaryError = error.localizedDescription
        }
        return false
    }
```

- [ ] **Step 2: MarkdownText.swift**

```swift
import SwiftUI

/// 줄 단위 간이 Markdown. `# `, `## `, `- `/`* ` 만 블록으로 처리, 나머지는 인라인 강조만.
struct MarkdownText: View {
    let markdown: String
    @Environment(\.fontScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.hasPrefix("# ") {
            Text(inline(String(line.dropFirst(2))))
                .font(.system(size: 14 * scale, weight: .bold))
                .padding(.bottom, 4)
        } else if line.hasPrefix("## ") {
            Text(inline(String(line.dropFirst(3))))
                .font(.system(size: 12.5 * scale, weight: .semibold))
                .padding(.top, 8)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                Text(inline(String(line.dropFirst(2))))
            }
            .font(.system(size: 12 * scale))
            .padding(.leading, 4)
        } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
            Color.clear.frame(height: 2)
        } else {
            Text(inline(line)).font(.system(size: 12 * scale))
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
```

- [ ] **Step 3: SummaryView.swift 교체**

```swift
import SwiftUI
import TaskWidgetCore

struct SummaryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.fontScale) private var scale
    @State private var day = Date()

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(dayLabel).font(.system(size: 12.5 * scale, weight: .medium))
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollView {
                content
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .onAppear { state.loadSummary(for: day) }
        .onChange(of: day) { _, d in state.loadSummary(for: d) }
        .onReceive(refreshTimer) { _ in
            if Calendar.current.isDateInToday(day) && !state.summaryGenerating { state.loadSummary(for: day) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let s = state.summary {
            MarkdownText(markdown: s.markdown)
        } else if let w = state.worklogRaw, !w.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("업무 일지 (요약 전)").font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
            MarkdownText(markdown: w)
        } else {
            Text("기록 없음").font(.system(size: 12 * scale)).foregroundStyle(.secondary).padding(.top, 20)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if state.summaryGenerating {
                ProgressView().controlSize(.small)
                Text("생성 중…")
            } else if let e = state.summaryError {
                Text(e).foregroundStyle(.red).lineLimit(1)
                Button("로그") { openLog() }.controlSize(.mini)
            } else if let s = state.summary {
                Text("\(s.generatedAt.formatted(date: .omitted, time: .shortened)) 생성")
            }
            Spacer()
            Button("복사") { copy() }
                .controlSize(.mini)
                .disabled(currentMarkdown == nil)
            Button(state.summary == nil ? "생성" : "다시 생성") {
                Task { await state.generateSummary(for: day, force: state.summary != nil) }
            }
            .controlSize(.mini)
            .disabled(state.summaryGenerating)
            Button("일지") { NSWorkspace.shared.open(Worklog.fileURL(for: day)) }
                .controlSize(.mini)
                .disabled(state.worklogRaw == nil)
        }
        .font(.system(size: 10.5 * scale))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var currentMarkdown: String? { state.summary?.markdown ?? state.worklogRaw }

    private func shift(_ days: Int) {
        day = Calendar.current.date(byAdding: .day, value: days, to: day)!
    }

    private func copy() {
        guard let m = currentMarkdown else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(m, forType: .string)
    }

    private func openLog() {
        NSWorkspace.shared.open(Paths.logsDir.appendingPathComponent("summary-\(DayKey.string(from: day)).log"))
    }

    private var dayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy-MM-dd (E)"
        return f.string(from: day)
    }
}
```

- [ ] **Step 4: 빌드 + 수동 확인**

```bash
swift build 2>&1 | grep -E "error"
mkdir -p ~/Library/Application\ Support/TaskWidget/worklog
printf '# %s 업무 일지\n\n## 10:00 · task-manager\n- 위젯 **설계** 스펙 작성\n- 미완료: 구현\n' "$(date +%F)" > ~/Library/Application\ Support/TaskWidget/worklog/$(date +%F).md
make run
```
Expected:
- 요약 탭: 오늘 날짜 `yyyy-MM-dd (요일)`. 본문에 "업무 일지 (요약 전)" + 일지 내용 (`**설계**` 굵게, 불릿).
- "생성" 클릭 → 스피너 "생성 중…" → 수십 초 후 `# 날짜 업무 요약` 섹션 렌더. 푸터 "HH:mm 생성". `ls ~/Library/Application\ Support/TaskWidget/summaries/` 에 파일.
- "복사" → 다른 앱에 붙여넣기 되면 markdown 원문.
- ◀ 로 어제 → "기록 없음", "생성" 클릭 → "오늘 기록 없음" 파일 생성(활동 없을 때). ▶ 로 복귀.
- 설정 `claudePath`를 엉뚱한 값으로: `defaults write com.lsm0506.TaskWidget claudePath /nonexistent` 는 자동 탐색으로 넘어가므로 실패 안 함. 대신 PATH 에 없는 환경 확인은 생략. "다시 생성" 중 claude 가 죽는 케이스는 `pkill -f "claude -p"` 로 유도 → 빨간 에러 + "로그" 버튼으로 로그 열림.
- "일지" 버튼 → 기본 에디터로 worklog 파일 열림.

- [ ] **Step 5: 커밋**

```bash
git add Sources/TaskWidget
git commit -m "feat(app): 요약 탭 — 날짜 이동, 일지/요약 표시, 생성, 복사

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 17: 설정 화면 (SettingsView) — 외관/창/일반/Jira/요약/Claude 연동/데이터

**Files:**
- Modify: `Sources/TaskWidget/Views/SettingsView.swift` (교체)

**Interfaces:**
- Consumes: `SettingsKey.*`, `Settings.defaultJiraBaseURL`, `Keychain.get/set`, `JiraClient.whoAmI`, `JiraError.userMessage`, `ClaudeIntegration`, `HookStatus`, `Paths.dataDir/summariesDir`, `AppState.refreshJira`
- 외관/창 변경은 `UserDefaults.didChangeNotification` → `AppDelegate` → `FloatingPanel.applyAppearance()` (Task 13에서 연결됨). 글자 크기는 `RootView`의 `@AppStorage(fontScale)` 가 환경값으로 전파.

- [ ] **Step 1: SettingsView.swift 교체**

```swift
import SwiftUI
import ServiceManagement
import TaskWidgetCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var state: AppState

    @AppStorage(SettingsKey.opacity) private var opacity = 1.0
    @AppStorage(SettingsKey.hoverOpaque) private var hoverOpaque = true
    @AppStorage(SettingsKey.theme) private var theme = "system"
    @AppStorage(SettingsKey.fontScale) private var fontScale = 1.0
    @AppStorage(SettingsKey.alwaysOnTop) private var alwaysOnTop = true
    @AppStorage(SettingsKey.allSpaces) private var allSpaces = true
    @AppStorage(SettingsKey.jiraBaseURL) private var jiraBaseURL = Settings.defaultJiraBaseURL
    @AppStorage(SettingsKey.jiraEmail) private var jiraEmail = ""
    @AppStorage(SettingsKey.jiraRefreshMinutes) private var jiraRefreshMinutes = 5
    @AppStorage(SettingsKey.jiraJQL) private var jiraJQL = ""
    @AppStorage(SettingsKey.summaryHour) private var summaryHour = 18
    @AppStorage(SettingsKey.summaryMinute) private var summaryMinute = 0
    @AppStorage(SettingsKey.summaryNotify) private var summaryNotify = true
    @AppStorage(SettingsKey.claudeModel) private var claudeModel = ""
    @AppStorage(SettingsKey.claudePath) private var claudePath = ""

    @State private var token = ""
    @State private var tokenStatus = ""
    @State private var loginAtStart = false
    @State private var hookStatus: HookStatus = .notInstalled
    @State private var skillInstalled = false
    @State private var integrationError = ""
    @State private var todayActivityCount = 0

    private var integration: ClaudeIntegration {
        ClaudeIntegration(executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0])
    }
    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("외관") {
                    Slider(value: $opacity, in: 0.6...1.0, step: 0.05) {
                        Text("투명도 \(Int((opacity * 100).rounded()))%")
                    }
                    Toggle("마우스 올리면 불투명", isOn: $hoverOpaque)
                    Picker("테마", selection: $theme) {
                        Text("시스템").tag("system")
                        Text("라이트").tag("light")
                        Text("다크").tag("dark")
                    }
                    Picker("글자 크기", selection: $fontScale) {
                        Text("작게").tag(0.9)
                        Text("보통").tag(1.0)
                        Text("크게").tag(1.15)
                    }
                }

                Section("창") {
                    Toggle("항상 위", isOn: $alwaysOnTop)
                    Toggle("모든 Spaces에 표시", isOn: $allSpaces)
                }

                Section("일반") {
                    Toggle("로그인 시 실행", isOn: $loginAtStart)
                        .disabled(!isBundled)
                        .onChange(of: loginAtStart) { _, on in setLogin(on) }
                    if !isBundled {
                        Text("앱 번들로 실행했을 때만 가능 (make install)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Jira") {
                    TextField("URL", text: $jiraBaseURL)
                    TextField("이메일", text: $jiraEmail)
                    HStack {
                        SecureField("API 토큰 (저장 후 비워짐)", text: $token)
                        Button("저장") { saveToken() }
                            .disabled(token.isEmpty || jiraEmail.isEmpty)
                    }
                    HStack {
                        Button("연결 테스트") { testJira() }
                        Text(tokenStatus).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Picker("갱신 주기", selection: $jiraRefreshMinutes) {
                        Text("1분").tag(1)
                        Text("5분").tag(5)
                        Text("15분").tag(15)
                    }
                    TextField("JQL (비우면 기본값)", text: $jiraJQL)
                }

                Section("요약") {
                    HStack {
                        Text("생성 시각")
                        Spacer()
                        Picker("", selection: $summaryHour) {
                            ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .labelsHidden().frame(width: 70)
                        Text(":")
                        Picker("", selection: $summaryMinute) {
                            ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .labelsHidden().frame(width: 70)
                    }
                    Toggle("완료 알림", isOn: $summaryNotify)
                    TextField("모델 (비우면 CLI 기본)", text: $claudeModel)
                    TextField("claude 경로 (비우면 자동 탐색)", text: $claudePath)
                }

                Section("Claude 연동") {
                    HStack {
                        Text("활동 훅")
                        Spacer()
                        Text("\(hookLabel) · 오늘 \(todayActivityCount)건").foregroundStyle(.secondary)
                        Button(hookButton) { toggleHook() }
                    }
                    HStack {
                        Text("/worklog 스킬")
                        Spacer()
                        Text(skillInstalled ? "설치됨" : "미설치").foregroundStyle(.secondary)
                        Button(skillInstalled ? "제거" : "설치") { toggleSkill() }
                    }
                    if !integrationError.isEmpty {
                        Text(integrationError).foregroundStyle(.red).font(.caption)
                    }
                    HStack {
                        Button("데이터 폴더 열기") { NSWorkspace.shared.open(Paths.dataDir) }
                        Button("요약 폴더 열기") { NSWorkspace.shared.open(Paths.summariesDir) }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(10)
        }
        .frame(width: 460, height: 600)
        .onAppear(perform: refreshStatus)
    }

    // MARK: - Actions

    private func refreshStatus() {
        hookStatus = integration.hookStatus()
        skillInstalled = integration.skillInstalled()
        todayActivityCount = ActivityLog.records(on: Date(), from: Paths.activityFile).count
        if isBundled { loginAtStart = SMAppService.mainApp.status == .enabled }
    }

    private func setLogin(_ on: Bool) {
        guard isBundled else { return }
        let current = SMAppService.mainApp.status == .enabled
        guard current != on else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            integrationError = "로그인 항목 변경 실패: \(error.localizedDescription)"
            loginAtStart = current
        }
    }

    private func saveToken() {
        do {
            try Keychain.set(token, account: jiraEmail)
            token = ""
            tokenStatus = "저장됨"
            Task { await state.refreshJira() }
        } catch {
            tokenStatus = "저장 실패: \(error)"
        }
    }

    private func testJira() {
        guard let url = URL(string: jiraBaseURL), let t = Keychain.get(account: jiraEmail) else {
            tokenStatus = "토큰 없음"
            return
        }
        tokenStatus = "확인 중…"
        Task {
            do {
                tokenStatus = "OK: " + (try await JiraClient(baseURL: url, email: jiraEmail, token: t).whoAmI())
            } catch let e as JiraError {
                tokenStatus = e.userMessage
            } catch {
                tokenStatus = error.localizedDescription
            }
        }
    }

    private var hookLabel: String {
        switch hookStatus {
        case .installed: return "설치됨"
        case .notInstalled: return "미설치"
        case .pathMismatch: return "경로 불일치"
        }
    }

    private var hookButton: String {
        switch hookStatus {
        case .installed: return "제거"
        case .notInstalled: return "설치"
        case .pathMismatch: return "재설치"
        }
    }

    private func toggleHook() {
        do {
            if hookStatus == .installed { try integration.removeHook() } else { try integration.installHook() }
            integrationError = ""
        } catch {
            integrationError = "훅 변경 실패: \(error)"
        }
        refreshStatus()
    }

    private func toggleSkill() {
        do {
            if skillInstalled { try integration.removeSkill() } else { try integration.installSkill() }
            integrationError = ""
        } catch {
            integrationError = "스킬 변경 실패: \(error)"
        }
        refreshStatus()
    }
}
```

- [ ] **Step 2: 빌드 + 수동 확인**

Run: `swift build 2>&1 | grep -E "error"; make run`
Expected:
- 기어 → 설정 시트 (460×600). 텍스트 필드에 타이핑 됨 (nonactivating 패널 위 시트에서 입력 안 되면 `RootView`의 `NSApp.activate` 호출이 있는지 확인).
- 투명도 슬라이더 60% → 패널 전체 반투명. 마우스 올리면 불투명(토글 on) → 커서 올리면 100%, 빼면 복귀.
- 테마 "다크" → 즉시 다크. "시스템" → 복귀.
- 글자 크기 "크게" → 목록 글자 커짐.
- "항상 위" off → 다른 창 클릭 시 뒤로 감. on → 복귀. "모든 Spaces" off → 다른 데스크톱으로 이동 시 안 따라옴.
- Jira: 이메일 입력, 토큰 붙여넣기 → "저장" → 필드 비워지고 "저장됨", Jira 섹션 갱신. "연결 테스트" → "OK: <displayName>". 토큰 잘못 넣으면 "토큰 확인 필요 (401/403)". JQL 에 `project = NMRS AND assignee = currentUser() AND statusCategory != Done` → 목록 바뀜. 엉터리 JQL → Jira 섹션에 "JQL 오류: …".
- 요약: 시각 변경 → (Task 18 후) 스케줄 재등록.
- Claude 연동: "설치" → `cat ~/.claude/settings.json | jq '.hooks.Stop'` 에 `"…/TaskWidget" --hook` 항목, 백업 파일 `~/.claude/settings.json.bak-*` 생성, 상태 "설치됨". Claude Code 새 세션에서 아무 프롬프트 → `tail -2 ~/Library/Application\ Support/TaskWidget/activity.jsonl` 에 prompt/stop 두 줄. 설정 다시 열면 "오늘 n건" 증가. "제거" → 항목 사라지고 다른 훅은 그대로.
- "/worklog 스킬" 설치 → `~/.claude/skills/worklog/SKILL.md` 존재. Claude Code 에서 `/worklog` → `worklog/오늘.md` 에 섹션 append, 요약 탭에 30초 내 반영.
- "로그인 시 실행": `make install` 후 `/Applications/TaskWidget.app` 으로 실행했을 때만 토글 가능. 시스템 설정 > 일반 > 로그인 항목에 TaskWidget 나타남.
- 데이터 폴더 열기 → Finder.

- [ ] **Step 3: 커밋**

```bash
git add Sources/TaskWidget/Views/SettingsView.swift
git commit -m "feat(app): 설정 화면 — 외관/창/Jira/요약/Claude 연동

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 18: Scheduler (자동 생성, catch-up, 알림) + 메뉴 항목

**Files:**
- Create: `Sources/TaskWidget/Scheduler.swift`
- Modify: `Sources/TaskWidget/AppDelegate.swift`

**Interfaces:**
- Consumes: `Schedule.nextFireDate`, `Settings.shared.summaryHour/summaryMinute/summaryNotify`, `AppState.summaryService.existing`, `AppState.generateSummary`, `AppState.loadSummary`, `AppState.summaryError`
- Produces: `Scheduler(state:)`, `.start()`, `.reschedule()`, `.catchUp()`

- [ ] **Step 1: Scheduler.swift**

```swift
import AppKit
import UserNotifications
import TaskWidgetCore

@MainActor
final class Scheduler {
    private let state: AppState
    private var timer: Timer?
    private var scheduledKey = ""
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
            Task { @MainActor in self?.catchUp() }
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
        catchUp()
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
        guard state.summaryService.existing(for: today) == nil else { return }
        let ok = await state.generateSummary(for: today, force: false)
        if Settings.shared.summaryNotify {
            notify(ok ? "오늘 요약 완료" : "요약 실패", body: ok ? "" : (state.summaryError ?? ""))
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
```

- [ ] **Step 2: AppDelegate에 스케줄러와 메뉴 항목 추가**

프로퍼티 추가:
```swift
    private var scheduler: Scheduler!
```

`applicationDidFinishLaunching` 끝(`panel.makeKeyAndOrderFront(nil)` 앞)에 추가:
```swift
        scheduler = Scheduler(state: state)
        scheduler.start()
```

`showMenu()` 의 `settingsItem` 앞에 추가:
```swift
        let genItem = NSMenuItem(title: "요약 지금 생성", action: #selector(generateNow), keyEquivalent: "")
        genItem.target = self
        menu.addItem(genItem)
```

메서드 추가:
```swift
    @objc private func generateNow() {
        panel.makeKeyAndOrderFront(nil)
        UserDefaults.standard.set("summary", forKey: SettingsKey.lastTab)
        Task { await state.generateSummary(for: Date(), force: true) }
    }
```

- [ ] **Step 3: 빌드 + 수동 확인**

```bash
swift build 2>&1 | grep -E "error"
rm -f ~/Library/Application\ Support/TaskWidget/summaries/$(date +%F).md
make install && open /Applications/TaskWidget.app
```
Expected:
- 첫 실행 시 알림 권한 요청 → 허용.
- 설정에서 생성 시각을 현재 시각 + 2분으로 → 2분 뒤 자동 생성, "오늘 요약 완료" 알림, 요약 탭에 내용. `log stream --predicate 'process == "TaskWidget"' --style compact` 에 `summary scheduled at` 다음 날 시각.
- 오늘 파일 지우고 생성 시각을 과거(예: 1분 전)로 바꾸면 catch-up 으로 즉시 생성.
- 파일이 이미 있으면 시각 변경해도 재생성 안 함.
- 메뉴바 우클릭 → "요약 지금 생성" → 요약 탭 열리고 강제 재생성.
- Mac 잠자기 → 깨우기 (예정 시각 지난 상태, 파일 없음) → 생성.

- [ ] **Step 4: 커밋**

```bash
git add Sources/TaskWidget
git commit -m "feat(app): 요약 자동 생성 스케줄, catch-up, 알림, 메뉴 항목

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 19: README, 설치, 전체 수동 체크리스트

**Files:**
- Create: `README.md`

- [ ] **Step 1: README.md 작성**

```markdown
# TaskWidget

macOS 메뉴바 상주 플로팅 위젯. 할 일(마감일) + 내 Jira 미완료 이슈 + Claude Code 세션 기반 하루 업무 요약.

## 설치

```bash
make install            # /Applications/TaskWidget.app
open /Applications/TaskWidget.app
```

처음 한 번:

1. 메뉴바 체크리스트 아이콘 → 패널 → 기어(설정)
2. **Jira**: 이메일 + API 토큰 입력 → 저장 → 연결 테스트
3. **Claude 연동**: "활동 훅 설치", "/worklog 스킬 설치"
4. **일반**: 로그인 시 실행

## 사용

- 할 일: 입력 후 Enter. 📅/배지 클릭으로 마감 설정. 지난 마감 빨강, 오늘 주황.
- Jira: 내게 할당된 미완료 이슈. 클릭하면 브라우저. 설정에서 JQL 교체 가능.
- 요약: 매일 설정 시각(기본 18:00)에 자동 생성. Claude Code 세션에서 `/worklog` 로 일지를 남기면 그게 1급 입력, 훅이 모은 대화 기록은 보완.
- 요약은 `claude -p` 로 생성 (Claude Code CLI 구독 사용).

## 데이터

`~/Library/Application Support/TaskWidget/`
- `todos.json`, `activity.jsonl`, `worklog/`, `summaries/`, `logs/`
- Jira 토큰은 Keychain (`com.lsm0506.TaskWidget.jira`)

## 개발

```bash
make build   # swift build
make test    # swift test (Core 단위 테스트)
make run     # build/TaskWidget.app 실행
```

앱을 옮기면 `~/.claude/settings.json` 의 훅 경로가 깨진다. 설정 > Claude 연동에서 "재설치".

설계: `docs/superpowers/specs/2026-10-02-task-widget-design.md`
```

- [ ] **Step 2: 전체 테스트 + 릴리스 빌드**

Run: `swift test 2>&1 | tail -2 && make install`
Expected: `0 failures`, `/Applications/TaskWidget.app` 갱신.

- [ ] **Step 3: 전체 수동 체크리스트** (하나씩 확인 후 체크)

- [ ] 메뉴바 아이콘만 있고 Dock 없음. 좌클릭 토글, 우클릭 메뉴 4개
- [ ] 패널이 Finder/브라우저/터미널 위에 떠 있음. 전체화면 앱 위에서도 보임 (allSpaces on)
- [ ] 할 일 추가/완료/삭제/마감/비우기, 재실행 후 유지
- [ ] Jira 목록, 클릭 시 브라우저, ↻, 토큰 오류 메시지, JQL 커스텀
- [ ] 설정 각 항목 즉시 반영 (투명도, 호버, 테마, 글자 크기, 항상 위, Spaces)
- [ ] 훅 설치 후 Claude Code 세션 → activity.jsonl 증가. 요약 생성용 claude -p 세션은 기록 안 됨 (cwd = 데이터 폴더)
- [ ] `/worklog` 스킬 → worklog 파일 append → 요약 탭 즉시 표시
- [ ] 예정 시각 자동 생성 + 알림. 재실행/깨우기 catch-up. 수동 "다시 생성"
- [ ] 기록 없는 날 → "오늘 기록 없음" 파일
- [ ] 로그인 시 실행 토글 → 시스템 설정 로그인 항목에 표시
- [ ] 앱 종료 후 재실행 시 패널 위치/크기/탭/섹션 접힘 유지

- [ ] **Step 4: 커밋 + 푸시**

```bash
git add README.md
git commit -m "docs: README — 설치/사용/데이터 위치

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push
```
