import XCTest
@testable import TaskWidgetCore

final class PRLogicTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func day(_ n: Double) -> Date { now.addingTimeInterval(-n * 86400) }

    func pr(_ id: String, created: Double = 1, updated: Double = 1, reviewers: [PRReviewer] = [],
            myReview: Date? = nil, lastCommit: Date? = nil) -> PullRequest {
        PullRequest(id: id, provider: .github, repo: "r", number: 1, title: "t", url: "u", author: "a",
                    createdAt: day(created), updatedAt: day(updated), lastCommitAt: lastCommit,
                    reviewers: reviewers, myReviewAt: myReview)
    }
    func rv(_ s: ReviewState) -> PRReviewer { PRReviewer(name: "x", state: s) }

    func testApproval() {
        XCTAssertEqual(PRLogic.approval(pr("a")), .noReviewers)
        XCTAssertEqual(PRLogic.approval(pr("a", reviewers: [rv(.approved), rv(.approved)])), .approved(2, 2))
        XCTAssertEqual(PRLogic.approval(pr("a", reviewers: [rv(.approved), rv(.pending)])), .waiting(1, 2))
        XCTAssertEqual(PRLogic.approval(pr("a", reviewers: [rv(.approved), rv(.changesRequested)])), .changesRequested)
        XCTAssertEqual(PRLogic.approval(pr("a", reviewers: [rv(.commented)])), .waiting(0, 1))
    }

    func testNewCommitsSinceMyReview() {
        XCTAssertFalse(PRLogic.hasNewCommitsSinceMyReview(pr("a")))
        XCTAssertFalse(PRLogic.hasNewCommitsSinceMyReview(pr("a", lastCommit: day(0))))
        XCTAssertTrue(PRLogic.hasNewCommitsSinceMyReview(pr("a", myReview: day(2), lastCommit: day(1))))
        XCTAssertFalse(PRLogic.hasNewCommitsSinceMyReview(pr("a", myReview: day(1), lastCommit: day(2))))
        XCTAssertFalse(PRLogic.hasNewCommitsSinceMyReview(pr("a", myReview: day(1), lastCommit: nil)))
    }

    func testSortReviewRequests() {
        let list = [pr("reviewedOld", created: 9, myReview: day(1)), pr("new", created: 1), pr("old", created: 5)]
        XCTAssertEqual(PRLogic.sortReviewRequests(list).map(\.id), ["old", "new", "reviewedOld"])
    }

    func testSortMine() {
        let list = [pr("wait", updated: 1, reviewers: [rv(.pending)]),
                    pr("ok", updated: 3, reviewers: [rv(.approved)]),
                    pr("chg", updated: 5, reviewers: [rv(.changesRequested)]),
                    pr("none", updated: 0)]
        XCTAssertEqual(PRLogic.sortMine(list).map(\.id), ["chg", "ok", "none", "wait"])
    }

    func testStale() {
        XCTAssertTrue(PRLogic.isStale(pr("a", created: 2), now: now, days: 2))
        XCTAssertFalse(PRLogic.isStale(pr("a", created: 1.9), now: now, days: 2))
        XCTAssertEqual(PRLogic.waitDays(pr("a", created: 3.5), now: now), 3)
    }

    func rv(_ name: String, _ s: ReviewState) -> PRReviewer { PRReviewer(name: name, state: s) }
    func act(_ id: String, _ who: String) -> PRActivity { PRActivity(id: id, author: who) }
    func mineWith(_ id: String = "github:o/r#1", reviewers: [PRReviewer] = [], activity: [PRActivity] = []) -> PullRequest {
        var p = pr(id, reviewers: reviewers); p.provider = .github; p.repo = "repo"; p.title = "Fix"; p.recentActivity = activity
        return p
    }
    /// old 상태를 만든다: 직전 목록으로 만든 스냅샷 (github 은 이미 본 제공자).
    func base(_ prs: [PullRequest]) -> PRSnapshot {
        var s = PRLogic.snapshot(reviewRequests: [], mine: prs); s.providers = ["github"]; return s
    }
    func notices(old: PRSnapshot?, _ prs: [PullRequest]) -> [PRNotice] {
        let new = PRLogic.snapshot(reviewRequests: [], mine: prs, old: old)
        return PRLogic.notifications(old: old, new: new, reviewRequests: [], mine: prs)
    }

    func testNewReviewRequestNotice() {
        let a = pr("github:o/r#1"), n = pr("github:o/r#2")
        let old = PRSnapshot(reviewRequestIDs: [a.id], providers: ["github"])
        let new = PRLogic.snapshot(reviewRequests: [a, n], mine: [])
        XCTAssertEqual(PRLogic.notifications(old: old, new: new, reviewRequests: [a, n], mine: []), [.newReviewRequest(n)])
        XCTAssertEqual(PRLogic.notifications(old: nil, new: new, reviewRequests: [a, n], mine: []), [], "첫 실행")
    }

    func testEachNewApproverNotifiesWithCount() {
        let before = mineWith(reviewers: [rv("bob", .approved), rv("cat", .pending), rv("dan", .pending)])
        let old = base([before])
        let after = mineWith(reviewers: [rv("bob", .approved), rv("cat", .approved), rv("dan", .pending)])
        let n = notices(old: old, [after])
        XCTAssertEqual(n, [.approved(after, by: "cat", count: 2, total: 3, complete: false)])
        XCTAssertEqual(n[0].title, "PR 승인 (2/3)")
        XCTAssertEqual(n[0].body, "cat 님이 승인 · repo · Fix")
    }

    func testFullApprovalWording() {
        let old = base([mineWith(reviewers: [rv("bob", .approved), rv("cat", .pending)])])
        let after = mineWith(reviewers: [rv("bob", .approved), rv("cat", .approved)])
        let n = notices(old: old, [after])
        XCTAssertEqual(n, [.approved(after, by: "cat", count: 2, total: 2, complete: true)])
        XCTAssertEqual(n[0].title, "PR 승인 완료 · 머지할 수 있어요")
    }

    func testChangesRequester() {
        let old = base([mineWith(reviewers: [rv("bob", .pending)])])
        let after = mineWith(reviewers: [rv("bob", .changesRequested)])
        let n = notices(old: old, [after])
        XCTAssertEqual(n, [.changesRequested(after, by: "bob")])
        XCTAssertEqual(n[0].body, "bob 님이 변경 요청 · repo · Fix")
        XCTAssertEqual(notices(old: base([after]), [after]), [], "이미 알린 변경 요청")
    }

    func testOthersCommentNotifiesAndOwnDoesNot() {
        let old = base([mineWith(activity: [act("c1", "bob")])])
        let after = mineWith(activity: [act("c1", "bob"), act("c2", "cat")])
        let n = notices(old: old, [after])
        XCTAssertEqual(n, [.comments(after, authors: ["cat"], count: 1)])
        XCTAssertEqual(n[0].body, "cat 님이 댓글 · repo · Fix")
        // 내 댓글은 가져올 때 이미 빠진다 (recentActivity 에 없음) → 알림 없음
        XCTAssertEqual(notices(old: old, [mineWith(activity: [act("c1", "bob")])]), [])
    }

    func testCommentsGroupedPerPR() {
        let old = base([mineWith()])
        let after = mineWith(activity: [act("c1", "bob"), act("c2", "cat"), act("c3", "bob")])
        let n = notices(old: old, [after])
        XCTAssertEqual(n, [.comments(after, authors: ["bob", "cat"], count: 3)])
        XCTAssertEqual(n[0].body, "bob 외 1명 · 댓글 3개 · repo · Fix")
        XCTAssertEqual(PRNotice.comments(after, authors: ["bob"], count: 3).body, "bob 님이 댓글 3개 · repo · Fix")
    }

    func testSeedingIsSilent() {
        let after = mineWith(reviewers: [rv("bob", .approved)], activity: [act("c1", "bob")])
        XCTAssertEqual(notices(old: nil, [after]), [])
        // 처음 켠 제공자 (providers 에 없음)
        var old = base([]); old.providers = ["bitbucket"]
        XCTAssertEqual(notices(old: old, [after]), [])
        // 직전에 없던 PR: 댓글은 이미 있던 것, 승인은 빈 상태와 비교
        let n = notices(old: base([]), [after])
        XCTAssertEqual(n, [.approved(after, by: "bob", count: 1, total: 1, complete: true)])
    }

    func testApprovalAndCommentsBothNotifyInOneRefresh() {
        let old = base([mineWith(reviewers: [rv("bob", .pending)])])
        let after = mineWith(reviewers: [rv("bob", .approved)], activity: [act("c1", "cat"), act("c2", "dan")])
        // 댓글은 PR 당 하나로 묶이고, 승인과는 따로
        XCTAssertEqual(notices(old: old, [after]), [.approved(after, by: "bob", count: 1, total: 1, complete: true),
                                                    .comments(after, authors: ["cat", "dan"], count: 2)])
    }

    func testMergedSnapshotKeepsFailedProviders() {
        let old = PRSnapshot(reviewRequestIDs: ["github:o/r#1", "bitbucket:w/s#2"],
                             mine: ["github:o/r#3": PRMineState(approvers: ["a"]), "bitbucket:w/s#4": PRMineState(approvers: ["b"])],
                             providers: ["github", "bitbucket"])
        // github 만 성공했고 새 목록은 비어 있다 → bitbucket 항목은 그대로, github 항목은 비워짐
        let m = PRLogic.mergedSnapshot(old: old, fresh: PRSnapshot(), succeeded: [.github])
        XCTAssertEqual(m.reviewRequestIDs, ["bitbucket:w/s#2"])
        XCTAssertEqual(Set(m.mine.keys), ["bitbucket:w/s#4"])
        XCTAssertEqual(m.providers, ["github", "bitbucket"])
        let f = PRSnapshot(reviewRequestIDs: ["bitbucket:w/s#9"])
        XCTAssertFalse(PRLogic.mergedSnapshot(old: old, fresh: f, succeeded: [.github]).reviewRequestIDs.contains("bitbucket:w/s#9"))
        XCTAssertEqual(PRLogic.mergedSnapshot(old: nil, fresh: PRSnapshot(reviewRequestIDs: ["github:o/r#1"]), succeeded: [.github]).providers, ["github"])
    }

    func testNotifyOnlyRequested() {
        var unasked = pr("u"); unasked.reviewRequested = false
        var bb = pr("bitbucket:w/s#1"); bb.provider = .bitbucket
        let all = [pr("n"), unasked, bb]
        let new = PRLogic.snapshot(reviewRequests: all, mine: [])
        XCTAssertEqual(new.reviewRequestIDs, ["n", "bitbucket:w/s#1"], "요청되지 않은 PR 은 기준에서도 제외")
        // bitbucket 은 처음 켬(old.providers 에 없음) → 알림 없이 기준만
        let n = PRLogic.notifications(old: PRSnapshot(providers: ["github"]), new: new, reviewRequests: all, mine: [])
        XCTAssertEqual(n, [.newReviewRequest(pr("n"))])
    }

    func testTrimSeen() {
        let seen: Set<String> = ["github:o/r#1", "github:o/r#2", "bitbucket:w/s#3"]
        XCTAssertEqual(PRLogic.trimSeen(seen, present: ["github:o/r#1"], succeeded: [.github]), ["github:o/r#1", "bitbucket:w/s#3"])
        XCTAssertEqual(PRLogic.trimSeen(seen, present: [], succeeded: []), seen)
    }

    func testRepoKeyAndProvider() {
        XCTAssertEqual(PRLogic.repoKey("github:o/r#12"), "github:o/r")
        XCTAssertEqual(PRLogic.provider(of: "bitbucket:w/s#1"), .bitbucket)
    }

    func testClassifyRateLimit() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(PRError.classify(code: 403, remaining: "0", retryAfter: nil, reset: "1060", provider: "GitHub", now: now),
                       .rateLimited(60, "GitHub 요청 한도 초과 — 잠시 후 다시 시도"))
        XCTAssertEqual(PRError.classify(code: 429, remaining: nil, retryAfter: "30", reset: nil, provider: "Bitbucket", now: now),
                       .rateLimited(30, "Bitbucket 요청 한도 초과 — 잠시 후 다시 시도"))
        XCTAssertEqual(PRError.classify(code: 403, remaining: "10", retryAfter: nil, reset: nil, provider: "GitHub"), .unauthorized)
        XCTAssertEqual(PRError.classify(code: 500, remaining: nil, retryAfter: nil, reset: nil, provider: "GitHub"), .http(500))
    }

    func testBadgeCount() {
        let rr = [pr("a"), pr("b")]
        let mine = [pr("c", reviewers: [rv(.changesRequested)]), pr("d", reviewers: [rv(.approved)])]
        XCTAssertEqual(PRLogic.badgeCount(reviewRequests: rr, mine: mine, seen: []), 3)
        XCTAssertEqual(PRLogic.badgeCount(reviewRequests: rr, mine: mine, seen: ["a", "b"]), 1)
        var unasked = pr("x"); unasked.reviewRequested = false
        XCTAssertEqual(PRLogic.badgeCount(reviewRequests: rr + [unasked], mine: mine, seen: []), 3)
    }

    func testParseDateAndRelative() {
        let a = PRLogic.parseDate("2026-10-14T01:02:03Z")!
        XCTAssertEqual(PRLogic.parseDate("2026-10-14T01:02:03.123456+00:00"), a)
        XCTAssertNil(PRLogic.parseDate("nope"))
        XCTAssertEqual(PRLogic.relative(now.addingTimeInterval(-7200), now: now), "2시간 전")
        XCTAssertEqual(PRLogic.relative(now.addingTimeInterval(-86400 * 3), now: now), "3일 전")
        XCTAssertEqual(PRLogic.todoTitle(pr("a"), isReviewRequest: true), "[PR 리뷰] t")
    }
}

