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

    func testDecodeFixVersions() throws {
        let issues = try JiraClient.decodeSearch(try fixture())
        func v(_ k: String) -> [String] { issues.first { $0.id == k }!.fixVersions }
        XCTAssertEqual(v("NMRS-20414"), ["15.3.0"])
        XCTAssertEqual(v("NMRS-20388"), ["15.2.1", "15.3.0"])
        XCTAssertEqual(v("NMRS-20450"), [], "필드 없음")
        XCTAssertEqual(v("NMRS-20001"), [], "null")
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

    func testDecodePageTruncatedFlag() throws {
        XCTAssertFalse(try JiraClient.decodePage(try fixture()).truncated, "isLast: true")
        let more = Data(#"{"isLast":false,"issues":[]}"#.utf8)
        XCTAssertTrue(try JiraClient.decodePage(more).truncated)
        let noFlag = Data(#"{"issues":[]}"#.utf8)
        XCTAssertFalse(try JiraClient.decodePage(noFlag).truncated, "isLast 없으면 잘리지 않은 것으로")
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
