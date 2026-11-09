import XCTest
@testable import TaskWidgetCore

final class E2EJobStoreTests: XCTestCase {
    var root: URL!
    var store: E2EJobStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-\(UUID().uuidString)/jobs")
        store = E2EJobStore(root: root)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func job(_ id: String, env: E2EEnv = .st, created: TimeInterval = 1_800_000_000, status: E2EJobStatus = .queued) -> E2EJob {
        E2EJob(id: id, env: env, baseUrl: "https://st.example.com", username: "qa",
               issues: [E2EIssueRef(key: "ABC-1", url: "https://j/browse/ABC-1", title: "제목")],
               status: status, createdAt: Date(timeIntervalSince1970: created))
    }

    private func raw(_ id: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.jobFile(id))) as? [String: Any])
    }

    private func perm(_ url: URL) throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    }

    func testCreateLoadListDelete() throws {
        try store.create(job("20261109100000-aaaa", created: 100))
        try store.create(job("20261109110000-bbbb", created: 200))
        XCTAssertEqual(try perm(store.jobFile("20261109100000-aaaa")), 0o600)
        XCTAssertEqual(try perm(store.dir("20261109100000-aaaa")), 0o700)
        XCTAssertEqual(store.load("20261109100000-aaaa")?.issues.first?.key, "ABC-1")
        XCTAssertEqual(store.list().map(\.id), ["20261109110000-bbbb", "20261109100000-aaaa"])

        try store.delete("20261109100000-aaaa")
        XCTAssertNil(store.load("20261109100000-aaaa"))
        XCTAssertEqual(store.list().count, 1)
        XCTAssertThrowsError(try store.delete("../x"))
        XCTAssertThrowsError(try store.create(job("../evil")))
    }

    func testListSkipsBrokenAndForeignFolders() throws {
        try store.create(job("20261109100000-aaaa"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("20261109100000-bad1"), withIntermediateDirectories: true)
        try "nope".write(to: store.jobFile("20261109100000-bad1"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".hidden dir"), withIntermediateDirectories: true)
        XCTAssertEqual(store.list().map(\.id), ["20261109100000-aaaa"])
    }

    func testPatchKeepsUnknownKeys() throws {
        let id = "20261109100000-aaaa"
        try store.create(job(id))
        try store.patch(id, set: ["asideNote": "hi"])
        try store.patch(id, set: ["status": "running"], remove: ["notes"])
        let obj = try raw(id)
        XCTAssertEqual(obj["asideNote"] as? String, "hi")
        XCTAssertEqual(obj["status"] as? String, "running")
        XCTAssertNil(obj["notes"])
        XCTAssertEqual(try perm(store.jobFile(id)), 0o600)
    }

    func testPasswordLifecycleOnFinish() throws {
        let id = "20261109100000-aaaa"
        let j = job(id)
        try store.create(j)
        try store.setPassword("p@ss\"w", for: id)
        XCTAssertEqual(try raw(id)["password"] as? String, "p@ss\"w")
        XCTAssertEqual(try perm(store.jobFile(id)), 0o600)
        // Aside 가 비밀번호를 결과·로그에 흘렸다고 치자
        try #"{"issues":[],"summary":"pw=p@ss\"w"}"#.write(to: store.resultFile(id), atomically: true, encoding: .utf8)
        try "login with p@ss\"w\n".write(to: store.logFile(id), atomically: true, encoding: .utf8)

        let done = try store.finish(j, status: .done, error: nil, sessionId: "ses1", secret: "p@ss\"w")
        XCTAssertEqual(done.status, .done)
        let obj = try raw(id)
        XCTAssertNil(obj["password"])
        XCTAssertEqual(obj["status"] as? String, "done")
        XCTAssertEqual(obj["sessionId"] as? String, "ses1")
        XCTAssertNotNil(obj["finishedAt"])
        XCTAssertEqual(try perm(store.jobFile(id)), 0o600)
        let result = try String(contentsOf: store.resultFile(id), encoding: .utf8)
        XCTAssertFalse(result.contains("p@ss"))
        XCTAssertEqual(try E2EResult.decode(Data(result.utf8)).summary, "pw=****")
        XCTAssertEqual(try String(contentsOf: store.logFile(id), encoding: .utf8), "login with ****\n")
    }

    func testFinishRewritesWhenAsideBrokeJobFile() throws {
        let id = "20261109100000-aaaa"
        let j = job(id)
        try store.create(j)
        try #"{"id": "x", "password": "secret1", broken"#.write(to: store.jobFile(id), atomically: true, encoding: .utf8)
        try store.finish(j, status: .failed, error: "결과 없음", sessionId: nil, secret: "secret1")
        let back = try XCTUnwrap(store.load(id))
        XCTAssertEqual(back.status, .failed)
        XCTAssertEqual(back.error, "결과 없음")
        XCTAssertFalse(try String(contentsOf: store.jobFile(id), encoding: .utf8).contains("secret1"))

        // 파일이 아예 없어져도 다시 만든다
        try FileManager.default.removeItem(at: store.jobFile(id))
        try store.finish(j, status: .cancelled, error: nil, sessionId: nil)
        XCTAssertEqual(store.load(id)?.status, .cancelled)
    }

    func testScrubPasswordOnBrokenJSON() throws {
        let id = "20261109100000-aaaa"
        try store.create(job(id))
        try #"{"id": "x", "password" : "se\"cret", "status": "running",,}"#.write(to: store.jobFile(id), atomically: true, encoding: .utf8)
        store.scrubPassword(id)
        let text = try String(contentsOf: store.jobFile(id), encoding: .utf8)
        XCTAssertFalse(text.contains("se\\\"cret"))
        XCTAssertTrue(text.contains(#""password": """#))
        XCTAssertEqual(try perm(store.jobFile(id)), 0o600)
    }

    func testRecoverOnLaunchClosesActiveJobsAndScrubs() throws {
        try store.create(job("20261109100000-runn", status: .running))
        try store.create(job("20261109100000-queu", status: .queued))
        try store.create(job("20261109100000-done", status: .done))
        try store.setPassword("pw1", for: "20261109100000-runn")
        try store.setPassword("pw2", for: "20261109100000-done")
        store.writePid(4242, for: "20261109100000-runn")
        try "[ATM x] 시작\n[err] created new session: ses-crash\n[err] Thinking...\n".write(
            to: store.logFile("20261109100000-runn"), atomically: true, encoding: .utf8)

        try store.create(job("20261109100000-late", created: 2_000_000_000, status: .queued))
        try store.setPassword("pw3", for: "20261109100000-late")
        let closed = store.recoverOnLaunch(createdBefore: Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertEqual(Set(closed.map(\.id)), ["20261109100000-runn", "20261109100000-queu"])
        XCTAssertEqual(closed.first { $0.id == "20261109100000-runn" }?.pid, 4242)
        XCTAssertNil(closed.first { $0.id == "20261109100000-queu" }?.pid)
        XCTAssertEqual(closed.first { $0.id == "20261109100000-runn" }?.sessionId, "ses-crash")
        XCTAssertNil(closed.first { $0.id == "20261109100000-queu" }?.sessionId)
        XCTAssertEqual(store.load("20261109100000-runn")?.status, .failed)
        XCTAssertEqual(store.load("20261109100000-queu")?.status, .cancelled)
        XCTAssertEqual(store.load("20261109100000-done")?.status, .done)
        for id in ["20261109100000-runn", "20261109100000-queu", "20261109100000-done"] {
            XCTAssertNil(try raw(id)["password"], id)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.pidFile(id).path), id)
        }
        // 이번 실행에서 만든 job 은 그대로 (대기 상태·비밀번호 유지)
        XCTAssertEqual(store.load("20261109100000-late")?.status, .queued)
        XCTAssertEqual(try raw("20261109100000-late")["password"] as? String, "pw3")
        XCTAssertTrue(store.recoverOnLaunch(createdBefore: Date(timeIntervalSince1970: 1_900_000_000)).isEmpty)
    }

    func testResultLoad() throws {
        let id = "20261109100000-aaaa"
        try store.create(job(id))
        XCTAssertEqual(store.result(id), .missing)
        try "{".write(to: store.resultFile(id), atomically: true, encoding: .utf8)
        XCTAssertEqual(store.result(id), .invalid("JSON 형식이 아님"))
        try #"{"summary": "x"}"#.write(to: store.resultFile(id), atomically: true, encoding: .utf8)
        XCTAssertEqual(store.result(id), .invalid("issues 항목 없음"))
        try #"{"issues": [{"key": "ABC-1", "verdict": "PASS"}]}"#.write(to: store.resultFile(id), atomically: true, encoding: .utf8)
        guard case .ok(let r) = store.result(id) else { return XCTFail("결과를 못 읽음") }
        XCTAssertEqual(r.issues.first?.verdict, .pass)
    }

    func testPruneOldFinishedJobs() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        try store.create(job("20261109100000-old1", created: now.timeIntervalSince1970 - 31 * day, status: .done))
        try store.create(job("20261109100000-old2", created: now.timeIntervalSince1970 - 31 * day, status: .running))
        try store.create(job("20261109100000-new1", created: now.timeIntervalSince1970 - 29 * day, status: .failed))
        XCTAssertEqual(store.prune(olderThanDays: 0, now: now), 0)
        XCTAssertEqual(store.prune(olderThanDays: 30, now: now), 1)
        XCTAssertEqual(Set(store.list().map(\.id)), ["20261109100000-old2", "20261109100000-new1"])
    }

    func testScreenshotURLStaysInJobFolder() throws {
        let id = "20261109100000-aaaa"
        try store.create(job(id))
        try Data([1, 2, 3]).write(to: store.dir(id).appendingPathComponent("ABC-1-1.png"))
        XCTAssertEqual(store.screenshotURL(id, name: "ABC-1-1.png")?.lastPathComponent, "ABC-1-1.png")
        XCTAssertEqual(store.screenshotURL(id, name: "/Users/x/.aside/tmp/ABC-1-1.png")?.lastPathComponent, "ABC-1-1.png")
        XCTAssertNil(store.screenshotURL(id, name: "../../secrets.json"))
        XCTAssertNil(store.screenshotURL(id, name: "missing.png"))
        XCTAssertNil(store.screenshotURL(id, name: ".."))
    }
}
