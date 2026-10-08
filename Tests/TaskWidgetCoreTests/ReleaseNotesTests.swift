import XCTest
@testable import TaskWidgetCore

final class ReleaseNotesTests: XCTestCase {
    let sample = """
    # 업데이트 노트

    머리말은 무시한다.

    ## 1.10.0 — 2026-10-10
    - 열 번째 기능
      - 하위 항목

    ## 1.9.0 - 2026-10-09
    - 아홉 번째

    ## 1.6.0
    - 날짜 없음
    """

    func testParse() {
        let n = ReleaseNotes.parse(sample)
        XCTAssertEqual(n.map(\.version), ["1.10.0", "1.9.0", "1.6.0"])
        XCTAssertEqual(n.map(\.date), ["2026-10-10", "2026-10-09", nil])
        XCTAssertEqual(n[0].body, "- 열 번째 기능\n  - 하위 항목")
        XCTAssertEqual(n[2].body, "- 날짜 없음")
    }

    func testCompare() {
        XCTAssertEqual(ReleaseNotes.compareVersions("1.10", "1.9"), .orderedDescending)
        XCTAssertEqual(ReleaseNotes.compareVersions("1.6", "1.6.0"), .orderedSame)
        XCTAssertEqual(ReleaseNotes.compareVersions("1.5.9", "1.6.0"), .orderedAscending)
        XCTAssertEqual(ReleaseNotes.compareVersions("x", "0.0.0"), .orderedSame)
    }

    func testNewer() {
        let n = ReleaseNotes.parse(sample)
        XCTAssertEqual(ReleaseNotes.newer(than: "1.6.0", in: n).map(\.version), ["1.10.0", "1.9.0"])
        XCTAssertEqual(ReleaseNotes.newer(than: "1.9.0", in: n).map(\.version), ["1.10.0"])
        XCTAssertEqual(ReleaseNotes.newer(than: "1.10.0", in: n), [])
        XCTAssertEqual(ReleaseNotes.newer(than: "unknown", in: n).map(\.version), ["1.10.0"])
    }
}
