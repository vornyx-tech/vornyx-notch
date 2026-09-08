//
//  KeychainStore.swift
//  VornyxNotch
//

import Foundation
import Security

/// Minimal keychain wrapper for secrets that must not sit in `UserDefaults`.
///
/// API keys land in the plist in plain text if stored through `Defaults`, and
/// that plist is readable by anything that can read the container - so the
/// Gemini key goes here instead.
enum KeychainStore {
    private static let service = "tech.vornyx.notch"

    static func set(_ value: String, for account: String) {
        guard !value.isEmpty else {
            remove(account)
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8)
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = Data(value.utf8)
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }

        return value
    }

    static func remove(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension KeychainStore {
    static let geminiAPIKeyAccount = "gemini-api-key"

    // Self.get, not get: a bare get( at the start of a body parses as a getter.
    static var geminiAPIKey: String? { Self.get(geminiAPIKeyAccount) }
    static var hasGeminiAPIKey: Bool { geminiAPIKey != nil }
}
