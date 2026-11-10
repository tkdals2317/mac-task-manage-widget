import Foundation

public struct TeleportTunnel: Codable, Equatable, Identifiable {
    /// db = `tsh proxy db --tunnel`, app = `tsh proxy app` (HTTP 앱, 인증 헤더는 Teleport 가 넣는다).
    public enum Kind: String, Codable { case db, app }

    public var name: String
    /// app 은 쓰지 않는다 (`tsh proxy app` 에는 DB 사용자가 없다).
    public var dbUser: String
    public var port: Int
    /// teleport.json 에 "group" 으로 적으면 그 이름으로 묶는다. 없으면 이름의 첫 토큰.
    public var groupOverride: String?
    public var kind: Kind
    public var id: String { name }

    enum CodingKeys: String, CodingKey { case name, dbUser, port, groupOverride = "group", kind }

    public init(name: String, dbUser: String = "developer", port: Int, kind: Kind = .db) {
        self.name = name
        self.dbUser = dbUser
        self.port = port
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        dbUser = try c.decodeIfPresent(String.self, forKey: .dbUser) ?? "developer"
        port = try c.decode(Int.self, forKey: .port)
        groupOverride = try c.decodeIfPresent(String.self, forKey: .groupOverride)
        // kind 가 생기기 전에 저장한 teleport.json 은 모두 DB 터널이다.
        // 손으로 고친 오타나 모르는 값도 db 로 읽는다 (던지면 teleport.json 전체가 빈 설정으로 읽힌다).
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .db
    }

    // db 항목은 kind 를 적지 않아 기존 teleport.json 과 같은 모양으로 저장하고, app 은 dbUser 를 적지 않는다.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(port, forKey: .port)
        try c.encodeIfPresent(groupOverride, forKey: .groupOverride)
        switch kind {
        case .db: try c.encode(dbUser, forKey: .dbUser)
        case .app: try c.encode(kind, forKey: .kind)
        }
    }

    /// 터널을 띄우는 tsh 인자.
    public var proxyArguments: [String] {
        switch kind {
        case .db: return ["proxy", "db", "--tunnel", name, "--db-user", dbUser, "--port", String(port)]
        case .app: return ["proxy", "app", name, "--port", String(port)]
        }
    }

    /// 끊을 때 이 리소스의 인증서를 지우는 tsh 인자.
    public var logoutArguments: [String] {
        switch kind {
        case .db: return ["db", "logout", name]
        case .app: return ["apps", "logout", name]
        }
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
