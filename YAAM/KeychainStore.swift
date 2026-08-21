//
//  KeychainStore.swift
//  YAAM
//

import Foundation
import LocalAuthentication
import Security

enum SecureCredential: String, CaseIterable {
    case qrzPassword = "qrz.password"
    case qrzAPIKey = "qrz.api-key"
    case lotwPassword = "lotw.password"
    case lotwCertificatePassword = "lotw.certificate-password"
    case hamqthPassword = "hamqth.password"
    case eqslPassword = "eqsl.password"
    case clubLogPassword = "clublog.password"
    case clubLogAPIKey = "clublog.api-key"
    case mobileAPIToken = "mobile-api.token"
    case cloudSyncBookmark = "cloud-sync.bookmark"
    case qrzRankPassword = "qrz-rank.password"
    case smtpPassword = "smtp.password"
    case qrzCookieHeader = "qrz.cookies.header"
    case qrzCookieArchive = "qrz.cookies.archive"
    case logAssistantAPIKey = "log-assistant.api-key"
}

nonisolated enum KeychainStore {
    private final class MemoryCache: @unchecked Sendable {
        private struct Entry {
            let data: Data?
        }

        private let lock = NSLock()
        private var entries: [String: Entry] = [:]

        func value(for account: String) -> (known: Bool, data: Data?) {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[account] else { return (false, nil) }
            return (true, entry.data)
        }

        func store(_ data: Data?, for account: String) {
            lock.lock()
            entries[account] = Entry(data: data)
            lock.unlock()
        }
    }

    private static let service = Bundle.main.bundleIdentifier ?? "ASIS.YAAM"
    private static let cache = MemoryCache()

    static func data(for account: String) -> Data? {
        let cached = cache.value(for: account)
        if cached.known { return cached.data }

        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let data = status == errSecSuccess ? result as? Data : nil
        cache.store(data, for: account)
        return data
    }

    static func dataIfAvailableWithoutPrompt(for account: String) -> Data? {
        let cached = cache.value(for: account)
        if cached.known { return cached.data }

        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            let data = result as? Data
            cache.store(data, for: account)
            return data
        }
        if status == errSecItemNotFound {
            cache.store(nil, for: account)
        }
        return nil
    }

    static func string(for account: String) -> String {
        guard let data = data(for: account) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        set(Data(value.utf8), for: account)
    }

    @discardableResult
    static func set(_ data: Data, for account: String) -> Bool {
        let cached = cache.value(for: account)
        if cached.known, cached.data == data { return true }

        var query = baseQuery(account: account)
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if updateStatus == errSecSuccess {
            cache.store(data, for: account)
            return true
        }
        guard updateStatus == errSecItemNotFound else { return false }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let didSave = SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        if didSave { cache.store(data, for: account) }
        return didSave
    }

    @discardableResult
    static func delete(_ account: String) -> Bool {
        let cached = cache.value(for: account)
        if cached.known, cached.data == nil { return true }

        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        let didDelete = status == errSecSuccess || status == errSecItemNotFound
        if didDelete { cache.store(nil, for: account) }
        return didDelete
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}

