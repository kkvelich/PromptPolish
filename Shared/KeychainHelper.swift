import Foundation
import Security

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

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: AppGroup.identifier,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
    }

    private static func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        var query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func load(account: String) -> String? {
        var query = baseQuery(account: account)
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
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
