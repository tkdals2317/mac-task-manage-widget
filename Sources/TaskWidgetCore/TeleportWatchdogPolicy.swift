import Foundation

/// 켜 둔 터널을 어떻게 살릴지 정하는 순수 판단. 실제 실행은 TeleportManager 가 한다.
public struct TeleportWatchdogPolicy: Equatable {
    public static let maxFailures = 3

    public var relogin = false
    public var restart: [String] = []
    public var giveUp: [String] = []

    public static func decide(wanted: [String], running: Set<String>, listening: Set<String>,
                              failures: [String: Int], loggedIn: Bool) -> TeleportWatchdogPolicy {
        var p = TeleportWatchdogPolicy()
        p.relogin = !loggedIn && !wanted.isEmpty
        for n in wanted {
            if failures[n, default: 0] >= maxFailures { p.giveUp.append(n); continue }
            // 재로그인하면 기존 터널의 인증서가 낡았으므로 모두 재시작
            if !loggedIn || !running.contains(n) || !listening.contains(n) { p.restart.append(n) }
        }
        return p
    }
}
