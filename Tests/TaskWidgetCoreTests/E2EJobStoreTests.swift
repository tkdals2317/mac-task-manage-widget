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

    func testFinishWritesStatusAndSession() throws {
        let id = "20261109100000-aaaa"
        let j = job(id)
        try store.create(j)
        try store.patch(id, set: ["error": "이전 오류"])
        let done = try store.finish(j, status: .done, error: nil, sessionId: "ses1")
        XCTAssertEqual(done.status, .done)
        let obj = try raw(id)
        XCTAssertEqual(obj["status"] as? String, "done")
        XCTAssertEqual(obj["sessionId"] as? String, "ses1")
        XCTAssertNil(obj["error"])
        XCTAssertNotNil(obj["finishedAt"])
        XCTAssertEqual(try perm(store.jobFile(id)), 0o600)
    }

    func testFinishRewritesBrokenJobFile() throws {
        let id = "20261109100000-aaaa"
        let j = job(id)
        try store.create(j)
        try #"{"id": "x", broken"#.write(to: store.jobFile(id), atomically: true, encoding: .utf8)
        try store.finish(j, status: .failed, error: "결과 없음", sessionId: nil)
        let back = try XCTUnwrap(store.load(id))
        XCTAssertEqual(back.status, .failed)
        XCTAssertEqual(back.error, "결과 없음")

        // 파일이 아예 없어져도 다시 만든다
        try FileManager.default.removeItem(at: store.jobFile(id))
        try store.finish(j, status: .cancelled, error: nil, sessionId: nil)
        XCTAssertEqual(store.load(id)?.status, .cancelled)
    }

    func testPrepareAndImportWorkDir() throws {
        let id = "20261109100000-aaaa"
        var j = job(id)
        j.requestedBy = "me@example.com"
        j.issues[0].detailFile = "jira/ABC-1.md"
        try store.create(j)
        let jira = store.dir(id).appendingPathComponent("jira")
        try FileManager.default.createDirectory(at: jira, withIntermediateDirectories: true)
        try "# ABC-1".write(to: jira.appendingPathComponent("ABC-1.md"), atomically: true, encoding: .utf8)

        let work = root.deletingLastPathComponent().appendingPathComponent("aside/atm-e2e/\(id)")
        try store.prepareWorkDir(j, at: work)
        XCTAssertEqual(try perm(work), 0o700)
        let req = try JSONDecoder().decode(E2ERequest.self, from: Data(contentsOf: work.appendingPathComponent("request.json")))
        XCTAssertEqual(req, E2ERequest(j))
        let reqText = try String(contentsOf: work.appendingPathComponent("request.json"), encoding: .utf8)
        XCTAssertFalse(reqText.contains("me@example.com"), "요청자·상태 같은 ATM 기록은 넘기지 않는다")
        XCTAssertFalse(reqText.contains("password"))
        XCTAssertEqual(try String(contentsOf: work.appendingPathComponent("jira/ABC-1.md"), encoding: .utf8), "# ABC-1")

        // Aside 가 남긴 것: 결과, 스크린샷, 실행 파일, 링크, 폴더, 큰 이미지
        let fm = FileManager.default
        try #"{"issues":[{"key":"ABC-1","verdict":"PASS"}]}"#.write(to: work.appendingPathComponent("result.json"), atomically: true, encoding: .utf8)
        try Data([1, 2, 3]).write(to: work.appendingPathComponent("ABC-1-1.png"))
        try Data([1]).write(to: work.appendingPathComponent("ABC-1-2.JPG"))
        try "#!/bin/sh\n".write(to: work.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: work.appendingPathComponent("ABC-1-1.png").path)
        try fm.createSymbolicLink(at: work.appendingPathComponent("ABC-1-3.png"), withDestinationURL: store.jobFile(id))
        try fm.createDirectory(at: work.appendingPathComponent("evil.png"), withIntermediateDirectories: true)
        try Data(count: E2EJobStore.maxImageBytes + 1).write(to: work.appendingPathComponent("big.png"))

        let skipped = store.importResults(from: work, into: id)
        XCTAssertEqual(Set(skipped), ["run.sh", "ABC-1-3.png", "evil.png", "big.png"])
        XCTAssertFalse(fm.fileExists(atPath: work.path), "실행용 폴더는 지운다")
        guard case .ok(let r) = store.result(id) else { return XCTFail("결과를 못 가져옴") }
        XCTAssertEqual(r.issues.first?.verdict, .pass)
        XCTAssertNotNil(store.screenshotURL(id, name: "ABC-1-1.png"))
        XCTAssertNotNil(store.screenshotURL(id, name: "ABC-1-2.JPG"))
        XCTAssertEqual(try perm(store.dir(id).appendingPathComponent("ABC-1-1.png")), 0o600, "실행 권한 없이 다시 쓴다")
        for n in ["run.sh", "ABC-1-3.png", "evil.png", "big.png", "request.json"] {
            XCTAssertFalse(fm.fileExists(atPath: store.dir(id).appendingPathComponent(n).path), n)
        }
        XCTAssertEqual(store.importResults(from: work, into: id), [], "폴더가 없으면 아무것도 안 한다")
    }

    func testPruneWorkDirsKeepsThisLaunch() throws {
        let rootA = root.deletingLastPathComponent().appendingPathComponent("aside/u0/atm-e2e")
        let fm = FileManager.default
        for name in ["20261109100000-old1", "20991231235959-new1", "not-a-job.txt"] {
            try fm.createDirectory(at: rootA.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let launched = try XCTUnwrap(E2EJobID.date("20261110000000-xxxx"))
        XCTAssertEqual(E2EJobStore.pruneWorkDirs(in: [rootA], createdBefore: launched), ["20261109100000-old1"])
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: rootA.path)), ["20991231235959-new1", "not-a-job.txt"])
    }

    func testRecoverOnLaunchClosesActiveJobs() throws {
        try store.create(job("20261109100000-runn", status: .running))
        try store.create(job("20261109100000-queu", status: .queued))
        try store.create(job("20261109100000-done", status: .done))
        store.writePid(4242, for: "20261109100000-runn")
        try "[ATM x] 시작\n[err] created new session: ses-crash\n[err] Thinking...\n".write(
            to: store.logFile("20261109100000-runn"), atomically: true, encoding: .utf8)

        try store.create(job("20261109100000-late", created: 2_000_000_000, status: .queued))
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
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.pidFile(id).path), id)
        }
        // 이번 실행에서 만든 job 은 그대로 (대기 상태 유지)
        XCTAssertEqual(store.load("20261109100000-late")?.status, .queued)
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
        // 이미지가 아니거나 링크·폴더면 열 수 있는 주소를 주지 않는다
        XCTAssertNil(store.screenshotURL(id, name: "job.json"))
        try "#!/bin/sh\n".write(to: store.dir(id).appendingPathComponent("run.command"), atomically: true, encoding: .utf8)
        XCTAssertNil(store.screenshotURL(id, name: "run.command"))
        try FileManager.default.createSymbolicLink(at: store.dir(id).appendingPathComponent("link.png"),
                                                   withDestinationURL: store.dir(id).appendingPathComponent("ABC-1-1.png"))
        XCTAssertNil(store.screenshotURL(id, name: "link.png"))
        try FileManager.default.createDirectory(at: store.dir(id).appendingPathComponent("Fake.app.png"), withIntermediateDirectories: true)
        XCTAssertNil(store.screenshotURL(id, name: "Fake.app.png"))
    }
}
