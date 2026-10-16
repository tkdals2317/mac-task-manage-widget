import XCTest
@testable import TaskWidgetCore

final class BitbucketClientTests: XCTestCase {
    let me = "{aaaa-1111}"

    func testUserAndWorkspaces() throws {
        let u = try BitbucketClient.decodeUser(Data(#"{"uuid":"{aaaa-1111}","display_name":"Kim","account_id":"123"}"#.utf8))
        XCTAssertEqual([u.uuid, u.displayName, u.accountId], ["{aaaa-1111}", "Kim", "123"])
        let ws = try BitbucketClient.decodeWorkspaces(Data(#"{"values":[{"workspace":{"slug":"midas","name":"Midas"}},{"workspace":{"slug":"x"}}]}"#.utf8))
        XCTAssertEqual(ws.workspaces, [BBWorkspace(slug: "midas", name: "Midas"), BBWorkspace(slug: "x", name: "x")])
        let flat = try BitbucketClient.decodeWorkspaces(Data(#"{"values":[{"slug":"a","name":"A"}],"next":"https://api.bitbucket.org/2.0/user/workspaces?page=2"}"#.utf8))
        XCTAssertEqual(flat.workspaces, [BBWorkspace(slug: "a", name: "A")])
        XCTAssertNotNil(flat.next)
    }

    func testRepositories() throws {
        let r = try BitbucketClient.decodeRepositories(Data(#"{"values":[{"slug":"a","name":"A","updated_on":"2026-10-01T00:00:00.123456+00:00"}],"next":"https://x/next"}"#.utf8))
        XCTAssertEqual(r.repos.map(\.slug), ["a"])
        XCTAssertNotNil(r.repos[0].updatedOn)
        XCTAssertEqual(r.next, "https://x/next")
    }

    func testPullRequests() throws {
        let json = """
        {"values": [{"id": 34, "title": "Fix", "draft": true, "comment_count": 2,
          "created_on": "2026-10-10T00:00:00.000000+00:00", "updated_on": "2026-10-11T00:00:00.000000+00:00",
          "author": {"display_name": "Lee"},
          "source": {"branch": {"name": "feature/x"}},
          "destination": {"branch": {"name": "develop"}, "repository": {"full_name": "midas/mrs-cms", "name": "mrs-cms"}},
          "links": {"html": {"href": "https://bitbucket.org/midas/mrs-cms/pull-requests/34"}},
          "participants": [
            {"user": {"uuid": "{aaaa-1111}", "display_name": "Kim"}, "role": "REVIEWER", "approved": true, "state": "approved", "participated_on": "2026-10-11T03:00:00.000000+00:00"},
            {"user": {"uuid": "{bbbb}", "display_name": "Park"}, "role": "REVIEWER", "approved": false, "state": "changes_requested", "participated_on": "2026-10-11T04:00:00.000000+00:00"},
            {"user": {"uuid": "{cccc}", "display_name": "Choi"}, "role": "REVIEWER", "approved": false, "state": null, "participated_on": null},
            {"user": {"uuid": "{dddd}", "display_name": "Author"}, "role": "PARTICIPANT", "approved": false, "state": null}],
          "reviewers": [{"uuid": "{cccc}", "display_name": "Choi"}, {"uuid": "{eeee}", "display_name": "Han"}]}],
         "next": null}
        """
        let r = try BitbucketClient.decodePullRequests(Data(json.utf8), me: me)
        XCTAssertEqual(r.prs.count, 1)
        let p = r.prs[0]
        XCTAssertEqual(p.id, "bitbucket:midas/mrs-cms#34")
        XCTAssertEqual([p.repo, p.author, p.sourceBranch, p.targetBranch], ["mrs-cms", "Lee", "feature/x", "develop"])
        XCTAssertTrue(p.isDraft)
        XCTAssertEqual(p.commentCount, 2)
        XCTAssertNil(p.additions)
        XCTAssertEqual(p.reviewers.map(\.name), ["Kim", "Park", "Choi", "Han"])
        XCTAssertEqual(p.reviewers.map(\.state), [.approved, .changesRequested, .pending, .pending])
        XCTAssertEqual(p.myReviewAt, PRLogic.parseDate("2026-10-11T03:00:00Z"))
        XCTAssertEqual(PRLogic.approval(p), .changesRequested)
    }

    func testURLEncoding() {
        let u = BitbucketClient.url("/repositories/ws/s/pullrequests", [.init(name: "fields", value: "+values.participants"), .init(name: "q", value: #"state="OPEN" AND reviewers.uuid="{u}""#)])!
        XCTAssertTrue(u.absoluteString.contains("fields=%2Bvalues.participants"))
        XCTAssertFalse(u.absoluteString.contains("{"))
        XCTAssertFalse(u.absoluteString.contains(" "))
        XCTAssertTrue(BitbucketClient.url("/workspaces/w/pullrequests/{abc}")!.absoluteString.contains("%7Babc%7D"))
    }

    func testDecodeComments() throws {
        let json = #"{"values":[{"id":11,"user":{"uuid":"{bbbb}","display_name":"Park"}},{"id":12,"user":{"uuid":"{aaaa-1111}","display_name":"Kim"}},{"id":13,"deleted":true,"user":{"uuid":"{cccc}"}}]}"#
        XCTAssertEqual(try BitbucketClient.decodeComments(Data(json.utf8), me: me), [PRActivity(id: "bb:11", author: "Park")])
    }

    func testSafeNext() {
        XCTAssertNotNil(BitbucketClient.safeNext("https://api.bitbucket.org/2.0/repositories/x?page=2"))
        XCTAssertNil(BitbucketClient.safeNext("http://api.bitbucket.org/2.0/x"))
        XCTAssertNil(BitbucketClient.safeNext("https://evil.example.com/2.0/x"))
        XCTAssertNil(BitbucketClient.safeNext("https://api.bitbucket.org.evil.com/x"))
    }

    func testMapConcurrentKeepsOrder() async {
        let r = await BitbucketClient.mapConcurrent([1, 2, 3, 4, 5, 6, 7, 8], limit: 3) { n -> Int in
            try? await Task.sleep(nanoseconds: UInt64((9 - n) * 1_000_000)); return n * 2
        }
        XCTAssertEqual(r, [2, 4, 6, 8, 10, 12, 14, 16])
    }
}
