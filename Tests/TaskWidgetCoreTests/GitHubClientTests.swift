import XCTest
@testable import TaskWidgetCore

final class GitHubClientTests: XCTestCase {
    func node(_ number: Int, repo: String, author: String, reviews: String = "[]", requests: String = "[]") -> String {
        """
        {"number": \(number), "title": "T\(number)", "url": "https://github.com/o/\(repo)/pull/\(number)", "isDraft": false,
         "createdAt": "2026-10-10T00:00:00Z", "updatedAt": "2026-10-11T00:00:00Z", "additions": 10, "deletions": 2, "changedFiles": 3,
         "headRefName": "feat", "baseRefName": "main", "repository": {"nameWithOwner": "o/\(repo)", "name": "\(repo)"},
         "author": {"login": "\(author)"}, "comments": {"totalCount": 4},
         "commits": {"nodes": [{"commit": {"committedDate": "2026-10-12T00:00:00Z"}}]},
         "reviewRequests": {"nodes": \(requests)},
         "latestOpinionatedReviews": {"nodes": \(reviews)}}
        """
    }

    func testDecode() throws {
        let mineReviews = """
        [{"author": {"login": "bob"}, "state": "APPROVED", "submittedAt": "2026-10-11T05:00:00Z"},
         {"author": {"login": "cat"}, "state": "CHANGES_REQUESTED", "submittedAt": "2026-10-11T06:00:00Z"},
         {"author": {"login": "dan"}, "state": "DISMISSED", "submittedAt": "2026-10-11T06:00:00Z"}]
        """
        let requests = #"[{"requestedReviewer": {"login": "eve"}}, {"requestedReviewer": {"name": "backend-team"}}, {"requestedReviewer": {"login": "bob"}}]"#
        let myReview = #"[{"author": {"login": "me"}, "state": "COMMENTED", "submittedAt": "2026-10-11T01:00:00Z"}]"#
        let json = """
        {"data": {"viewer": {"login": "me"},
         "requested": {"nodes": [\(node(1, repo: "api", author: "zed")), {}]},
         "reviewed": {"nodes": [\(node(1, repo: "api", author: "zed")), \(node(2, repo: "web", author: "amy", reviews: myReview))]},
         "mine": {"nodes": [\(node(3, repo: "task-widget", author: "me", reviews: mineReviews, requests: requests))]}}}
        """
        let data = Data(json.utf8)
        XCTAssertEqual(try GitHubClient.viewerLogin(data), "me")
        let r = try GitHubClient.decode(data, me: "me")
        XCTAssertEqual(r.reviewRequests.map(\.id), ["github:o/api#1", "github:o/web#2"], "중복 제거, 빈 노드 무시")
        XCTAssertEqual(r.reviewRequests.map(\.reviewRequested), [true, false], "reviewed-by 검색에서만 나온 PR 은 요청 아님")
        let web = r.reviewRequests[1]
        XCTAssertEqual(web.myReviewAt, PRLogic.parseDate("2026-10-11T01:00:00Z"))
        XCTAssertTrue(PRLogic.hasNewCommitsSinceMyReview(web))
        let m = r.mine[0]
        XCTAssertEqual(m.repo, "task-widget")
        XCTAssertEqual([m.additions, m.deletions, m.changedFiles, m.commentCount], [10, 2, 3, 4])
        XCTAssertEqual(m.sourceBranch, "feat")
        XCTAssertEqual(m.reviewers.map(\.name), ["bob", "cat", "eve", "backend-team"], "DISMISSED 제외, 이미 리뷰한 사람은 대기에서 제외")
        XCTAssertEqual(m.reviewers.map(\.state), [.approved, .changesRequested, .pending, .pending])
        XCTAssertEqual(PRLogic.approval(m), .changesRequested)
    }

    func testGraphQLError() {
        XCTAssertThrowsError(try GitHubClient.decode(Data(#"{"errors":[{"message":"Bad credentials"}]}"#.utf8), me: "x")) {
            XCTAssertEqual($0 as? PRError, .message("Bad credentials"))
        }
    }
}
