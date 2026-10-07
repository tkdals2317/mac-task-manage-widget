import XCTest
@testable import TaskWidgetCore

final class JiraVersionsTests: XCTestCase {
    func issue(_ id: String, _ v: [String], status: String = "진행 중") -> JiraIssue {
        JiraIssue(id: id, summary: id, status: status, statusCategory: "indeterminate",
                  priority: nil, updated: Date(timeIntervalSince1970: 0), fixVersions: v)
    }

    var sample: [JiraIssue] {
        [issue("A", ["15.9.2"]), issue("B", ["15.10.0"]), issue("C", ["15.9.2", "15.10.0"]), issue("D", [])]
    }

    func testStorageRoundTrip() {
        for f in [VersionFilter.all, .none, .named("15.3.0")] {
            XCTAssertEqual(VersionFilter(storage: f.storage), f)
        }
        XCTAssertEqual(VersionFilter.all.storage, "")
    }

    func testCounts() {
        let c = JiraVersions.counts(sample)
        XCTAssertEqual(c.versions.map(\.name), ["15.10.0", "15.9.2"])
        XCTAssertEqual(c.versions.map(\.count), [2, 2])
        XCTAssertEqual(c.noneCount, 1)
    }

    func testFilter() {
        XCTAssertEqual(JiraVersions.filter(sample, .all).count, 4)
        XCTAssertEqual(JiraVersions.filter(sample, .none).map(\.id), ["D"])
        XCTAssertEqual(Set(JiraVersions.filter(sample, .named("15.9.2")).map(\.id)), ["A", "C"])
        XCTAssertEqual(Set(JiraVersions.filter(sample, .named("15.10.0")).map(\.id)), ["B", "C"])
        XCTAssertTrue(JiraVersions.filter(sample, .named("9.9")).isEmpty)
    }

    func testGrouped() {
        let g = JiraVersions.grouped(sample)
        XCTAssertEqual(g.map(\.title), ["15.10.0", "15.9.2", nil])
        XCTAssertEqual(Set(g[0].issues.map(\.id)), ["B", "C"])
        XCTAssertEqual(Set(g[1].issues.map(\.id)), ["A", "C"])
        XCTAssertEqual(g[2].issues.map(\.id), ["D"])
        XCTAssertEqual(JiraVersions.grouped([issue("X", [])]).count, 1)
    }

    func testTag() {
        XCTAssertNil(JiraVersions.tag(for: issue("a", [])))
        XCTAssertEqual(JiraVersions.tag(for: issue("a", ["15.3.0"])), "15.3.0")
        XCTAssertEqual(JiraVersions.tag(for: issue("a", ["15.3.0", "15.2.1"])), "15.3.0 +1")
    }
}
