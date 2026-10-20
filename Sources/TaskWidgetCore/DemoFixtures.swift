import Foundation

/// 스크린샷 데모 모드. `ATM_DEMO_FIXTURES` 폴더가 있으면 네트워크·키체인·tsh 대신 거기 JSON 을 쓴다.
public enum DemoFixtures {
    public static var dir: URL? { dir(env: ProcessInfo.processInfo.environment) }
    public static var isOn: Bool { dir != nil }

    static func dir(env: [String: String]) -> URL? {
        guard let p = env["ATM_DEMO_FIXTURES"], !p.isEmpty else { return nil }
        return URL(fileURLWithPath: p, isDirectory: true)
    }

    /// `<dir>/<name>.json` 을 읽는다 (날짜는 ISO8601). 데모가 아니거나 파일이 없거나 깨졌으면 nil.
    public static func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let dir, let data = try? Data(contentsOf: dir.appendingPathComponent("\(name).json")) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(T.self, from: data)
    }
}
