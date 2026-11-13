import Foundation
import Security

enum KeychainStore {
    private static let service = "com.wristex.watch.credentials"

    static func read(_ account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }

        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            status = SecItemAdd(item as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            }
        }
        return status == errSecSuccess
    }
}
