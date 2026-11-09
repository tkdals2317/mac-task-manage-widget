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
    func testLegacyTunnelDecodesAsDB() throws {
        // kind 가 생기기 전 teleport.json
        let j = #"{"name":"mrs-dv","dbUser":"developer","port":4306,"group":"MRS"}"#
        let t = try JSONDecoder().decode(TeleportTunnel.self, from: Data(j.utf8))
        XCTAssertEqual(t.kind, .db)
        XCTAssertEqual(t.proxyArguments, ["proxy", "db", "--tunnel", "mrs-dv", "--db-user", "developer", "--port", "4306"])
        XCTAssertEqual(t.logoutArguments, ["db", "logout", "mrs-dv"])
    }
    func testDBEncodingUnchanged() throws {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        let s = String(decoding: try e.encode(TeleportTunnel(name: "mrs-dv", port: 4306)), as: UTF8.self)
        XCTAssertEqual(s, #"{"dbUser":"developer","name":"mrs-dv","port":4306}"#)
    }
    func testAppRoundTrip() throws {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        let app = TeleportTunnel(name: "grafana-dv", port: 18123, kind: .app)
        let d = try e.encode(app)
        XCTAssertEqual(String(decoding: d, as: UTF8.self), #"{"kind":"app","name":"grafana-dv","port":18123}"#)
        XCTAssertEqual(try JSONDecoder().decode(TeleportTunnel.self, from: d), app)
        XCTAssertEqual(app.proxyArguments, ["proxy", "app", "grafana-dv", "--port", "18123"])
        XCTAssertEqual(app.logoutArguments, ["apps", "logout", "grafana-dv"])
        XCTAssertEqual(app.group, "GRAFANA")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("teleport.json")
        let c = TeleportConfig(user: "me", tunnels: [TeleportTunnel(name: "mrs-dv", port: 4306), app])
        try c.save(to: url)
        XCTAssertEqual(TeleportConfig.load(from: url), c)
    }
    func testSecretsCodable() throws {
        let s = TeleportSecrets(password: "p", otpSecret: "k")
        XCTAssertEqual(try JSONDecoder().decode(TeleportSecrets.self, from: JSONEncoder().encode(s)), s)
    }
}

final class TeleportCleanIDTests: XCTestCase {
    func testRemovesInvisibleCharacters() {
        XCTAssertEqual(TeleportConfig.cleanID(" hsw0618\u{200B}\n"), "hsw0618")
        XCTAssertEqual(TeleportConfig.cleanID("\u{FEFF}lsm0506\u{00A0}"), "lsm0506")
        XCTAssertEqual(TeleportConfig.cleanID("teleport.example.com\t"), "teleport.example.com")
    }
}
