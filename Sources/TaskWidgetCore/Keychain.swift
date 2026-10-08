import Foundation
import Security

public enum KeychainError: Error, Equatable {
    case status(OSStatus)
}

public enum Keychain {
    public static let service = "com.lsm0506.TaskWidget.jira"

    private static func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public static func get(account: String, service: String = Keychain.service) -> String? {
        var q = baseQuery(account: account, service: service)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func set(_ value: String, account: String, service: String = Keychain.service) throws {
        let data = Data(value.utf8)
        let q = baseQuery(account: account, service: service)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public static func delete(account: String, service: String = Keychain.service) {
        SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
    }
}