/// 승인(쓰기) 관련. 요청을 만들기만 하고 네트워크는 타지 않는다.
final class PRApproveTests: XCTestCase {
    func testIdParsers() {
        let g = PRLogic.githubParts("github:midas/task-widget#12")
        XCTAssertEqual([g?.owner, g?.repo], ["midas", "task-widget"]); XCTAssertEqual(g?.number, 12)
        let b = PRLogic.bitbucketParts("bitbucket:ws/mrs-cms#34")
        XCTAssertEqual([b?.workspace, b?.slug], ["ws", "mrs-cms"]); XCTAssertEqual(b?.number, 34)
        XCTAssertNil(PRLogic.githubParts("bitbucket:ws/s#1"))
        XCTAssertNil(PRLogic.githubParts("github:o/r"))
        XCTAssertNil(PRLogic.githubParts("github:o/r/x#1"))
        XCTAssertNil(PRLogic.bitbucketParts("bitbucket:ws#1"))
    }

    func testGitHubApproveRequest() {
        let r = GitHubClient.approveRequest(owner: "o", repo: "r", number: 7, token: "T")
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.url?.absoluteString, "https://api.github.com/repos/o/r/pulls/7/reviews")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer T")
        XCTAssertEqual(String(decoding: r.httpBody ?? Data(), as: UTF8.self), #"{"event":"APPROVE"}"#)
    }

