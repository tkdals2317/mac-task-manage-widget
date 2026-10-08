import XCTest
@testable import TaskWidgetCore

final class TeleportConfigTests: XCTestCase {
    func testGroup() {
        XCTAssertEqual(TeleportTunnel.group(forName: "mrs-st2-rep"), "MRS")
        XCTAssertEqual(TeleportTunnel.group(forName: "ats-llm-dv"), "ATS")
        let j = #"{"name":"ats-llm-dv","port":4310,"group":"Retention"}"#
        XCTAssertEqual(try JSONDecoder().decode(TeleportTunnel.self, from: Data(j.utf8)).group, "Retention")
        XCTAssertEqual(TeleportTunnel.group(forName: "foo-bar"), "FOO")
        XCTAssertEqual(TeleportTunnel.group(forName: "solo"), "SOLO")
    }
    func testNextFreePort() {
        XCTAssertEqual(TeleportConfig.nextFreePort(used: []), 4306)
        XCTAssertEqual(TeleportConfig.nextFreePort(used: [4306, 4307, 4309]), 4308)
        XCTAssertEqual(TeleportConfig.nextFreePort(startingAt: 5000, used: [4306]), 5000)
    }
    func testDuplicatePorts() {
        let t = [TeleportTunnel(name: "a", port: 1), TeleportTunnel(name: "b", port: 1), TeleportTunnel(name: "c", port: 2)]
        XCTAssertEqual(TeleportConfig.duplicatePorts(t), [1])
        XCTAssertEqual(TeleportConfig.duplicatePorts([]), [])
    }
    func testRoundTripAndDefaults() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("teleport.json")
        XCTAssertEqual(TeleportConfig.load(from: url), TeleportConfig())
        let c = TeleportConfig(user: "me", tunnels: [TeleportTunnel(name: "mrs-dv", port: 4306)])
        try c.save(to: url)
        XCTAssertEqual(TeleportConfig.load(from: url), c)
        // 손으로 쓴 최소 JSON: 빠진 필드는 기본값
        try Data(#"{"user":"u","tunnels":[{"name":"x","port":1}]}"#.utf8).write(to: url)
        let m = TeleportConfig.load(from: url)
        XCTAssertEqual(m.proxy, TeleportConfig.defaultProxy)
        XCTAssertEqual(m.tunnels[0].dbUser, "developer")
    }
    func testSecretsCodable() throws {
        let s = TeleportSecrets(password: "p", otpSecret: "k")
        XCTAssertEqual(try JSONDecoder().decode(TeleportSecrets.self, from: JSONEncoder().encode(s)), s)
    }
}
