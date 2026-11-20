import XCTest
@testable import TaskWidgetCore

final class E2EModelsTests: XCTestCase {
    func testCombineVerdicts() {
        XCTAssertNil(E2EVerdict.combine([]))
        XCTAssertEqual(E2EVerdict.combine([.pass, .skipped, .fail, .blocked]), .fail)
        XCTAssertEqual(E2EVerdict.combine([.pass, .blocked, .skipped]), .blocked)
        XCTAssertEqual(E2EVerdict.combine([.skipped, .skipped]), .skipped)
        XCTAssertEqual(E2EVerdict.combine([.pass, .skipped]), .pass)
        XCTAssertEqual(E2EVerdict.combine([.pass]), .pass)
    }

    func testEnvironments() {
        XCTAssertEqual(E2EEnv.allCases.map(\.rawValue), ["DV", "ST", "ST2", "PR"])
        XCTAssertEqual(E2EEnv.allCases.filter(\.forcesReadOnly), [.pr])
        XCTAssertEqual(E2EEnv(rawValue: "ST2"), .st2)
    }

    func testLenientVerdict() {
        XCTAssertEqual(E2EVerdict(lenient: " pass "), .pass)
        XCTAssertEqual(E2EVerdict(lenient: "Blocked"), .blocked)
        XCTAssertNil(E2EVerdict(lenient: "maybe"))
        XCTAssertNil(E2EVerdict(lenient: nil))
    }

    func testDecodeSampleResultLeniently() throws {
        let url = Bundle.module.url(forResource: "e2e-result", withExtension: "json", subdirectory: "Fixtures")!
        let r = try E2EResult.decode(Data(contentsOf: url))
        XCTAssertEqual(r.status, "done")
        XCTAssertEqual(r.issues.count, 3)

        let a = r.issues[0]
        XCTAssertEqual(a.key, "NMRS-22374")
        XCTAssertEqual(a.verdict, .pass)
        XCTAssertEqual(a.assumptions, ["초기화는 날짜 필터도 비운다고 봤어요"])
        XCTAssertEqual(a.scenarios[0].steps.count, 3)
        XCTAssertEqual(a.scenarios[0].screenshots, ["NMRS-22374-1.png", "NMRS-22374-2.png"])
        // steps 가 문자열 하나, screenshot 단수, 소문자 판정
        XCTAssertEqual(a.scenarios[1].steps, ["초기화 버튼 확인"])
        XCTAssertEqual(a.scenarios[1].screenshots, ["NMRS-22374-3.png"])
        XCTAssertEqual(a.scenarios[1].verdict, .pass)

        // Aside 는 PASS 라고 적었지만 시나리오에 FAIL 이 있으면 FAIL. 키는 대문자로.
        let b = r.issues[1]
        XCTAssertEqual(b.key, "NMRS-22380")
        XCTAssertEqual(b.reportedVerdict, .pass)
        XCTAssertEqual(b.verdict, .fail)
        XCTAssertEqual(b.scenarios[1].steps, [])
        XCTAssertEqual(b.scenarios[1].screenshots, [])
        XCTAssertEqual(b.notes, "콘솔 에러 없음\n네트워크 실패 없음")

        // 시나리오도 판정도 없으면 nil, 숫자 세기에서 빠진다
        XCTAssertNil(r.issues[2].verdict)
        XCTAssertEqual(r.counts, [.pass: 1, .fail: 1])
    }

