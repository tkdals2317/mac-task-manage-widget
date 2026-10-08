import XCTest
@testable import TaskWidgetCore

final class TeleportWatchdogPolicyTests: XCTestCase {
    private func decide(running: Set<String> = ["a"], listening: Set<String> = ["a"],
                        failures: [String: Int] = [:], loggedIn: Bool = true) -> TeleportWatchdogPolicy {
        .decide(wanted: ["a"], running: running, listening: listening, failures: failures, loggedIn: loggedIn)
    }

    func testHealthyNoop() { XCTAssertEqual(decide(), TeleportWatchdogPolicy()) }
    func testDeadProcessRestarts() { XCTAssertEqual(decide(running: [], listening: []).restart, ["a"]) }
    func testAliveButNotListeningRestarts() { XCTAssertEqual(decide(listening: []).restart, ["a"]) }
    func testNotLoggedInReloginsAndRestartsAll() {
        let p = decide(loggedIn: false)
        XCTAssertTrue(p.relogin)
        XCTAssertEqual(p.restart, ["a"])
    }
    func testThreeFailuresGiveUp() {
        let p = decide(running: [], listening: [], failures: ["a": 3])
        XCTAssertEqual(p.giveUp, ["a"])
        XCTAssertTrue(p.restart.isEmpty)
    }
}
