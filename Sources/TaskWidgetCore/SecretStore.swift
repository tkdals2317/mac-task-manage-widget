import Foundation

public enum SecretStorageKind: String {
    case keychain, file
}

public protocol SecretBackend {
    /// 항목이 없으면 nil, 읽기에 실패(취소·거부)하면 throw.
    func get(service: String, account: String) throws -> String?
    func set(_ value: String, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

public struct KeychainBackend: SecretBackend {
    public init() {}
    public func get(service: String, account: String) throws -> String? {
        try Keychain.read(account: account, service: service)
    }
    public func set(_ value: String, service: String, account: String) throws {
        try Keychain.set(value, account: account, service: service)
    }
    public func delete(service: String, account: String) throws {
        Keychain.delete(account: account, service: service)
    }
}

/// `{ "<service>": { "<account>": "<value>" } }` 를 0600 파일 하나에 둔다. 값은 로그에 남기지 않는다.
public struct FileBackend: SecretBackend {
    public let url: URL
    public init(url: URL) { self.url = url }

    private func load() throws -> [String: [String: String]] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: url))
    }

    private func save(_ all: [String: [String: String]]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(all)
        // 임시 파일을 0600 으로 만든 뒤 바꿔치기해서 0644 로 노출되는 순간이 없게 한다.
        let tmp = url.appendingPathExtension("tmp")
        guard fm.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: url)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func get(service: String, account: String) throws -> String? {
        try load()[service]?[account]
    }

    public func set(_ value: String, service: String, account: String) throws {
        var all = try load()
        all[service, default: [:]][account] = value
        try save(all)
    }

    public func delete(service: String, account: String) throws {
        var all = try load()
        guard all[service]?.removeValue(forKey: account) != nil else { return }
        if all[service]?.isEmpty == true { all[service] = nil }
        try save(all)
    }
}

public enum SecretStore {
    public static func backend(for kind: SecretStorageKind) -> SecretBackend {
        switch kind {
        case .keychain: return KeychainBackend()
        case .file: return FileBackend(url: Paths.secretsFile)
        }
    }

    public static var current: SecretBackend {
        backend(for: SecretStorageKind(rawValue: Settings.shared.secretStorage) ?? .keychain)
    }

    public static func get(service: String, account: String) -> String? {
        (try? current.get(service: service, account: account)) ?? nil
    }

    public static func set(_ value: String, service: String, account: String) throws {
        try current.set(value, service: service, account: account)
    }

    public static func delete(service: String, account: String) {
        try? current.delete(service: service, account: account)
    }

    /// 옮길 대상: Jira 토큰(이메일이 있을 때), Teleport 비밀번호·OTP 키.
    public static func knownItems(jiraEmail: String) -> [(service: String, account: String)] {
        var items = [(service: TeleportSecrets.service, account: TeleportSecrets.account)]
        if !jiraEmail.isEmpty { items.append((Keychain.service, jiraEmail)) }
        return items
    }

    /// 전부 읽고 → 새 위치에 쓰고 → 읽어 검증한 뒤 → 이전 위치에서 지운다. 어느 단계든 실패하면 throw (이전 값은 남는다).
    @discardableResult
    public static func migrate(items: [(service: String, account: String)],
                               from old: SecretBackend, to new: SecretBackend) throws -> Int {
        var found: [(service: String, account: String, value: String)] = []
        for i in items {
            if let v = try old.get(service: i.service, account: i.account) { found.append((i.service, i.account, v)) }
        }
        for f in found {
            try new.set(f.value, service: f.service, account: f.account)
            guard try new.get(service: f.service, account: f.account) == f.value else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        for f in found { try old.delete(service: f.service, account: f.account) }
        return found.count
    }
}
