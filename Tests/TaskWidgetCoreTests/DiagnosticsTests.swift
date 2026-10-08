import XCTest
@testable import TaskWidgetCore

final class DiagnosticsTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testVisibleControlChars() {
        XCTAssertEqual(DiagTranscript.visible("a\u{1B}[6n\r\nb\u{07}\t"), "a\\e[6n\\r\nb\\x07\\x09")
    }

    func testRedactAcrossChunksAndDirections() {
        let ev: [DiagTranscript.Event] = [
            .init(ms: 1, outbound: false, text: "echo: secret-"),
            .init(ms: 2, outbound: false, text: "pw done 123456\n"),
            .init(ms: 3, outbound: true, text: "secret-pw\n"),
            .init(ms: 4, outbound: true, text: "123456\n"),
        ]
        let out = DiagTranscript.render(ev, secrets: ["secret-pw", "123456", ""])
        XCTAssertFalse(out.contains("secret"), out)
        XCTAssertFalse(out.contains("123456"), out)
        XCTAssertTrue(out.contains("] > ***"), out)
        XCTAssertTrue(out.contains("] < echo: ***"), out)
    }

    func testTrimmed() {
        let line = String(repeating: "x", count: 99) + "\n"
        let d = Data(String(repeating: line, count: 20).utf8)   // 2000 bytes
        XCTAssertEqual(DiagLog.trimmed(d, max: 3000, keep: 1000), d)
        let t = DiagLog.trimmed(d, max: 1500, keep: 1000)
        XCTAssertLessThanOrEqual(t.count, 1000)
        XCTAssertEqual(String(decoding: t, as: UTF8.self).split(separator: "\n").allSatisfy { $0.count == 99 }, true)
    }

    func testAppendCapsFile() throws {
        for i in 0..<8000 { DiagLog.append("line \(i) " + String(repeating: "y", count: 80), dir: dir) }
        let size = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("app.log").path)[.size] as! Int
        XCTAssertLessThanOrEqual(size, DiagLog.maxBytes)
        let text = try String(contentsOf: dir.appendingPathComponent("app.log"), encoding: .utf8)
        XCTAssertTrue(text.contains("line 7999 "))
        XCTAssertFalse(text.contains("line 0 "))
    }

    func testMaskEmail() {
        XCTAssertEqual(DiagnosticsExport.maskEmail("lsm0506@midasin.com"), "***@midasin.com")
        XCTAssertEqual(DiagnosticsExport.maskEmail(""), "(없음)")
    }

    func testRedactDefaults() {
        let src = """
        {
            jiraBaseURL = "https://x.atlassian.net";
            jiraEmail = "me@midasin.com";
            jiraApiToken = abc;
            teleportOtpKey = (
                "AAAA",
                "BBBB"
            );
            enabledTabs = "tasks,summary";
            "my-Secret" = {
                a = 1;
            };
            opacity = 1;
        }
        """
        let out = DiagnosticsExport.redactDefaults(src)
        for bad in ["abc", "AAAA", "BBBB", "me@", "my-Secret", "a = 1"] { XCTAssertFalse(out.contains(bad), "\(bad)\n\(out)") }
        for good in ["jiraBaseURL", "***@midasin.com", "enabledTabs", "opacity = 1;"] { XCTAssertTrue(out.contains(good), "\(good)\n\(out)") }
    }

    /// 실제 PTY 로 돌려 본 기록. 비밀번호·OTP 는 어디에도 남지 않는다.
    func testLoginTranscriptRedacted() throws {
        let script = """
        #!/bin/bash
        printf '\\033]11;?\\007'
        echo "Press [ENTER] to continue"; read -rs x
        printf "Enter password for Teleport user tester:"; read -s pw; echo
        printf "Enter your OTP token:"; read -s otp; echo
        echo "> Profile URL: x"
        """
        let f = dir.appendingPathComponent("fake.sh")
        try script.write(to: f, atomically: true, encoding: .utf8)
        let (res, rep) = TeleportLogin(executable: "/bin/bash", arguments: [f.path], timeout: 15)
            .runReported(password: "secret-pw", otp: { "654321" })
        guard case .success = res else { return XCTFail("\(res)") }
        XCTAssertFalse(rep.transcript.contains("secret-pw"))
        XCTAssertFalse(rep.transcript.contains("654321"))
        XCTAssertTrue(rep.transcript.contains("> ***"), rep.transcript)
        XCTAssertTrue(rep.transcript.contains("\\e]11;?"), rep.transcript)
        XCTAssertEqual(rep.exitStatus, 0)
        XCTAssertFalse(rep.timedOut)
        let block = TeleportLoginLog.block(kind: "setup", user: "tester", proxy: "p.example.com", tsh: "/x/tsh", version: "Teleport v1",
                                           report: rep, result: res, now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(block.hasPrefix("=== 19"), block)
        XCTAssertTrue(block.contains("login (setup) user=tester proxy=p.example.com tsh=/x/tsh (Teleport v1) ==="))
        XCTAssertTrue(block.contains("--- result: ok exit=0 "))
        print("\n--- SAMPLE TRANSCRIPT ---\n\(block)--- END SAMPLE ---")
    }

    func testLoginTimeoutReport() {
        let (res, rep) = TeleportLogin(executable: "/bin/sleep", arguments: ["30"], timeout: 1).runReported(password: "p", otp: { "1" })
        guard case .failure = res else { return XCTFail() }
        XCTAssertTrue(rep.timedOut)
    }

    /// 데이터 폴더에 secrets.json·todos 등이 있어도 내보내기에 들어가지 않는다 (logs 에 이름이 같은 파일이 있어도).
    func testExportNeverIncludesSecrets() throws {
        let fm = FileManager.default
        let data = dir.appendingPathComponent("data"), logs = data.appendingPathComponent("logs")
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        for f in ["secrets.json", "todos.json", "activity.jsonl"] { try "TOPSECRET".write(to: data.appendingPathComponent(f), atomically: true, encoding: .utf8) }
        try fm.createDirectory(at: data.appendingPathComponent("worklog"), withIntermediateDirectories: true)
        try "TOPSECRET".write(to: data.appendingPathComponent("worklog/a.md"), atomically: true, encoding: .utf8)
        try "TOPSECRET".write(to: logs.appendingPathComponent("secrets.json"), atomically: true, encoding: .utf8)
        try "ok".write(to: logs.appendingPathComponent("app.log"), atomically: true, encoding: .utf8)
        try #"{"proxy":"p"}"#.write(to: data.appendingPathComponent("teleport.json"), atomically: true, encoding: .utf8)

        let desktop = dir.appendingPathComponent("desktop")
        try fm.createDirectory(at: desktop, withIntermediateDirectories: true)
        let zip = try DiagnosticsExport.export(to: desktop, dataDir: data, logsDir: logs, info: "info\n", defaults: "{\n    pw = 1;\n    secretKey = 2;\n}")
        XCTAssertTrue(zip.lastPathComponent.hasPrefix("ATM-진단-") && zip.pathExtension == "zip")

        let r = ProcessRunner.run(executable: "/usr/bin/unzip", arguments: ["-Z1", zip.path], timeout: 10)
        let names = r.stdout.split(separator: "\n").map(String.init)
        for want in ["logs/app.log", "info.txt", "defaults.txt", "teleport.json"] { XCTAssertTrue(names.contains { $0.hasSuffix(want) }, "\(want) in \(names)") }
        for bad in ["secrets.json", "todos.json", "activity.jsonl", "worklog"] { XCTAssertFalse(names.contains { $0.contains(bad) }, "\(bad) in \(names)") }

        let files = try DiagnosticsExport.stage(into: dir.appendingPathComponent("stage"), dataDir: data, logsDir: logs, info: "i", defaults: "")
        XCTAssertEqual(files, ["logs/app.log", "info.txt", "defaults.txt", "teleport.json"])
    }

    func testInfoTextHasNoSecrets() {
        let suite = UserDefaults(suiteName: "diag-\(UUID().uuidString)")!
        let s = Settings(defaults: suite)
        s.jiraEmail = "me@midasin.com"; s.jiraBaseURL = "https://x.atlassian.net"
        let cfg = TeleportConfig(proxy: "p.example.com", user: "tester", tunnels: [TeleportTunnel(name: "mrs-dv", port: 4306)])
        let i = DiagnosticsExport.InfoInput(build: BuildInfo(infoDictionary: [:]), settings: s, teleport: cfg, tshPath: "/x/tsh",
                                            claudePath: nil, hasJiraToken: true, hasTeleportSecrets: false)
        let t = DiagnosticsExport.infoText(i, run: { exe, _ in "out(\(exe))" })
        XCTAssertTrue(t.contains("email=***@midasin.com"))
        XCTAssertFalse(t.contains("me@"))
        XCTAssertTrue(t.contains("jira token 있음: yes") && t.contains("teleport 비밀 정보 있음: no"))
        XCTAssertTrue(t.contains("tunnel mrs-dv port=4306"))
    }
}
