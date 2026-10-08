import Foundation

public struct TeleportTunnel: Codable, Equatable, Identifiable {
    public var name: String
    public var dbUser: String
    public var port: Int
    /// teleport.json 에 "group" 으로 적으면 그 이름으로 묶는다. 없으면 이름의 첫 토큰.
    public var groupOverride: String?
    public var id: String { name }

    enum CodingKeys: String, CodingKey { case name, dbUser, port, groupOverride = "group" }

    public init(name: String, dbUser: String = "developer", port: Int) {
        self.name = name
        self.dbUser = dbUser
        self.port = port
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        dbUser = try c.decodeIfPresent(String.self, forKey: .dbUser) ?? "developer"
        port = try c.decode(Int.self, forKey: .port)
        groupOverride = try c.decodeIfPresent(String.self, forKey: .groupOverride)
    }

    public var group: String {
        let g = groupOverride?.trimmingCharacters(in: .whitespaces) ?? ""
        return g.isEmpty ? Self.group(forName: name) : g
    }

    /// 이름의 첫 토큰 대문자 (app-dv → APP).
    public static func group(forName name: String) -> String {
        return name.split(separator: "-").first.map { $0.uppercased() } ?? name.uppercased()
    }
}

public struct TeleportConfig: Codable, Equatable {
    /// 아이디·프록시에서 공백, 줄바꿈, 폭 없는 공백 같은 보이지 않는 문자를 지운다 (복사해 붙이면 섞여 들어온다).
    public static func cleanID(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { u in
            !(u.properties.isWhitespace || u.properties.generalCategory == .format || u.properties.generalCategory == .control)
        }))
    }

    public static let defaultProxy = ""
    public static let basePort = 4306

    public var proxy: String
    public var user: String
    public var tunnels: [TeleportTunnel]

    public init(proxy: String = TeleportConfig.defaultProxy, user: String = "", tunnels: [TeleportTunnel] = []) {
        self.proxy = proxy
        self.user = user
        self.tunnels = tunnels
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proxy = try c.decodeIfPresent(String.self, forKey: .proxy) ?? Self.defaultProxy
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? ""
        tunnels = try c.decodeIfPresent([TeleportTunnel].self, forKey: .tunnels) ?? []
    }

    public static func load(from url: URL = Paths.teleportFile) -> TeleportConfig {
        guard let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(TeleportConfig.self, from: d) else { return TeleportConfig() }
        return c
    }

    public func save(to url: URL = Paths.teleportFile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(self).write(to: url, options: .atomic)
    }

    public static func nextFreePort(startingAt start: Int = basePort, used: Set<Int>) -> Int {
        var p = start
        while used.contains(p) { p += 1 }
        return p
    }

    public static func duplicatePorts(_ tunnels: [TeleportTunnel]) -> Set<Int> {
        var seen = Set<Int>(), dup = Set<Int>()
        for t in tunnels where !seen.insert(t.port).inserted { dup.insert(t.port) }
        return dup
    }
}

/// 비밀번호·OTP 키는 SecretStore 항목 하나(JSON)에 둔다.
public struct TeleportSecrets: Codable, Equatable {
    public static let service = "com.lsm0506.TaskWidget.teleport"
    public static let account = "credentials"

    public var password: String
    public var otpSecret: String

    public init(password: String, otpSecret: String) {
        self.password = password
        self.otpSecret = otpSecret
    }

    public static func load() -> TeleportSecrets? {
        guard let s = SecretStore.get(service: service, account: account),
              let v = try? JSONDecoder().decode(TeleportSecrets.self, from: Data(s.utf8)) else { return nil }
        return v
    }

    public func save() throws {
        let d = try JSONEncoder().encode(self)
        try SecretStore.set(String(decoding: d, as: UTF8.self), service: Self.service, account: Self.account)
    }

    public static func delete() { SecretStore.delete(service: service, account: account) }
}
