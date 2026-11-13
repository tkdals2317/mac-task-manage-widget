import XCTest
@testable import TaskWidgetCore

final class E2EJiraCommentTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func job(env: E2EEnv = .st, notes: String = "") -> E2EJob {
        E2EJob(id: "20261113100000-aaaa", env: env, baseUrl: "https://st.example.com", username: "qa01",
               issues: [E2EIssueRef(key: "ABC-1", url: "https://jira.example.com/browse/ABC-1", title: "제목")],
               notes: notes, status: .done, createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    /// 문서 안의 텍스트 노드를 순서대로 모은다.
    private func texts(_ node: Any) -> [String] {
        guard let n = node as? [String: Any] else { return [] }
        if n["type"] as? String == "text" { return [n["text"] as? String ?? ""] }
        return (n["content"] as? [Any] ?? []).flatMap(texts)
    }

    private func types(_ node: Any) -> Set<String> {
        guard let n = node as? [String: Any] else { return [] }
        return (n["content"] as? [Any] ?? []).reduce(into: Set([n["type"] as? String ?? ""])) { $0.formUnion(types($1)) }
    }

    func testDocumentHasVerdictScenariosAndAttachedNames() throws {
        let issue = E2EIssueResult(key: "ABC-1", title: "t", url: "https://evil.example.com", assumptions: ["쿠폰 없음"], scenarios: [
            E2EScenario(name: "주문 취소", steps: ["로그인", "취소 클릭"], expected: "취소됨", actual: "오류\n[~accountid:123] {code}x{code}",
                        verdict: .fail, screenshots: ["ABC-1-1.png", "dir/ABC-1-2.png"]),
            E2EScenario(name: "조회", verdict: .pass),
        ], notes: "콘솔 에러 없음")
        let doc = E2EJiraComment.document(job: job(notes: "주문 #1 사용"), issue: issue, modelName: "기본 모델",
                                          attached: ["ABC-1-1.png": "E2E-ST-20270115-0800-ABC-1-1.png"], timeZone: utc)

        XCTAssertEqual(doc["type"] as? String, "doc")
        XCTAssertEqual(doc["version"] as? Int, 1)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(doc))
        // 기본 노드만 쓴다 (Jira 가 모르는 노드가 있으면 댓글 전체가 거절된다)
        XCTAssertEqual(types(doc), ["doc", "heading", "paragraph", "bulletList", "orderedList", "listItem", "text", "hardBreak"])

        let all = texts(doc)
        XCTAssertEqual(Array(all.prefix(2)), ["E2E 자동 검증 · ", "FAIL"])
        XCTAssertTrue(all.contains("환경 ST · https://st.example.com · 모델 기본 모델 · 2027-01-15 08:00"))
        XCTAssertTrue(all.contains("추가 요청사항: "))
        XCTAssertTrue(all.contains("주문 #1 사용"))
        XCTAssertTrue(all.contains("쿠폰 없음"))
        XCTAssertTrue(all.contains(" 주문 취소"))
        XCTAssertTrue(all.contains("취소 클릭"))
        XCTAssertTrue(all.contains("취소됨"))
        // 멘션·마크업 모양의 글자도 글자 그대로 한 노드에 들어간다
        XCTAssertTrue(all.contains("[~accountid:123] {code}x{code}"))
        // 올린 스크린샷만 이름을 적고, 결과에 적힌 링크는 넣지 않는다
        XCTAssertTrue(all.contains("E2E-ST-20270115-0800-ABC-1-1.png"))
        XCTAssertFalse(all.joined().contains("ABC-1-2"))
        XCTAssertFalse(all.joined().contains("evil.example.com"))
        XCTAssertFalse(all.joined().contains("qa01"))
        XCTAssertTrue(all.contains("콘솔 에러 없음"))
        XCTAssertFalse(all.contains(""), "ADF 는 빈 텍스트 노드를 받지 않는다")
    }

    func testDocumentForReadOnlyAndEmptyResult() {
        let doc = E2EJiraComment.document(job: job(env: .pr), issue: E2EIssueResult(key: "ABC-1", reportedVerdict: .skipped),
                                          modelName: "m", timeZone: utc)
        let all = texts(doc)
        XCTAssertEqual(all[1], "SKIPPED")
        XCTAssertTrue(all[2].hasPrefix("환경 PR (조회만) · "))
        XCTAssertEqual(texts(E2EJiraComment.document(job: job(), issue: E2EIssueResult(key: "ABC-1"), modelName: "m", timeZone: utc))[1], "판정 없음")
    }

    func testLongTextAndManyScenariosAreClipped() {
        let long = String(repeating: "가", count: 5000)
        let many = (1...40).map { E2EScenario(name: "s\($0)", actual: long, verdict: .pass) }
        let all = texts(E2EJiraComment.document(job: job(), issue: E2EIssueResult(key: "ABC-1", scenarios: many), modelName: "m", timeZone: utc))
        XCTAssertTrue(all.allSatisfy { $0.count <= E2EJiraComment.maxText + 1 })
        XCTAssertTrue(all.contains(" s30"))
        XCTAssertFalse(all.contains(" s31"))
        XCTAssertTrue(all.contains("… 시나리오 10개는 줄였어요"))
    }

    func testScreenshotsAndAttachmentName() {
        let issue = E2EIssueResult(key: "ABC-1", scenarios: [
            E2EScenario(name: "a", verdict: .pass, screenshots: ["x/ABC-1-1.png", "ABC-1-2.png"]),
            E2EScenario(name: "b", verdict: .pass, screenshots: ["ABC-1-1.png"]),
        ])
        XCTAssertEqual(E2EJiraComment.screenshots(issue), ["ABC-1-1.png", "ABC-1-2.png"])
        XCTAssertEqual(E2EJiraComment.attachmentName(job(), screenshot: "ABC-1-1.png", timeZone: utc), "E2E-ST-20270115-0800-ABC-1-1.png")
        XCTAssertEqual(E2EJiraComment.attachmentName(job(env: .dv), screenshot: "../a\"b\n.JPG", timeZone: utc), "E2E-DV-20270115-0800-ab.jpg")
        XCTAssertEqual(E2EJiraComment.attachmentName(job(), screenshot: "한글", timeZone: utc), "E2E-ST-20270115-0800-shot")
    }

    func testJobKeepsJiraComments() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-comment-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = E2EJobStore(root: base)
        let j = job()
        try store.create(j)
        XCTAssertEqual(store.load(j.id)?.jiraComments, [:])
        try store.patch(j.id, set: ["jiraComments": ["ABC-1": "2026-11-13T04:40:00Z"]])
        XCTAssertEqual(store.load(j.id)?.jiraComments, ["ABC-1": "2026-11-13T04:40:00Z"])
        // 모양이 다르면 없는 것으로
        try store.patch(j.id, set: ["jiraComments": "x"])
        XCTAssertEqual(store.load(j.id)?.jiraComments, [:])
    }

    func testMultipartBody() {
        let body = JiraClient.multipart(boundary: "B", fileName: "a\"b\r\n.png", mime: "image/png", data: Data([1, 2, 3]))
        let head = "--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"ab.png\"\r\nContent-Type: image/png\r\n\r\n"
        XCTAssertEqual(body, Data(head.utf8) + Data([1, 2, 3]) + Data("\r\n--B--\r\n".utf8))
    }
}
