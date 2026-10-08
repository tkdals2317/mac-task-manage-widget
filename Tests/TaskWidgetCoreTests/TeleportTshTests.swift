import XCTest
@testable import TaskWidgetCore

final class TeleportTshTests: XCTestCase {
    private func fixture(_ n: String) -> Data {
        try! Data(contentsOf: Bundle.module.url(forResource: n, withExtension: "json", subdirectory: "Fixtures")!)
    }

    func testDBListParse() {
        let dbs = TeleportTsh.parseDBList(json: fixture("tsh-db-ls"))
        XCTAssertEqual(dbs.map(\.name), ["ats-llm-dv", "ats-llm-x", "mrs-dv", "mrs-prd-rep", "mrs-st2"])   // 이름 없는 항목·중복 제외
        XCTAssertEqual(dbs.filter(\.isProd).map(\.name), ["ats-llm-x", "mrs-prd-rep"])
        XCTAssertEqual(TeleportTsh.parseDBList(json: Data("garbage".utf8)), [])
    }
    func testSessionExpiry() {
        let d = TeleportTsh.parseSessionExpiry(json: fixture("tsh-status"))
        XCTAssertEqual(d, ISO8601DateFormatter().date(from: "2026-10-08T21:07:10Z")!.addingTimeInterval(0.5))
        XCTAssertNil(TeleportTsh.parseSessionExpiry(json: Data(#"{"profiles":[]}"#.utf8)))
        XCTAssertNil(TeleportTsh.parseSessionExpiry(json: Data("not logged in".utf8)))
        XCTAssertNotNil(TeleportTsh.parseSessionExpiry(json: Data(#"{"active":{"valid_until":"2026-10-08T21:07:10+09:00"}}"#.utf8)))
    }
    func testRemainingText() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(TeleportTsh.remainingText(until: now.addingTimeInterval(3 * 3600 + 25 * 60 + 10), now: now), "3시간 25분 남음")
        XCTAssertEqual(TeleportTsh.remainingText(until: now.addingTimeInterval(5 * 60 + 1), now: now), "5분 남음")
        XCTAssertEqual(TeleportTsh.remainingText(until: now.addingTimeInterval(-5), now: now), "만료됨")
    }
    func testLocate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tsh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let exe = dir.appendingPathComponent("tsh").path
        FileManager.default.createFile(atPath: exe, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        XCTAssertEqual(TeleportTsh.locate(configured: exe, shellLookup: { nil }), exe)
        XCTAssertEqual(TeleportTsh.locate(configured: "/nope", shellLookup: { exe }), exe)
    }
    func testIsListening() throws {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        var a = sockaddr_in()
        a.sin_family = sa_family_t(AF_INET); a.sin_addr = in_addr(s_addr: UInt32(0x7f000001).bigEndian); a.sin_port = 0
        let ok = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        XCTAssertEqual(ok, 0); XCTAssertEqual(listen(s, 1), 0)
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(s, $0, &len) } }
        let port = Int(UInt16(bigEndian: a.sin_port))
        XCTAssertTrue(TeleportTsh.isListening(port: port))
        close(s)
        XCTAssertFalse(TeleportTsh.isListening(port: port))
    }
}

private func msg(_ r: Result<Void, TeleportError>) -> String? { if case .failure(let e) = r { return e.message }; return nil }

final class TeleportLoginTests: XCTestCase {
    private var dir: URL!
    private let code = "123456"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("tl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    /// tsh 와 같은 프롬프트(`read -s`). 비밀번호 "secret-pw", OTP "123456" 일 때만 exit 0.
    private func fake(banner: Bool = true, otpPrompt: String = "Enter your OTP token:") throws -> TeleportLogin {
        let script = """
        #!/bin/bash
        [ -t 0 ] || { echo "no tty"; exit 2; }
        \(banner ? #"echo "Press [ENTER] to continue"; read -s x"# : "")
        printf "Enter password for Teleport user tester:"; read -s pw; echo
        [ "$pw" = "secret-pw" ] || { echo "access denied for $pw"; exit 1; }
        printf "\(otpPrompt)"; read -s otp; echo
        [ "$otp" = "\(code)" ] || { echo "invalid OTP"; exit 1; }
        echo "> Profile URL: x"
        """
        let f = dir.appendingPathComponent("fake-tsh.sh")
        try script.write(to: f, atomically: true, encoding: .utf8)
        return TeleportLogin(executable: "/bin/bash", arguments: [f.path], timeout: 15)
    }

    func testSuccess() throws {
        XCTAssertNil(msg(try fake().run(password: "secret-pw", otp: { self.code })))
        XCTAssertNil(msg(try fake(banner: false).run(password: "secret-pw", otp: { self.code })))
    }
    /// 보안키도 등록된 계정의 OTP 문구
    func testSecurityKeyAccountOTPPrompt() throws {
        XCTAssertNil(msg(try fake(otpPrompt: "Tap any security key or enter a code from a OTP device").run(password: "secret-pw", otp: { self.code })))
    }
    func testTimeoutShowsLastPrompt() throws {
        let l = try fake(otpPrompt: "Unknown prompt:")
        let short = TeleportLogin(executable: l.executable, arguments: l.arguments, timeout: 2)
        guard case .failure(let e) = short.run(password: "secret-pw", otp: { self.code }) else { return XCTFail() }
        XCTAssertTrue(e.message.contains("Unknown prompt"), e.message)
        XCTAssertFalse(e.message.contains("secret-pw"), e.message)
    }
    func testWrongPasswordFailsWithoutLeakingIt() throws {
        guard case .failure(let e) = try fake().run(password: "wrong-pw", otp: { self.code }) else { return XCTFail("성공하면 안 됨") }
        XCTAssertTrue(e.message.contains("access denied"), e.message)
        XCTAssertFalse(e.message.contains("wrong-pw"), e.message)
    }
    func testWrongOTP() throws {
        guard case .failure(let e) = try fake().run(password: "secret-pw", otp: { "000000" }) else { return XCTFail() }
        XCTAssertTrue(e.message.contains("invalid OTP"), e.message)
    }
    func testAlreadyLoggedInIsSuccess() {
        let l = TeleportLogin(executable: "/bin/echo", arguments: ["> Profile URL: x"])
        XCTAssertNil(msg(l.run(password: "p", otp: { "1" })))
    }
    func testTimeout() {
        let l = TeleportLogin(executable: "/bin/sleep", arguments: ["30"], timeout: 1)
        guard case .failure(let e) = l.run(password: "p", otp: { "1" }) else { return XCTFail() }
        XCTAssertTrue(e.message.contains("시간 초과"))
    }
    func testExtraEnvironmentReachesTsh() {
        var l = TeleportLogin(executable: "/bin/sh", arguments: ["-c", "test \"$TELEPORT_HOME\" = /tmp/atm-verify"], timeout: 5)
        guard case .failure = l.run(password: "p", otp: { "1" }) else { return XCTFail("환경 변수 없이는 실패해야 함") }
        l.extraEnvironment["TELEPORT_HOME"] = "/tmp/atm-verify"
        XCTAssertNil(msg(l.run(password: "p", otp: { "1" })))
    }
    /// 최신 tsh 처럼 배경색·커서 위치를 묻고 답을 읽은 뒤에 프롬프트를 띄우는 경우
    func testAnswersTerminalQueriesBeforePrompts() throws {
        let script = """
        #!/bin/bash
        printf '\\033]11;?\\033\\\\'; IFS= read -rs -d '\\' bg
        printf '\\033[6n'; IFS= read -rs -d R pos
        echo "Press [ENTER] to continue"; read -s x
        printf '\\033]11;?\\033\\\\'; IFS= read -rs -d '\\' bg2
        printf '\\033[6n'; IFS= read -rs -d R pos2
        printf "Enter password for Teleport user tester:"; read -s pw; echo
        [ "$pw" = "secret-pw" ] || { echo "ERROR: invalid credentials"; exit 1; }
        printf "Enter your OTP token:"; read -s otp; echo
        [ "$otp" = "\(code)" ] || { echo "ERROR: invalid credentials"; exit 1; }
        """
        let f = dir.appendingPathComponent("fake-query-tsh.sh")
        try script.write(to: f, atomically: true, encoding: .utf8)
        let l = TeleportLogin(executable: "/bin/bash", arguments: [f.path], timeout: 10)
        XCTAssertNil(msg(l.run(password: "secret-pw", otp: { self.code })))
    }
    func testMissingExecutable() {
        guard case .failure = TeleportLogin(executable: "/nope/tsh", arguments: []).run(password: "p", otp: { "1" }) else { return XCTFail() }
    }
}
