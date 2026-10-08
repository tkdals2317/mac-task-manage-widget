import XCTest
@testable import TaskWidgetCore

final class TOTPTests: XCTestCase {
    // RFC 6238 부록 B (SHA1, 비밀 "12345678901234567890")
    let b32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

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
