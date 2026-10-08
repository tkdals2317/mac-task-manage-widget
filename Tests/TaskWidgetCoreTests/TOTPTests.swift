import XCTest
@testable import TaskWidgetCore

final class TOTPTests: XCTestCase {
    // RFC 6238 부록 B (SHA1, 비밀 "12345678901234567890")
    let b32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    /// 기존 파이썬 도구(pyotp)와 같은 코드가 나오는지. 기대값은 pyotp.TOTP(key).at(1700000000).
    func testMatchesPyotp() throws {
        let url = "otpauth://totp/midas-teleport:fake%40teleport.devops.midasin.com?secret=JBSWY3DPEHPK3PXP&issuer=midas-teleport"
        let t = try XCTUnwrap(TOTP(input: url))
        XCTAssertEqual(t.code(at: Date(timeIntervalSince1970: 1_700_000_000)), "324550")
    }

    func testRFCVectors8Digits() throws {
        let t = try XCTUnwrap(TOTP(input: b32))
        let v: [(TimeInterval, String)] = [(59, "94287082"), (1111111109, "07081804"), (1111111111, "14050471"),
                                           (1234567890, "89005924"), (2000000000, "69279037"), (20000000000, "65353130")]
        for (s, code) in v { XCTAssertEqual(t.code(at: Date(timeIntervalSince1970: s), digits: 8), code) }
    }
    func testSixDigitsTruncation() throws {
        let t = try XCTUnwrap(TOTP(input: b32))
        XCTAssertEqual(t.code(at: Date(timeIntervalSince1970: 59)), "287082")
        XCTAssertEqual(t.code(at: Date(timeIntervalSince1970: 1111111109)), "081804")   // 앞 0 유지
    }
    func testInputTolerance() throws {
        let t = try XCTUnwrap(TOTP(input: " gezd gnbv gy3t qojq gezd gnbv gy3t qojq \n"))
        XCTAssertEqual(t.code(at: Date(timeIntervalSince1970: 59)), "287082")
    }
    func testOtpauthURL() throws {
        let t = try XCTUnwrap(TOTP(input: "otpauth://totp/Teleport:me?secret=\(b32)&issuer=Teleport&period=30"))
        XCTAssertEqual(t.code(at: Date(timeIntervalSince1970: 59)), "287082")
    }
    func testInvalid() {
        XCTAssertNil(TOTP(input: ""))
        XCTAssertNil(TOTP(input: "not base32 !!1"))
        XCTAssertNil(TOTP(input: "otpauth://totp/x?issuer=a"))
        XCTAssertNil(TOTP(input: "otpauth://hotp/x?secret=\(b32)"))
    }
    func testSecondsLeft() {
        XCTAssertEqual(TOTP.secondsLeft(at: Date(timeIntervalSince1970: 60)), 30)
        XCTAssertEqual(TOTP.secondsLeft(at: Date(timeIntervalSince1970: 89)), 1)
    }
}

final class TOTPAccountTests: XCTestCase {
    func testAccountUser() {
        XCTAssertEqual(TOTP.accountUser(in: "otpauth://totp/Teleport%3Alsm0506%40teleport.devops.midasin.com?secret=JBSWY3DPEHPK3PXP"), "lsm0506")
        XCTAssertEqual(TOTP.accountUser(in: "otpauth://totp/lsm0506?secret=JBSWY3DPEHPK3PXP"), "lsm0506")
        XCTAssertNil(TOTP.accountUser(in: "JBSWY3DPEHPK3PXP"))
    }

    func testLoginErrorShowsErrorLineOnly() {
        let out = "⚠️ 공지\n긴 안내문\nPress [ENTER] to continue.\nEnter password for Teleport user developer:\nEnter your OTP token:\nERROR: invalid username, password or second factor\n"
        XCTAssertEqual(TeleportLogin.tail(out, redacting: [], status: 1), "tsh 로그인 실패 (exit 1): ERROR: invalid username, password or second factor")
    }
}

final class TeleportLeftoverTests: XCTestCase {
    func testIsTunnelCommand() {
        XCTAssertTrue(TeleportTsh.isTunnelCommand("/usr/local/bin/tsh proxy db --tunnel mrs-dv --db-user developer --port 4306\n", name: "mrs-dv"))
        XCTAssertFalse(TeleportTsh.isTunnelCommand("/usr/local/bin/tsh proxy db --tunnel mrs-dv2 --port 4306", name: "mrs-dv"))
        XCTAssertFalse(TeleportTsh.isTunnelCommand("/usr/local/mysql/bin/mysqld --port 4306", name: "mrs-dv"))
    }
}
