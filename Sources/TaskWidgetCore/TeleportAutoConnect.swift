import Foundation

public enum TeleportAutoConnect {
    /// 지난번에 켜 둔 터널 중 지금도 설정에 있는 것만, 설정 순서대로. 꺼져 있으면 빈 목록.
    public static func namesToRestore(persisted: [String], configured: [String], enabled: Bool) -> [String] {
        guard enabled else { return [] }
        let p = Set(persisted)
        return configured.filter { p.contains($0) }
    }
}
