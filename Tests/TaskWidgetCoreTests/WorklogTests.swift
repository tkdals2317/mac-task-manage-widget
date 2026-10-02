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

    func testMalformedHeadersAreBodyNotEntries() {
        // 각각 단독으로는 항목을 만들지 않는다 (`## · x` 는 예전 구현에서 trap)
        for bad in ["## · x", "## 메모 · x", "## 09:40 · ", "## 9:40 · x", "## 09:40 · \t", "## 09:40 ·x"] {
            XCTAssertEqual(Worklog.parse(bad), [], bad)
        }
        // 열린 항목이 있으면 그 본문으로 들어간다
        let md = "## 09:40 · proj\n- a\n## · x\n## 메모 · x\n## 9:40 · y\n## 10:00 · \n- b"
        let e = Worklog.parse(md)
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].project, "proj")
        XCTAssertEqual(e[0].body, "- a\n## · x\n## 메모 · x\n## 9:40 · y\n## 10:00 · \n- b")
    }

    func testProjectKeepsLaterSeparator() {
        let e = Worklog.parse("## 09:40 · a · b\n- x")
        XCTAssertEqual(e.map(\.project), ["a · b"])
    }

    func testInvalidUTF8StillReturnsEntry() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("worklog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let day = DayKey.date(from: "2026-10-02", calendar: seoul)!
        var data = Data("## 09:40 · proj\n- a".utf8)
        data.append(0xFF)
        data.append(Data("b\n".utf8))
        try data.write(to: Worklog.fileURL(for: day, dir: dir, calendar: seoul))

        let e = Worklog.entries(on: day, dir: dir, calendar: seoul)
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].project, "proj")
        XCTAssertEqual(e[0].body, "- a\u{FFFD}b")
        XCTAssertNotNil(Worklog.raw(on: day, dir: dir, calendar: seoul))
    }

    func testFileURLAndMissing() {
        let dir = URL(fileURLWithPath: "/tmp/wl")
        let day = DayKey.date(from: "2026-10-02", calendar: seoul)!
        XCTAssertEqual(Worklog.fileURL(for: day, dir: dir, calendar: seoul).lastPathComponent, "2026-10-02.md")
        XCTAssertNil(Worklog.raw(on: day, dir: dir, calendar: seoul))
        XCTAssertEqual(Worklog.entries(on: day, dir: dir, calendar: seoul), [])
    }
}
