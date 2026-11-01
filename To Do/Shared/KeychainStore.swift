import Foundation
import Security

/// Thin wrapper over the iOS Keychain for the handful of secrets this app holds.
///
/// Nothing secret is ever compiled into the binary or committed to the repo —
/// the user types these into Settings once.
///
/// `nonisolated`: the Security framework is thread-safe, and this is read from
/// the token actor as well as the main actor.
nonisolated enum KeychainStore {
    private static let service = "com.matodoapp.compass"

    enum Key: String, CaseIterable {
        case whoopClientID     = "whoop.clientID"
        case whoopClientSecret = "whoop.clientSecret"
        case whoopAccessToken  = "whoop.accessToken"
        case whoopRefreshToken = "whoop.refreshToken"
        case whoopExpiresAt    = "whoop.expiresAt"
    }

    static func set(_ value: String?, for key: Key) {
        // Pasted credentials routinely arrive with a trailing newline or space,
        // which makes OAuth fail with an unhelpful "client authorization" error.
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            delete(key)
            return
        }
        let data = Data(trimmed.utf8)
        var query = baseQuery(for: key)

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        } else {
            query[kSecValueData] = data
            query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    static func get(_ key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        // Trim on read as well, so values stored before trimming existed are
        // also neutralised without needing re-entry.
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func delete(_ key: Key) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    /// Wipes every stored secret.
    static func deleteAll() {
        Key.allCases.forEach(delete)
    }

    private static func baseQuery(for key: Key) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
        ]
    }
}
