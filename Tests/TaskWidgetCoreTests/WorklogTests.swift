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
