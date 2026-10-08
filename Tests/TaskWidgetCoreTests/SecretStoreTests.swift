import XCTest
@testable import TaskWidgetCore

private final class FakeBackend: SecretBackend {
    var data: [String: String] = [:]
    var failGet = false
    func get(service: String, account: String) throws -> String? {
        if failGet { throw KeychainError.status(-128) }
        return data["\(service)/\(account)"]
    }
    func set(_ value: String, service: String, account: String) throws { data["\(service)/\(account)"] = value }
    func delete(service: String, account: String) throws { data["\(service)/\(account)"] = nil }
}

final class SecretStoreTests: XCTestCase {
    func testFileRoundTripPermissionsAndDelete() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("secrets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("sub/secrets.json")
        let b = FileBackend(url: url)
        XCTAssertNil(try b.get(service: "s1", account: "a"))
        try b.set("v1", service: "s1", account: "a")
        try b.set("v2", service: "s1", account: "b")
        try b.set("v3", service: "s2", account: "a")
        try b.set("v1x", service: "s1", account: "a")
        XCTAssertEqual(try b.get(service: "s1", account: "a"), "v1x")
        XCTAssertEqual(try b.get(service: "s1", account: "b"), "v2")
        XCTAssertEqual(try b.get(service: "s2", account: "a"), "v3")
        let perm = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(perm, 0o600)
        try b.delete(service: "s1", account: "a")
        XCTAssertNil(try b.get(service: "s1", account: "a"))
        XCTAssertEqual(try b.get(service: "s1", account: "b"), "v2")
        try b.delete(service: "nope", account: "x")
    }

    func testMigrateMovesAndDeletesOld() throws {
        let old = FakeBackend(), new = FakeBackend()
        old.data["j/me@x.com"] = "tok"
        old.data["t/credentials"] = "{}"
        let items = [("j", "me@x.com"), ("t", "credentials"), ("t", "missing")]
        XCTAssertEqual(try SecretStore.migrate(items: items, from: old, to: new), 2)
        XCTAssertEqual(new.data["j/me@x.com"], "tok")
        XCTAssertTrue(old.data.isEmpty)
    }

    func testMigrateReadFailureKeepsOld() {
        let old = FakeBackend(), new = FakeBackend()
        old.data["j/a"] = "tok"
        old.failGet = true
        XCTAssertThrowsError(try SecretStore.migrate(items: [("j", "a")], from: old, to: new))
        XCTAssertEqual(old.data["j/a"], "tok")
        XCTAssertTrue(new.data.isEmpty)
    }
}
