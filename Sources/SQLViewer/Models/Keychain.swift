import Foundation
import Security

/// Connection passwords live in the login keychain, keyed by connection id.
enum Keychain {
    private static let service = "com.edgaropech.SQLViewer"

    static func password(for id: UUID) -> String? {
        var query = baseQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func setPassword(_ password: String, for id: UUID) throws {
        deletePassword(for: id)
        guard !password.isEmpty else { return }
        var item = baseQuery(id)
        item[kSecValueData as String] = Data(password.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func deletePassword(for id: UUID) {
        SecItemDelete(baseQuery(id) as CFDictionary)
    }

    private static func baseQuery(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }
}
