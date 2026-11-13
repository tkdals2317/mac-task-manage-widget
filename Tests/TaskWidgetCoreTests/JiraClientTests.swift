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

final class JiraTransitionTests: XCTestCase {
    final class Stub: URLProtocol {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var body = Data()
        nonisolated(unsafe) static var last: URLRequest?
        nonisolated(unsafe) static var lastBody: Data?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
        override func startLoading() {
            Self.last = request
            if let s = request.httpBodyStream {
                s.open(); defer { s.close() }
                var d = Data(); var buf = [UInt8](repeating: 0, count: 1024)
                while s.hasBytesAvailable { let n = s.read(&buf, maxLength: 1024); if n <= 0 { break }; d.append(buf, count: n) }
                Self.lastBody = d
            } else { Self.lastBody = request.httpBody }
            let r = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    func client(status: Int, body: String = "") -> JiraClient {
        Stub.status = status; Stub.body = Data(body.utf8); Stub.last = nil; Stub.lastBody = nil
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [Stub.self]
        return JiraClient(baseURL: URL(string: "https://x.example.com")!, email: "a@b.c", token: "t", session: URLSession(configuration: cfg))
    }

    func testFetchTransitionsDecodes() async throws {
        let c = client(status: 200, body: #"{"transitions":[{"id":"21","name":"Start","to":{"name":"진행 중","statusCategory":{"key":"indeterminate"}}},{"id":"31","name":"Done","to":{"name":"완료","statusCategory":{"key":"done"}}}]}"#)
        let t = try await c.fetchTransitions(issueKey: "NMRS-1")
        XCTAssertEqual(t, [JiraTransition(id: "21", name: "Start", toName: "진행 중", toCategory: "indeterminate"),
                           JiraTransition(id: "31", name: "Done", toName: "완료", toCategory: "done")])
        XCTAssertEqual(Stub.last?.httpMethod, "GET")
        XCTAssertEqual(Stub.last?.url?.path, "/rest/api/3/issue/NMRS-1/transitions")
    }

    func testTransitionPostsBody() async throws {
        let c = client(status: 204)
        try await c.transition(issueKey: "NMRS-1", transitionId: "21")
        XCTAssertEqual(Stub.last?.httpMethod, "POST")
        XCTAssertEqual(Stub.last?.url?.path, "/rest/api/3/issue/NMRS-1/transitions")
        let obj = try JSONSerialization.jsonObject(with: Stub.lastBody ?? Data()) as? [String: [String: String]]
        XCTAssertEqual(obj, ["transition": ["id": "21"]])
    }

    func testTransitionErrorMapping() async {
        let expect: [(Int, String)] = [(400, "이 상태로 바꿀 수 없음"), (401, "토큰 만료"), (403, "권한 없음"), (404, "이슈 없음"), (500, "HTTP 500")]
        for (code, text) in expect {
            let c = client(status: code)
            do { try await c.transition(issueKey: "NMRS-1", transitionId: "1"); XCTFail("\(code)") }
            catch let e as JiraError { XCTAssertTrue(e.userMessage.hasPrefix(text), "\(code): \(e.userMessage)") }
            catch { XCTFail("\(error)") }
        }
        let c = client(status: 403)
        do { _ = try await c.fetchTransitions(issueKey: "X-1"); XCTFail() }
        catch let e as JiraError { XCTAssertEqual(e.userMessage, "권한 없음") }
        catch { XCTFail("\(error)") }
    }

    func testAddCommentPostsDocument() async throws {
        let c = client(status: 201, body: #"{"id":"10042","body":{}}"#)
        let doc: [String: Any] = ["type": "doc", "version": 1, "content": [["type": "paragraph", "content": [["type": "text", "text": "hi"]]]]]
        let id = try await c.addComment(issueKey: "NMRS-1", document: doc)
        XCTAssertEqual(id, "10042")
        XCTAssertEqual(Stub.last?.httpMethod, "POST")
        XCTAssertEqual(Stub.last?.url?.path, "/rest/api/3/issue/NMRS-1/comment")
        XCTAssertEqual(Stub.last?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: Stub.lastBody ?? Data()) as? [String: Any])
        XCTAssertEqual((sent["body"] as? [String: Any])?["type"] as? String, "doc")
    }

    func testAddAttachmentSendsMultipartWithNoCheckHeader() async throws {
        let c = client(status: 200, body: "[]")
        try await c.addAttachment(issueKey: "NMRS-1", fileName: "shot.png", mime: "image/png", data: Data([9, 8, 7]))
        XCTAssertEqual(Stub.last?.httpMethod, "POST")
        XCTAssertEqual(Stub.last?.url?.path, "/rest/api/3/issue/NMRS-1/attachments")
        XCTAssertEqual(Stub.last?.value(forHTTPHeaderField: "X-Atlassian-Token"), "no-check")
        let type = try XCTUnwrap(Stub.last?.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(type.hasPrefix("multipart/form-data; boundary=atm-"))
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        XCTAssertEqual(Stub.lastBody, JiraClient.multipart(boundary: boundary, fileName: "shot.png", mime: "image/png", data: Data([9, 8, 7])))
    }

    func testCommentAndAttachmentErrors() async {
        let expect: [(Int, String)] = [(400, "Jira 가 댓글 요청을 받아 주지 않았어요 (본문 오류)"), (401, "토큰 만료"),
                                       (403, "이 이슈에 댓글 권한이 없어요"), (404, "이슈를 찾지 못했어요"), (500, "HTTP 500")]
        for (code, text) in expect {
            let c = client(status: code, body: #"{"errorMessages":["본문 오류"]}"#)
            do { _ = try await c.addComment(issueKey: "NMRS-1", document: [:]); XCTFail("\(code)") }
            catch let e as JiraError { XCTAssertTrue(e.userMessage.hasPrefix(text), "\(code): \(e.userMessage)") }
            catch { XCTFail("\(error)") }
        }
        let big = client(status: 413)
        do { try await big.addAttachment(issueKey: "NMRS-1", fileName: "a.png", mime: "image/png", data: Data()); XCTFail() }
        catch let e as JiraError { XCTAssertEqual(e.userMessage, "너무 커서 Jira 가 받지 않았어요 (첨부)") }
        catch { XCTFail("\(error)") }
        // 이슈 키 모양이 아니면 요청을 보내지 않는다
        let c = client(status: 201)
        do { _ = try await c.addComment(issueKey: "../x", document: [:]); XCTFail() }
        catch { XCTAssertNil(Stub.last) }
    }

    func testDecodePageWithExpandedTransitions() throws {
        let json = #"{"issues":[{"key":"NMRS-1","fields":{"summary":"s","status":{"name":"진행 중","statusCategory":{"key":"indeterminate"}},"priority":null,"updated":"2026-10-01T10:00:00.000+0900"},"transitions":[{"id":"31","name":"Done","to":{"name":"완료","statusCategory":{"key":"done"}}}]},{"key":"NMRS-2","fields":{"summary":"t","status":{"name":"할 일","statusCategory":{"key":"new"}},"priority":null,"updated":"2026-10-01T10:00:00.000+0900"}}],"isLast":true}"#
        let issues = try JiraClient.decodePage(Data(json.utf8)).issues
        XCTAssertEqual(issues[0].transitions, [JiraTransition(id: "31", name: "Done", toName: "완료", toCategory: "done")])
        XCTAssertNil(issues[1].transitions, "expand 가 없으면 nil → 팝오버가 따로 받는다")
    }
}
