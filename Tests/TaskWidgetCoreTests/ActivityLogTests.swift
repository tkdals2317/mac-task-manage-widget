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
        XCTAssertNil(ActivityLog.record(fromHookInput: hook(#"{"hook_event_name":"UserPromptSubmit","prompt":"hi"}"#), excludingCwdPrefix: "", now: now))
        XCTAssertNil(ActivityLog.record(fromHookInput: hook(#"{"hook_event_name":"UserPromptSubmit","prompt":"hi","cwd":""}"#), excludingCwdPrefix: "", now: now))
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

    func testInvalidUtf8ByteDoesNotHideOtherLines() throws {
        let file = dir.appendingPathComponent("activity.jsonl")
        let r1 = ActivityRecord(ts: now, event: "prompt", session: "a", cwd: "/p", text: "one")
        let r2 = ActivityRecord(ts: now.addingTimeInterval(1), event: "stop", session: "b", cwd: "/p", text: "two")
        var data = try ActivityLog.encoder.encode(r1)
        data.append(contentsOf: [0x0A, 0xFF, 0x0A])
        data.append(try ActivityLog.encoder.encode(r2))
        data.append(0x0A)
        try data.write(to: file)
        XCTAssertEqual(ActivityLog.records(on: now, from: file).map(\.session), ["a", "b"], "깨진 바이트 한 줄이 파일 전체를 날리면 안 된다")
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
