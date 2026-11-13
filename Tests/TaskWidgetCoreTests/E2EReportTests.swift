import XCTest
@testable import TaskWidgetCore

final class E2EReportTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let png = Data([0x89, 0x50, 0x4E, 0x47])

    private func job(keys: [String] = ["ABC-1"], env: E2EEnv = .st, status: E2EJobStatus = .done, error: String? = nil,
                     username: String = "qa01", notes: String = "") -> E2EJob {
        E2EJob(id: "20261113100000-aaaa", env: env, baseUrl: "https://st.example.com", username: username,
               issues: keys.map { E2EIssueRef(key: $0, url: "https://jira.example.com/browse/\($0)", title: "제목 \($0)") },
               notes: notes, status: status, createdAt: Date(timeIntervalSince1970: 1_800_000_000),
               finishedAt: Date(timeIntervalSince1970: 1_800_000_300), error: error)
    }

    private func html(_ job: E2EJob, _ result: E2EResultLoad, logTail: String = "", images: [String: Data] = [:]) -> String {
        E2EReport.html(job: job, result: result, modelName: "기본 모델", logTail: logTail, timeZone: utc) { name in
            images[name].map { E2EReport.Image(mime: "image/png", data: $0) }
        }
    }

    func testFileName() {
        XCTAssertEqual(E2EReport.fileName(job(), timeZone: utc), "ATM-E2E-ABC-1-ST-20270115-0800.html")
        XCTAssertEqual(E2EReport.fileName(job(keys: ["ABC-1", "ABC-2", "XY-9"], env: .dv), timeZone: utc),
                       "ATM-E2E-ABC-1+2-DV-20270115-0800.html")
        // 이슈가 없으면 job id, 경로에 쓰면 안 되는 글자는 뺀다
        XCTAssertEqual(E2EReport.fileName(job(keys: []), timeZone: utc), "ATM-E2E-20261113100000-aaaa-ST-20270115-0800.html")
        XCTAssertEqual(E2EReport.fileName(job(keys: ["../A/B-1"]), timeZone: utc), "ATM-E2E-AB-1-ST-20270115-0800.html")
    }

    func testResultWithScenariosAndScreenshot() {
        let scenario = E2EScenario(name: "주문 취소", steps: ["로그인", "주문 상세 열기"], expected: "취소됨으로 바뀐다",
                                   actual: "오류 문구 <b>실패</b>", verdict: .fail, screenshots: ["ABC-1-1.png", "없는파일.png"])
        let result = E2EResult(summary: "1건 실패 <script>alert(1)</script>", issues: [
            E2EIssueResult(key: "ABC-1", title: "주문 취소 버튼", url: "https://evil.example.com/x",
                           assumptions: ["쿠폰은 없다고 가정"], scenarios: [scenario], notes: "메모"),
        ])
        let out = html(job(notes: "테스트 데이터 & 메모"), .ok(result), images: ["ABC-1-1.png": png])

        XCTAssertTrue(out.hasPrefix("<!doctype html>"))
        XCTAssertTrue(out.contains("<title>E2E 검증 결과 · ABC-1</title>"))
        XCTAssertTrue(out.contains("<td>ST</td>"))
        XCTAssertTrue(out.contains("<td>https://st.example.com</td>"))
        XCTAssertTrue(out.contains("<td>qa01</td>"))
        XCTAssertTrue(out.contains("<td>2027-01-15 08:00 ~ 08:05</td>"))
        XCTAssertTrue(out.contains("<tr><th>추가 요청사항</th><td>테스트 데이터 &amp; 메모</td></tr>"))
        XCTAssertTrue(out.contains("<span class=\"badge fail\">FAIL 1</span>"))
        XCTAssertTrue(out.contains("<h3>주문 취소 <span class=\"badge fail\">FAIL</span></h3>"))
        XCTAssertTrue(out.contains("<ol><li>로그인</li><li>주문 상세 열기</li></ol>"))
        XCTAssertTrue(out.contains("<tr><th>기대</th><td>취소됨으로 바뀐다</td></tr>"))
        XCTAssertTrue(out.contains("<li>쿠폰은 없다고 가정</li>"))
        // Aside 가 쓴 글자는 태그로 살아나지 않는다
        XCTAssertTrue(out.contains("오류 문구 &lt;b&gt;실패&lt;/b&gt;"))
        XCTAssertFalse(out.contains("<script>"))
        // 링크는 ATM 이 만든 Jira 주소만
        XCTAssertTrue(out.contains("<a href=\"https://jira.example.com/browse/ABC-1\">ABC-1</a>"))
        XCTAssertFalse(out.contains("evil.example.com"))
        // 스크린샷은 파일 안에 넣고, 없는 파일은 뺀다
        XCTAssertTrue(out.contains("src=\"data:image/png;base64,\(png.base64EncodedString())\""))
        XCTAssertTrue(out.contains("<figcaption>ABC-1-1.png</figcaption>"))
        XCTAssertFalse(out.contains("없는파일.png"))
    }

    func testIssueKeyIsNotLinkedWhenJobUrlIsNotWeb() {
        var j = job()
        j.issues = [E2EIssueRef(key: "ABC-1", url: "javascript:alert(1)", title: "제목")]
        let out = html(j, .ok(E2EResult(issues: [E2EIssueResult(key: "ABC-1", reportedVerdict: .pass)])))
        XCTAssertFalse(out.contains("<a href"))
        XCTAssertTrue(out.contains("<h2>ABC-1 제목 <span class=\"badge pass\">PASS</span></h2>"))
    }

    func testFailedJobShowsReasonStepsAndLog() {
        let kind = E2EFailureKind.windowClosed
        let out = html(job(status: .failed, error: kind.message), .missing, logTail: "line1\nprofile <x> is not connected")
        XCTAssertTrue(out.contains("검증을 돌리지 못했어요"))
        XCTAssertTrue(out.contains(E2EReport.esc(kind.message)))
        for step in kind.steps { XCTAssertTrue(out.contains("<li>\(E2EReport.esc(step))</li>")) }
        XCTAssertTrue(out.contains("<td>실패</td>"))
        XCTAssertTrue(out.contains("<pre>line1\nprofile &lt;x&gt; is not connected</pre>"))
        XCTAssertFalse(out.contains("결과가 없어요"))

        // 모르는 오류는 문구만, 결과도 오류도 없으면 "결과가 없어요"
        let unknown = html(job(status: .failed, error: "알 수 없는 오류"), .missing)
        XCTAssertTrue(unknown.contains("<p>알 수 없는 오류</p>"))
        XCTAssertFalse(unknown.contains("<ol>"))
        XCTAssertTrue(html(job(status: .cancelled), .missing).contains("결과가 없어요"))
        XCTAssertTrue(html(job(), .invalid("issues 항목 없음")).contains("result.json 을 읽지 못했어요"))
    }

    func testLoginBlockedShowsWhatToDo() {
        let result = E2EResult(loginBlocked: .vaultLocked, issues: [E2EIssueResult(key: "ABC-1", reportedVerdict: .blocked)])
        let out = html(job(), .ok(result))
        XCTAssertTrue(out.contains("환경 로그인에서 막혔어요"))
        XCTAssertTrue(out.contains(E2ELoginBlock.vaultLocked.reason))
        XCTAssertTrue(out.contains("<span class=\"badge blocked\">BLOCKED 1</span>"))
        XCTAssertTrue(html(job(username: ""), .ok(E2EResult(loginBlocked: .noSavedLogin, issues: [])))
            .contains("테스트 계정으로 직접 로그인해요"))
    }

    func testExportWritesOneFileWithScreenshots() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-report-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = E2EJobStore(root: base.appendingPathComponent("jobs"))
        let out = base.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let j = job()
        try store.create(j)
        let json = """
        {"status":"done","summary":"요약","issues":[{"key":"ABC-1","title":"t","scenarios":[
          {"name":"s","verdict":"PASS","screenshots":["shot.jpg","../../etc/passwd","note.txt"]}]}]}
        """
        try Data(json.utf8).write(to: store.resultFile(j.id))
        try png.write(to: store.dir(j.id).appendingPathComponent("shot.jpg"))
        try Data("비밀".utf8).write(to: store.dir(j.id).appendingPathComponent("note.txt"))

        let url = try E2EReport.export(j, store: store, modelName: "m", to: out, timeZone: utc)
        XCTAssertEqual(url.lastPathComponent, "ATM-E2E-ABC-1-ST-20270115-0800.html")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("src=\"data:image/jpeg;base64,\(png.base64EncodedString())\""))
        XCTAssertFalse(text.contains("note.txt"))
        XCTAssertFalse(text.contains("passwd"))
        XCTAssertTrue(text.contains("<span class=\"badge pass\">PASS 1</span>"))

        // 다시 내보내면 같은 이름을 덮어쓴다
        XCTAssertEqual(try E2EReport.export(j, store: store, modelName: "m", to: out, timeZone: utc), url)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path).count, 1)
    }

    func testLogTail() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-report-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = E2EJobStore(root: base)
        let j = job()
        try store.create(j)
        XCTAssertEqual(store.logTail(j.id), "")
        try Data((1...30).map { "line\($0)" }.joined(separator: "\n").appending("\n").utf8).write(to: store.logFile(j.id))
        XCTAssertEqual(store.logTail(j.id, lines: 3), "line29\nline30")
        XCTAssertTrue(store.logTail(j.id).hasPrefix("line17\n"))
    }
}
