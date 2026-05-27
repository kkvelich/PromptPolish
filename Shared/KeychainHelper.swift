import Foundation
import Security

/// Keychain wrapper with App Group sharing and graceful fallback.
///
/// **Default behavior**: store under App Group so the host app and keyboard extension
/// see the same items. This is what production iOS needs.
///
/// **Fallback behavior**: if App Group access fails (which happens on Mac via
/// "Designed for iPhone" mode, or on simulator with stripped entitlements), fall
/// back to default keychain. The host app still works standalone; the keyboard
/// extension obviously isn't relevant on those targets anyway.
enum KeychainHelper {
    private static let service = "com.velicheti.promptpolish"
    private static let apiKeyAccount = "anthropic-api-key"
    private static let modelAccount = "anthropic-model"

    static func saveAPIKey(_ key: String) {
        save(key, account: apiKeyAccount)
    }

    static func loadAPIKey() -> String? {
        load(account: apiKeyAccount)
    }

    static func deleteAPIKey() {
        delete(account: apiKeyAccount)
    }

    static func saveModel(_ model: String) {
        save(model, account: modelAccount)
    }

    static func loadModel() -> String? {
        load(account: modelAccount)
    }

    private static func baseQuery(account: String, useAppGroup: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if useAppGroup {
            query[kSecAttrAccessGroup as String] = AppGroup.identifier
        }
        return query
    }

    private static func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Try App Group first (shared with keyboard extension).
        var query = baseQuery(account: account, useAppGroup: true)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        var status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            // App Group access denied (Mac "Designed for iPhone", unsigned simulator
            // build, etc.). Fall back to default keychain.
            var fallback = baseQuery(account: account, useAppGroup: false)
            SecItemDelete(fallback as CFDictionary)
            fallback[kSecValueData as String] = data
            status = SecItemAdd(fallback as CFDictionary, nil)
        }
    }

    private static func load(account: String) -> String? {
        // Try App Group first.
        if let value = loadOne(account: account, useAppGroup: true) {
            return value
        }
        // Fall back to default keychain.
        return loadOne(account: account, useAppGroup: false)
    }

    private static func loadOne(account: String, useAppGroup: Bool) -> String? {
        var query = baseQuery(account: account, useAppGroup: useAppGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func delete(account: String) {
        // Delete from both locations to keep things consistent.
        SecItemDelete(baseQuery(account: account, useAppGroup: true) as CFDictionary)
        SecItemDelete(baseQuery(account: account, useAppGroup: false) as CFDictionary)
    }
}
