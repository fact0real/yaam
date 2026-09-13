//
//  KeychainStore.swift
//  YAAM
//
//  Hardware-Bound AES-256-GCM Secure Vault Engine & Biometric Authentication
//  Eliminates ALL macOS Keychain prompts by deriving a 256-bit cryptographic key bound
//  directly to the local machine hardware (IOPlatformUUID) and user account.
//

import CryptoKit
import Foundation
import IOKit
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
    case clubLogCookieHeader = "clublog.cookies.header"
    case clubLogCookieArchive = "clublog.cookies.archive"
    case mobileAPIToken = "mobile-api.token"
    case cloudSyncBookmark = "cloud-sync.bookmark"
    case qrzRankPassword = "qrz-rank.password"
    case qrzRankAPIToken = "qrz-rank.api-token"
    case smtpPassword = "smtp.password"
    case qrzCookieHeader = "qrz.cookies.header"
    case qrzCookieArchive = "qrz.cookies.archive"
    case logAssistantAPIKey = "log-assistant.api-key"
    case icomNetworkPassword = "icom-network.password"
    case wavelogAPIKey = "wavelog.api-key"
    case hrdlogCode = "hrdlog.upload-code"
}

// MARK: - Hardware-Bound AES-256-GCM Secure Vault Engine

nonisolated enum KeychainStore {
    private final class VaultManager: @unchecked Sendable {
        private let lock = NSLock()
        private var memoryVault: [String: Data] = [:]
        private var isLoaded: Bool = false
        private var masterKey: SymmetricKey?

        private var vaultDirectoryURL: URL {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let dir = appSupport.appendingPathComponent("ASIS.YAAM", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        private var vaultFileURL: URL {
            vaultDirectoryURL.appendingPathComponent("secure_vault.dat")
        }

        private var saltFileURL: URL {
            vaultDirectoryURL.appendingPathComponent(".vault_salt")
        }

        private static let legacyMigrationFlagKey = "ASIS.YAAM.LegacyKeychainMigrationFinished_v2"

        private func isLegacyMigrationFinished() -> Bool {
            UserDefaults.standard.bool(forKey: Self.legacyMigrationFlagKey)
        }

        private func markLegacyMigrationFinished() {
            UserDefaults.standard.set(true, forKey: Self.legacyMigrationFlagKey)
        }

        func prewarm() {
            lock.lock()
            defer { lock.unlock() }
            ensureLoaded()
        }

        func data(for account: String) -> Data? {
            lock.lock()
            defer { lock.unlock() }
            ensureLoaded()
            if let inMemory = memoryVault[account] {
                return inMemory
            }
            if !isLegacyMigrationFinished(), let legacyData = queryLegacyKeychain(account: account) {
                memoryVault[account] = legacyData
                _ = persistVault()
                deleteLegacyKeychainItem(account: account)
                return legacyData
            }
            return nil
        }

        func set(_ data: Data, for account: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            ensureLoaded()
            memoryVault[account] = data
            deleteLegacyKeychainItem(account: account)
            return persistVault()
        }

        func delete(_ account: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            ensureLoaded()
            deleteLegacyKeychainItem(account: account)
            guard memoryVault[account] != nil else { return true }
            memoryVault.removeValue(forKey: account)
            return persistVault()
        }

        // MARK: - Cryptographic Key Derivation & Hardware Binding

        private func ensureLoaded() {
            guard !isLoaded else { return }
            isLoaded = true

            // 1. Derive machine-bound 256-bit symmetric key
            let key = deriveHardwareBoundKey()
            self.masterKey = key

            // 2. Read and decrypt vault file if present
            if let fileData = try? Data(contentsOf: vaultFileURL), !fileData.isEmpty {
                if let sealedBox = try? AES.GCM.SealedBox(combined: fileData),
                   let decryptedData = try? AES.GCM.open(sealedBox, using: key),
                   let dictionary = try? JSONDecoder().decode([String: Data].self, from: decryptedData) {
                    self.memoryVault = dictionary
                    migrateFromUserDefaultsSilently()
                    if !isLegacyMigrationFinished() {
                        migrateFromLegacyKeychainSilently()
                    }
                    return
                }
            }

            // 3. Fallback migrations if fresh or empty
            migrateFromUserDefaultsSilently()
            if !isLegacyMigrationFinished() {
                migrateFromLegacyKeychainSilently()
            }
        }

        private func persistVault() -> Bool {
            let key = masterKey ?? deriveHardwareBoundKey()
            self.masterKey = key

            guard let jsonData = try? JSONEncoder().encode(memoryVault) else { return false }
            guard let sealedBox = try? AES.GCM.seal(jsonData, using: key),
                  let combined = sealedBox.combined else { return false }

            do {
                try combined.write(to: vaultFileURL, options: .atomic)
                #if os(macOS)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: vaultFileURL.path)
                #endif
                return true
            } catch {
                return false
            }
        }

        private func deriveHardwareBoundKey() -> SymmetricKey {
            let hwUUID = getHardwareUUID() ?? "YAAM-FALLBACK-MAC-UUID"
            let userHome = NSHomeDirectory()
            let bundleID = Bundle.main.bundleIdentifier ?? "ASIS.YAAM"
            let ikmString = "\(hwUUID):\(userHome):\(bundleID)"
            let ikmData = ikmString.data(using: .utf8) ?? Data("YAAM-ROOT-KEY".utf8)

            var salt = (try? Data(contentsOf: saltFileURL)) ?? Data()
            if salt.count < 32 {
                var randomBytes = [UInt8](repeating: 0, count: 32)
                _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
                salt = Data(randomBytes)
                try? salt.write(to: saltFileURL, options: .atomic)
                #if os(macOS)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: saltFileURL.path)
                #endif
            }

            let inputKey = SymmetricKey(data: ikmData)
            return HKDF<SHA256>.deriveKey(
                inputKeyMaterial: inputKey,
                salt: salt,
                info: "ASIS.YAAM.HardwareBoundVault.v3".data(using: .utf8)!,
                outputByteCount: 32
            )
        }

        private func getHardwareUUID() -> String? {
            let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
            guard platformExpert != 0 else { return nil }
            defer { IOObjectRelease(platformExpert) }
            guard let property = IORegistryEntryCreateCFProperty(platformExpert, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0) else {
                return nil
            }
            return property.takeRetainedValue() as? String
        }

        private func migrateFromUserDefaultsSilently() {
            let defaults = UserDefaults.standard
            var found = false

            let legacyKeys: [(SecureCredential, String)] = [
                (.qrzPassword, "qrzPassword"),
                (.qrzAPIKey, "qrzApiKey"),
                (.lotwPassword, "lotwPassword"),
                (.hamqthPassword, "hamqthPassword"),
                (.eqslPassword, "eqslPassword"),
                (.clubLogPassword, "clubLogPassword"),
                (.clubLogAPIKey, "clubLogAPIKey"),
                (.smtpPassword, "smtpPass")
            ]

            for (cred, legacyKey) in legacyKeys {
                if let val = defaults.string(forKey: legacyKey), !val.isEmpty {
                    self.memoryVault[cred.rawValue] = Data(val.utf8)
                    found = true
                    defaults.removeObject(forKey: legacyKey)
                }
            }

            if let cookieData = defaults.data(forKey: "qrzSessionCookies"), !cookieData.isEmpty {
                self.memoryVault[SecureCredential.qrzCookieArchive.rawValue] = cookieData
                found = true
                defaults.removeObject(forKey: "qrzSessionCookies")
            }

            if let cookieHeader = defaults.string(forKey: "qrzSessionCookie"), !cookieHeader.isEmpty {
                self.memoryVault[SecureCredential.qrzCookieHeader.rawValue] = Data(cookieHeader.utf8)
                found = true
                defaults.removeObject(forKey: "qrzSessionCookie")
            }

            if found {
                _ = persistVault()
            }
        }

        private func queryLegacyKeychain(account: String) -> Data? {
            let services = [Bundle.main.bundleIdentifier, "ASIS.YAAM"].compactMap { $0 }
            for service in Set(services) {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ]
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                if status == errSecSuccess, let data = result as? Data, !data.isEmpty {
                    return data
                }
            }
            return nil
        }

        private func deleteLegacyKeychainItem(account: String) {
            let services = [Bundle.main.bundleIdentifier, "ASIS.YAAM"].compactMap { $0 }
            for service in Set(services) {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account
                ]
                SecItemDelete(query as CFDictionary)
            }
        }

        private func migrateFromLegacyKeychainSilently() {
            guard !isLegacyMigrationFinished() else { return }
            markLegacyMigrationFinished()

            let services = [Bundle.main.bundleIdentifier, "ASIS.YAAM"].compactMap { $0 }
            var foundAny = false
            var migratedAccounts: [String] = []

            for service in Set(services) {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecReturnAttributes as String: true,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitAll
                ]
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                if status == errSecSuccess {
                    let items: [[String: Any]]
                    if let array = result as? [[String: Any]] {
                        items = array
                    } else if let dict = result as? [String: Any] {
                        items = [dict]
                    } else {
                        items = []
                    }

                    for item in items {
                        if let account = item[kSecAttrAccount as String] as? String,
                           let data = item[kSecValueData as String] as? Data,
                           !account.isEmpty,
                           !data.isEmpty,
                           account != "ASIS.YAAM.MasterVaultKey" {
                            if memoryVault[account] == nil {
                                memoryVault[account] = data
                                foundAny = true
                            }
                            migratedAccounts.append(account)
                        }
                    }
                }
            }

            for cred in SecureCredential.allCases {
                if memoryVault[cred.rawValue] == nil,
                   let data = queryLegacyKeychain(account: cred.rawValue) {
                    memoryVault[cred.rawValue] = data
                    foundAny = true
                    migratedAccounts.append(cred.rawValue)
                }
            }

            if foundAny {
                _ = persistVault()
            }

            for account in Set(migratedAccounts) {
                deleteLegacyKeychainItem(account: account)
            }
        }
    }

    private static let vault = VaultManager()

    // MARK: - Biometric & Touch ID Capabilities

    public static var isBiometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    public static var isDevicePasscodeAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    public static var biometryTypeDescription: String {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .touchID:
                return "Touch ID"
            case .faceID:
                return "Face ID"
            case .opticID:
                return "Optic ID"
            case .none:
                return "None"
            @unknown default:
                return "Touch ID"
            }
        } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            return "Mac Password"
        }
        return "None"
    }

    private static let biometricLockPreferenceKey = "yaam.security.requireBiometrics"

    public static var isBiometricLockEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: biometricLockPreferenceKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: biometricLockPreferenceKey)
        }
    }

    private static let sessionLock = NSLock()
    private static var _isVaultSessionUnlocked: Bool = false

    public static var isVaultSessionUnlocked: Bool {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if !isBiometricLockEnabled {
            return true
        }
        return _isVaultSessionUnlocked
    }

    public static func markSessionUnlocked() {
        sessionLock.lock()
        _isVaultSessionUnlocked = true
        sessionLock.unlock()
    }

    public static func lockSession() {
        sessionLock.lock()
        _isVaultSessionUnlocked = false
        sessionLock.unlock()
    }

    @discardableResult
    public static func authenticateWithBiometrics(
        reason: String = "Scan your fingerprint to securely unlock YAAM radio credentials"
    ) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: reason
                )
                if success {
                    markSessionUnlocked()
                    vault.prewarm()
                }
                return success
            } catch {
                return false
            }
        } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: reason
                )
                if success {
                    markSessionUnlocked()
                    vault.prewarm()
                }
                return success
            } catch {
                return false
            }
        }

        markSessionUnlocked()
        vault.prewarm()
        return true
    }

    // MARK: - Public API (Zero-Prompt In-Memory Access)

    public static func prewarm() {
        vault.prewarm()
    }

    public static func data(for account: String) -> Data? {
        vault.data(for: account)
    }

    public static func dataIfAvailableWithoutPrompt(for account: String) -> Data? {
        vault.data(for: account)
    }

    public static func string(for account: String) -> String {
        guard let d = vault.data(for: account) else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }

    @discardableResult
    public static func set(_ value: String, for account: String) -> Bool {
        set(Data(value.utf8), for: account)
    }

    @discardableResult
    public static func set(_ data: Data, for account: String) -> Bool {
        vault.set(data, for: account)
    }

    @discardableResult
    public static func delete(_ account: String) -> Bool {
        vault.delete(account)
    }
}