nonisolated enum CredentialVault {
    private static let migrationFlag = "secureCredentialMigrationV1"
    private static let legacyKeys: [(SecureCredential, String)] = [
        (.qrzPassword, "qrzPassword"),
        (.qrzAPIKey, "qrzApiKey"),
        (.lotwPassword, "lotwPassword"),
        (.hamqthPassword, "hamqthPassword"),
        (.eqslPassword, "eqslPassword"),
        (.clubLogPassword, "clubLogPassword"),
        (.clubLogAPIKey, "clubLogAPIKey"),
        (.smtpPassword, "smtpPass")
    ]

    static func migrateLegacyCredentials() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationFlag) else { return }
        var completed = true

        for (credential, legacyKey) in legacyKeys {
            let legacyValue = defaults.string(forKey: legacyKey) ?? ""
            guard !legacyValue.isEmpty else {
                defaults.removeObject(forKey: legacyKey)
                continue
            }

            if set(legacyValue, for: credential) {
                defaults.removeObject(forKey: legacyKey)
            } else {
                completed = false
            }
        }

        if let cookieData = defaults.data(forKey: "qrzSessionCookies"), !cookieData.isEmpty {
            if set(cookieData, for: .qrzCookieArchive) {
                defaults.removeObject(forKey: "qrzSessionCookies")
            } else {
                completed = false
            }
        } else {
            defaults.removeObject(forKey: "qrzSessionCookies")
        }

        let cookieHeader = defaults.string(forKey: "qrzSessionCookie") ?? ""
        if !cookieHeader.isEmpty {
            if set(cookieHeader, for: .qrzCookieHeader) {
                defaults.removeObject(forKey: "qrzSessionCookie")
            } else {
                completed = false
            }
        } else {
            defaults.removeObject(forKey: "qrzSessionCookie")
        }

        if completed { defaults.set(true, forKey: migrationFlag) }
    }

    static func value(for credential: SecureCredential) -> String {
        let value = KeychainStore.string(for: credential.rawValue)
        if !value.isEmpty { setPresence(true, account: credential.rawValue) }
        return value
    }

    static func valueIfAvailableWithoutPrompt(for credential: SecureCredential) -> String {
        guard let data = KeychainStore.dataIfAvailableWithoutPrompt(for: credential.rawValue) else { return "" }
        let value = String(data: data, encoding: .utf8) ?? ""
        if !value.isEmpty { setPresence(true, account: credential.rawValue) }
        return value
    }

    static func dataIfAvailableWithoutPrompt(for credential: SecureCredential) -> Data? {
        let value = KeychainStore.dataIfAvailableWithoutPrompt(for: credential.rawValue)
        if value != nil { setPresence(true, account: credential.rawValue) }
        return value
    }

    static func data(for credential: SecureCredential) -> Data? {
        let value = KeychainStore.data(for: credential.rawValue)
        if value != nil { setPresence(true, account: credential.rawValue) }
        return value
    }

    @discardableResult
    static func set(_ value: String, for credential: SecureCredential) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let result = KeychainStore.delete(credential.rawValue)
            if result { setPresence(false, account: credential.rawValue) }
            return result
        }
        let result = KeychainStore.set(trimmed, for: credential.rawValue)
        if result { setPresence(true, account: credential.rawValue) }
        return result
    }

    @discardableResult
    static func set(_ data: Data, for credential: SecureCredential) -> Bool {
        guard !data.isEmpty else {
            let result = KeychainStore.delete(credential.rawValue)
            if result { setPresence(false, account: credential.rawValue) }
            return result
        }
        let result = KeychainStore.set(data, for: credential.rawValue)
        if result { setPresence(true, account: credential.rawValue) }
        return result
    }

    @discardableResult
    static func delete(_ credential: SecureCredential) -> Bool {
        let result = KeychainStore.delete(credential.rawValue)
        if result { setPresence(false, account: credential.rawValue) }
        return result
    }

    static func stationQRZAPIKey(profileID: UUID) -> String {
        let account = stationQRZAccount(profileID: profileID)
        let value = KeychainStore.string(for: account)
        if !value.isEmpty { setPresence(true, account: account) }
        return value
    }

    @discardableResult
    static func setStationQRZAPIKey(_ value: String, profileID: UUID) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = stationQRZAccount(profileID: profileID)
        if trimmed.isEmpty {
            let result = KeychainStore.delete(account)
            if result { setPresence(false, account: account) }
            return result
        }
        let result = KeychainStore.set(trimmed, for: account)
        if result { setPresence(true, account: account) }
        return result
    }

    @discardableResult
    static func deleteStationCredentials(profileID: UUID) -> Bool {
        let account = stationQRZAccount(profileID: profileID)
        let result = KeychainStore.delete(account)
        if result { setPresence(false, account: account) }
        return result
    }

    static func hasStoredValueHint(for credential: SecureCredential) -> Bool {
        UserDefaults.standard.bool(forKey: presenceKey(account: credential.rawValue))
    }

    static func hasStationQRZAPIKeyHint(profileID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: presenceKey(account: stationQRZAccount(profileID: profileID)))
    }

    private static func stationQRZAccount(profileID: UUID) -> String {
        "station.\(profileID.uuidString.lowercased()).qrz-api-key"
    }

    private static func presenceKey(account: String) -> String {
        "secureCredential.present.\(account)"
    }

    private static func setPresence(_ present: Bool, account: String) {
        UserDefaults.standard.set(present, forKey: presenceKey(account: account))
    }

}
