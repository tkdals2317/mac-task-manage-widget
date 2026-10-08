import XCTest
@testable import TaskWidgetCore

final class TeleportAutoConnectTests: XCTestCase {
    func testFiltersRemovedTunnelsKeepsConfigOrder() {
        XCTAssertEqual(TeleportAutoConnect.namesToRestore(persisted: ["b", "gone", "a"], configured: ["a", "b", "c"], enabled: true), ["a", "b"])
    }
    func testDisabledOrEmptyYieldsNothing() {
        XCTAssertEqual(TeleportAutoConnect.namesToRestore(persisted: ["a"], configured: ["a"], enabled: false), [])
        XCTAssertEqual(TeleportAutoConnect.namesToRestore(persisted: [], configured: ["a"], enabled: true), [])
    }
}