// MARK: - CredentialVault

nonisolated enum CredentialVault {
    static func prewarm() {
        KeychainStore.prewarm()
    }

    static func migrateLegacyCredentials() {
        KeychainStore.prewarm()
    }

    static var isBiometricsAvailable: Bool {
        KeychainStore.isBiometricsAvailable
    }

    static var isDevicePasscodeAvailable: Bool {
        KeychainStore.isDevicePasscodeAvailable
    }

    static var biometryTypeDescription: String {
        KeychainStore.biometryTypeDescription
    }

    static var isBiometricLockEnabled: Bool {
        get { KeychainStore.isBiometricLockEnabled }
        set { KeychainStore.isBiometricLockEnabled = newValue }
    }

    static var isVaultSessionUnlocked: Bool {
        KeychainStore.isVaultSessionUnlocked
    }

    @discardableResult
    static func authenticateWithBiometrics(
        reason: String = "Scan your fingerprint to securely unlock YAAM radio credentials"
    ) async -> Bool {
        await KeychainStore.authenticateWithBiometrics(reason: reason)
    }

    static func value(for credential: SecureCredential) -> String {
        let value = KeychainStore.string(for: credential.rawValue)
        if !value.isEmpty { setPresence(true, account: credential.rawValue) }
        return value
    }

    static func valueIfAvailableWithoutPrompt(for credential: SecureCredential) -> String {
        let value = KeychainStore.string(for: credential.rawValue)
        if !value.isEmpty { setPresence(true, account: credential.rawValue) }
        return value
    }

    static func dataIfAvailableWithoutPrompt(for credential: SecureCredential) -> Data? {
        let value = KeychainStore.data(for: credential.rawValue)
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
        if UserDefaults.standard.bool(forKey: presenceKey(account: credential.rawValue)) {
            return true
        }
        return !KeychainStore.string(for: credential.rawValue).isEmpty
    }

    static func hasStationQRZAPIKeyHint(profileID: UUID) -> Bool {
        let account = stationQRZAccount(profileID: profileID)
        if UserDefaults.standard.bool(forKey: presenceKey(account: account)) {
            return true
        }
        return !KeychainStore.string(for: account).isEmpty
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