    func testBitbucketApproveRequests() {
        let c = BitbucketClient(email: "a@b.c", token: "T")
        let a = c.approveRequest(workspace: "ws", slug: "s", id: 5, undo: false)
        XCTAssertEqual(a.httpMethod, "POST")
        XCTAssertEqual(a.url?.absoluteString, "https://api.bitbucket.org/2.0/repositories/ws/s/pullrequests/5/approve")
        XCTAssertEqual(c.approveRequest(workspace: "ws", slug: "s", id: 5, undo: true).httpMethod, "DELETE")
        XCTAssertEqual(a.value(forHTTPHeaderField: "Authorization"), "Basic " + Data("a@b.c:T".utf8).base64EncodedString())
    }

    func testErrorMapping() {
        XCTAssertEqual(PRError.bitbucketWriteError(code: 403), .noWritePermission)
        XCTAssertEqual(PRError.bitbucketWriteError(code: 401), .noWritePermission)
        XCTAssertEqual(PRError.bitbucketWriteError(code: 500), .http(500))
        if case .rateLimited = PRError.bitbucketWriteError(code: 429, retryAfter: "20") {} else { XCTFail("429") }
        XCTAssertEqual(PRError.noWritePermission.userMessage, "Bitbucket 토큰에 PR 쓰기 권한(write:pullrequest:bitbucket)이 필요해요")
        XCTAssertEqual(PRError.githubApproveError(code: 422, remaining: nil, retryAfter: nil, reset: nil),
                       .message("승인할 수 없는 PR 이에요 (이미 닫혔거나 내가 올린 PR)"))
        XCTAssertEqual(PRError.githubApproveError(code: 403, remaining: "5", retryAfter: nil, reset: nil),
                       .message("이 저장소에서 승인할 권한이 없어요"))
        if case .rateLimited = PRError.githubApproveError(code: 403, remaining: "0", retryAfter: nil, reset: nil) {} else { XCTFail("rate") }
    }

    func testOptimisticMarking() {
        let t = Date(timeIntervalSince1970: 100)
        var p = PullRequest(id: "github:o/r#1", provider: .github, repo: "r", number: 1, title: "t", url: "u", author: "a",
                            createdAt: t, updatedAt: t, reviewers: [PRReviewer(name: "bob", state: .approved)])
        XCTAssertFalse(PRLogic.approvedBy(p, me: "me"))
        p = PRLogic.markApproved(p, by: "me", at: t)
        XCTAssertTrue(PRLogic.approvedBy(p, me: "me"))
        XCTAssertEqual(p.myReviewAt, t)
        XCTAssertEqual(p.reviewers.count, 2)
        p = PRLogic.markApproved(p, by: "me", at: t)   // 두 번 눌러도 중복되지 않는다
        XCTAssertEqual(p.reviewers.count, 2)
        p = PRLogic.markUnapproved(p, by: "me")
        XCTAssertFalse(PRLogic.approvedBy(p, me: "me"))
        XCTAssertNil(p.myReviewAt)
        XCTAssertFalse(PRLogic.approvedBy(p, me: nil))
    }
}
