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

    func testNotifications() {
        let a = pr("a"), b = pr("b", reviewers: [rv(.approved)]), c = pr("c", reviewers: [rv(.changesRequested)])
        let old = PRSnapshot(reviewRequestIDs: ["a"], mineApproval: ["b": "waiting", "c": "waiting", "d": "approved"], providers: ["github"])
        let new = PRLogic.snapshot(reviewRequests: [a, pr("n")], mine: [b, c, pr("d", reviewers: [rv(.approved)])])
        let notices = PRLogic.notifications(old: old, new: new, reviewRequests: [a, pr("n")], mine: [b, c, pr("d", reviewers: [rv(.approved)])])
        XCTAssertEqual(notices, [.newReviewRequest(pr("n")), .approved(b), .changesRequested(c)])
    }

    func testNotificationsFirstRunAndUnknownMine() {
        let b = pr("b", reviewers: [rv(.approved)])
        let new = PRLogic.snapshot(reviewRequests: [pr("a")], mine: [b])
        XCTAssertEqual(PRLogic.notifications(old: nil, new: new, reviewRequests: [pr("a")], mine: [b]), [])
        // 직전에 없던 내 PR 이 이미 승인 상태로 보여도 알리지 않는다
        XCTAssertEqual(PRLogic.notifications(old: PRSnapshot(providers: ["github"]), new: new, reviewRequests: [], mine: [b]), [])
    }

    func testNotifyOnlyRequestedAndSeedNewProvider() {
        var unasked = pr("u"); unasked.reviewRequested = false
        var bb = pr("bitbucket:w/s#1"); bb.provider = .bitbucket
        let all = [pr("n"), unasked, bb]
        let new = PRLogic.snapshot(reviewRequests: all, mine: [])
        XCTAssertEqual(new.reviewRequestIDs, ["n", "bitbucket:w/s#1"], "요청되지 않은 PR 은 기준에서도 제외")
        // bitbucket 은 처음 켬(old.providers 에 없음) → 알림 없이 기준만
        let n = PRLogic.notifications(old: PRSnapshot(providers: ["github"]), new: new, reviewRequests: all, mine: [])
        XCTAssertEqual(n, [.newReviewRequest(pr("n"))])
    }

    func testMergedSnapshotKeepsFailedProviders() {
        let old = PRSnapshot(reviewRequestIDs: ["github:o/r#1", "bitbucket:w/s#2"],
                             mineApproval: ["github:o/r#3": "approved", "bitbucket:w/s#4": "waiting"], providers: ["github", "bitbucket"])
        // github 만 성공했고 새 목록은 비어 있다 → bitbucket 항목은 그대로, github 항목은 비워짐
        let m = PRLogic.mergedSnapshot(old: old, fresh: PRSnapshot(), succeeded: [.github])
        XCTAssertEqual(m.reviewRequestIDs, ["bitbucket:w/s#2"])
        XCTAssertEqual(m.mineApproval, ["bitbucket:w/s#4": "waiting"])
        XCTAssertEqual(m.providers, ["github", "bitbucket"])
        // 실패한 제공자의 fresh 항목(있더라도)은 무시
        let f = PRSnapshot(reviewRequestIDs: ["bitbucket:w/s#9"])
        XCTAssertFalse(PRLogic.mergedSnapshot(old: old, fresh: f, succeeded: [.github]).reviewRequestIDs.contains("bitbucket:w/s#9"))
        XCTAssertEqual(PRLogic.mergedSnapshot(old: nil, fresh: PRSnapshot(reviewRequestIDs: ["github:o/r#1"]), succeeded: [.github]).providers, ["github"])
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
