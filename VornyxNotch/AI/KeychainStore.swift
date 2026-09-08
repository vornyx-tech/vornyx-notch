//
//  KeychainStore.swift
//  VornyxNotch
//

import Defaults
import Foundation
import Security

/// Keychain wrapper for secrets that must not sit in `UserDefaults`.
///
/// An API key stored through `Defaults` lands in the preferences plist in plain
/// text, readable by anything that can read the container - so the Gemini key
/// goes here instead.
///
/// Two things keep this from nagging the user:
///
/// 1. It uses the **data protection keychain**. The legacy file-based keychain
///    ties each item to the code signature that wrote it, so every rebuild
///    looks like a different app and macOS raises the "wants to use your
///    confidential information" panel. The data protection keychain scopes
///    items to the app's own access group instead, and does not prompt.
/// 2. It never touches the keychain speculatively. A non-secret flag in
///    `Defaults` records whether a key was ever saved, so a fresh install
///    answers "no key" without a single keychain call - and the value is
///    memoised per launch, rather than re-read on every view update.
enum KeychainStore {
    private static let service = "tech.vornyx.notch"

    /// Memoised per launch. `.some(nil)` means "checked, nothing there".
    private static var cache: [String: String?] = [:]

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func set(_ value: String, for account: String) {
        guard !value.isEmpty else {
            remove(account)
            return
        }

        let query = baseQuery(account)
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = Data(value.utf8)
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(insert as CFDictionary, nil)
        }

        guard status == errSecSuccess else { return }
        cache[account] = value
        markStored(account, true)
    }

    static func get(_ account: String) -> String? {
        // Nothing was ever saved: answer without touching the keychain, so a
        // fresh launch never raises an access prompt.
        guard isStored(account) else { return nil }
        if let cached = cache[account] { return cached }

        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else {
            // Gone, or unreadable. Remember that so we do not ask again.
            cache[account] = String?.none
            markStored(account, false)
            return nil
        }

        cache[account] = value
        return value
    }

    static func remove(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
        // Older builds wrote to the legacy keychain; clear that too.
        var legacy = baseQuery(account)
        legacy.removeValue(forKey: kSecUseDataProtectionKeychain as String)
        SecItemDelete(legacy as CFDictionary)

        cache[account] = String?.none
        markStored(account, false)
    }

    // MARK: - Non-secret presence flag

    private static func isStored(_ account: String) -> Bool {
        Defaults[.keychainAccountsInUse].contains(account)
    }

    private static func markStored(_ account: String, _ stored: Bool) {
        var accounts = Defaults[.keychainAccountsInUse]
        if stored { accounts.insert(account) } else { accounts.remove(account) }
        Defaults[.keychainAccountsInUse] = accounts
    }
}

extension KeychainStore {
    static let geminiAPIKeyAccount = "gemini-api-key"

    // Self.get, not get: a bare get( at the start of a body parses as a getter.
    static var geminiAPIKey: String? { Self.get(geminiAPIKeyAccount) }
    static var hasGeminiAPIKey: Bool { isStored(geminiAPIKeyAccount) }
}