    func testResultWithoutIssuesIsInvalid() {
        XCTAssertThrowsError(try E2EResult.decode(Data(#"{"status":"done","summary":"x"}"#.utf8)))
        XCTAssertThrowsError(try E2EResult.decode(Data("not json".utf8)))
        XCTAssertEqual(try E2EResult.decode(Data(#"{"issues":[]}"#.utf8)).issues, [])
    }

    func testJobRoundTripHasNoPasswordAndForcesReadOnlyOnPR() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let job = E2EJob(id: "20261109141500-a1b2", env: .pr, baseUrl: "https://pr.example.com", username: "qa",
                         issues: [E2EIssueRef(key: "ABC-1", url: "https://j/browse/ABC-1", title: "t")], createdAt: now)
        XCTAssertTrue(job.readOnly)
        var withModel = job
        withModel.model = "claude-sonnet-5"
        XCTAssertEqual(try JSONDecoder().decode(E2EJob.self, from: E2EJobStore.encoder.encode(withModel)).model, "claude-sonnet-5")
        let data = try E2EJobStore.encoder.encode(job)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("password"))
        let back = try JSONDecoder().decode(E2EJob.self, from: data)
        XCTAssertEqual(back, job)
    }

    func testJobDecodesWhatAsideRewrote() throws {
        // Aside 가 다시 쓴 모양: 소수 초 날짜, 모르는 키, 다른 상태 이름, PR 인데 readOnly false
        let raw = #"""
        {"id":"20261109141500-a1b2","env":"pr","baseUrl":"https://x","username":"qa","readOnly":false,
         "issues":[{"key":"ABC-1","url":"u","title":"t"}],"status":"completed",
         "createdAt":"2026-11-09T05:15:00.123Z","extra":{"a":1}}
        """#
        let j = try JSONDecoder().decode(E2EJob.self, from: Data(raw.utf8))
        XCTAssertEqual(j.env, .pr)
        XCTAssertTrue(j.readOnly)
        XCTAssertEqual(j.status, .done)
        XCTAssertEqual(j.createdAt.timeIntervalSince1970, 1_794_201_300.123, accuracy: 0.01)
        XCTAssertEqual(j.notes, "")
        XCTAssertNil(j.error)

        let noDate = try JSONDecoder().decode(E2EJob.self, from: Data(#"{"id":"20261109141500-zz99","status":"weird"}"#.utf8))
        XCTAssertEqual(noDate.status, .failed)
        XCTAssertEqual(noDate.createdAt, E2EJobID.date("20261109141500-zz99"))
    }

    func testJobID() {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 9; c.hour = 14; c.minute = 15; c.second = 0
        let d = Calendar.current.date(from: c)!
        XCTAssertEqual(E2EJobID.make(now: d, suffix: "a1b2"), "20261109141500-a1b2")
        let random = E2EJobID.make(now: d)
        XCTAssertTrue(random.hasPrefix("20261109141500-"))
        XCTAssertEqual(random.count, 19)
        XCTAssertTrue(E2EJobID.isValid(random))
        XCTAssertFalse(E2EJobID.isValid("../etc"))
        XCTAssertFalse(E2EJobID.isValid("a/b"))
        XCTAssertFalse(E2EJobID.isValid(""))
        XCTAssertEqual(E2EJobID.date("20261109141500-a1b2"), d)
    }

    func testIssueKeyParsing() {
        let raw = """
        NMRS-22374, abc-12
        https://x.atlassian.net/browse/DEF-3?focusedCommentId=1
        https://x.atlassian.net/jira/software/projects/G/boards/1?selectedIssue=GHI-4
        NMRS-22374 ; not-a-key https://x.atlassian.net/wiki/spaces/A
        X-1 A1-2
        """
        XCTAssertEqual(E2EIssueKeys.parse(raw), ["NMRS-22374", "ABC-12", "DEF-3", "GHI-4", "A1-2"])
        XCTAssertEqual(E2EIssueKeys.parse(""), [])
    }

    func testRunPolicyTimeout() {
        XCTAssertEqual(E2ERunPolicy.timeout(issueCount: 1, minutesPerIssue: 10, maxMinutes: 30), 600)
        XCTAssertEqual(E2ERunPolicy.timeout(issueCount: 2, minutesPerIssue: 10, maxMinutes: 30), 1200)
        XCTAssertEqual(E2ERunPolicy.timeout(issueCount: 5, minutesPerIssue: 10, maxMinutes: 30), 1800)
        // 최대값이 이슈당 값보다 작으면 이슈당 값을 쓴다
        XCTAssertEqual(E2ERunPolicy.timeout(issueCount: 3, minutesPerIssue: 10, maxMinutes: 5), 600)
        XCTAssertEqual(E2ERunPolicy.timeout(issueCount: 0, minutesPerIssue: 0, maxMinutes: 0), 60)
    }

    func testLatestVerdictsUseNewestJob() {
        func job(_ id: String, _ t: TimeInterval) -> E2EJob {
            E2EJob(id: id, env: .st, baseUrl: "", username: "", issues: [], createdAt: Date(timeIntervalSince1970: t))
        }
        func res(_ key: String, _ v: E2EVerdict) -> E2EResult {
            E2EResult(issues: [E2EIssueResult(key: key, scenarios: [E2EScenario(name: "s", verdict: v)])])
        }
        let m = E2ELatestVerdicts.build([
            (job("new", 200), res("A-1", .pass)),
            (job("old", 100), res("A-1", .fail)),
            (job("mid", 150), E2EResult(issues: [E2EIssueResult(key: "B-2", reportedVerdict: .blocked), E2EIssueResult(key: "A-1")])),
        ])
        XCTAssertEqual(m["A-1"]?.verdict, .pass)
        XCTAssertEqual(m["A-1"]?.jobId, "new")
        XCTAssertEqual(m["B-2"]?.verdict, .blocked)
        XCTAssertEqual(m.count, 2)
    }

    func testPRIsHiddenUnlessAllowed() {
        XCTAssertEqual(E2EEnv.selectable(allowPR: false), [.dv, .st, .st2])
        XCTAssertEqual(E2EEnv.selectable(allowPR: true), [.dv, .st, .st2, .pr])
    }

    func testIssueWebURLOnlyHTTP() {
        func url(_ s: String) -> URL? { E2EIssueRef(key: "A-1", url: s, title: "").webURL }
        XCTAssertEqual(url("https://x.atlassian.net/browse/A-1")?.absoluteString, "https://x.atlassian.net/browse/A-1")
        XCTAssertNotNil(url("HTTP://jira.local/browse/A-1"))
        XCTAssertNil(url("file:///Applications/Calculator.app"))
        XCTAssertNil(url("/tmp/run.sh"))
        XCTAssertNil(url("javascript:alert(1)"))
        XCTAssertNil(url("https://"))
        XCTAssertNil(url(""))
        XCTAssertEqual(E2EWebURL.parse("https://st.example.com")?.host, "st.example.com")
        XCTAssertNil(E2EWebURL.parse("st.example.com"))
    }

    func testLoginBlockedReason() throws {
        func blocked(_ value: String) throws -> E2ELoginBlock? {
            try E2EResult.decode(Data(#"{"issues":[],"loginBlocked":\#(value)}"#.utf8)).loginBlocked
        }
        XCTAssertEqual(try blocked(#""VAULT_LOCKED""#), .vaultLocked)
        XCTAssertEqual(try blocked(#"" no_saved_login ""#), .noSavedLogin)
        XCTAssertEqual(try blocked(#""2FA""#), .other)
        XCTAssertEqual(try blocked(#""vault_not_setup""#), .vaultNotSetUp)
        XCTAssertEqual(try blocked(#""WRONG_ACCOUNT""#), .wrongAccount)
        XCTAssertEqual(try blocked(#""LOGIN_REJECTED""#), .rejected)
        XCTAssertEqual(try blocked(#""TWO_FACTOR""#), .twoFactor)
        XCTAssertEqual(try blocked("true"), .other)
        XCTAssertNil(try blocked(#""""#))
        XCTAssertNil(try blocked("null"))
        XCTAssertNil(try blocked("false"))
        XCTAssertNil(try E2EResult.decode(Data(#"{"issues":[]}"#.utf8)).loginBlocked)

        let steps = E2ELoginBlock.noSavedLogin.steps(account: "테스트 계정(qa)")
        XCTAssertTrue(steps.contains { $0.contains("테스트 계정(qa)") })
        for b in E2ELoginBlock.allCases {
            XCTAssertTrue(b.steps(account: "a").last?.hasSuffix("다시 실행해요") == true, b.rawValue)
            XCTAssertFalse(b.reason.isEmpty)
        }
        XCTAssertEqual(Set(E2ELoginBlock.allCases.map(\.reason)).count, E2ELoginBlock.allCases.count)
    }
}
