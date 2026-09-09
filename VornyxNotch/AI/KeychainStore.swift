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

    /// Which store each account actually lives in, decided at write time.
    private static var usesDataProtection: [String: Bool] = [:]

    private static func baseQuery(_ account: String, dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    /// Writes the secret, reporting whether it actually landed.
    ///
    /// Tries the data protection keychain first and falls back to the legacy
    /// one. The data protection keychain needs a real signing identity: a
    /// locally-built, ad-hoc-signed app has no `application-identifier`
    /// entitlement, so `SecItemAdd` fails with errSecMissingEntitlement and
    /// the save silently did nothing. The legacy keychain has no such
    /// requirement - it just re-prompts whenever the signature changes.
    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        guard !value.isEmpty else {
            remove(account)
            return true
        }

        for dataProtection in [true, false] {
            if write(value, account: account, dataProtection: dataProtection) {
                usesDataProtection[account] = dataProtection
                cache[account] = value
                markStored(account, true)
                return true
            }
        }
        return false
    }

    private static func write(_ value: String, account: String, dataProtection: Bool) -> Bool {
        let query = baseQuery(account, dataProtection: dataProtection)
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = Data(value.utf8)
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    static func get(_ account: String) -> String? {
        // Nothing was ever saved: answer without touching the keychain, so a
        // fresh launch never raises an access prompt.
        guard isStored(account) else { return nil }
        if let cached = cache[account] { return cached }

        // Prefer whichever store the write landed in, then try the other.
        let preferred = usesDataProtection[account] ?? true
        for dataProtection in [preferred, !preferred] {
            if let value = read(account: account, dataProtection: dataProtection) {
                usesDataProtection[account] = dataProtection
                cache[account] = value
                return value
            }
        }

        // Gone, or unreadable. Remember that so we do not ask again.
        cache[account] = String?.none
        markStored(account, false)
        return nil
    }

    private static func read(account: String, dataProtection: Bool) -> String? {
        var query = baseQuery(account, dataProtection: dataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func remove(_ account: String) {
        // Clear both stores: which one holds it depends on how the app was signed.
        SecItemDelete(baseQuery(account, dataProtection: true) as CFDictionary)
        SecItemDelete(baseQuery(account, dataProtection: false) as CFDictionary)

        cache[account] = String?.none
        usesDataProtection[account] = nil
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
