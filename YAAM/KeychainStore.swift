//
//  KeychainStore.swift
//  YAAM
//
//  AES-GCM vault with a random root protected by the macOS Keychain.
//  Touch ID is an optional application-session gate, not a per-item Keychain ACL.
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

// MARK: - Keychain-Protected AES-GCM Vault

nonisolated enum KeychainStore {
    private final class VaultManager: @unchecked Sendable {
        private let lock = NSLock()
        private var memoryVault: [String: Data] = [:]
        private var isLoaded: Bool = false
        private var lastFailure: String?
        private var storage: ProtectedCredentialStorage {
            ProtectedCredentialStorage(file: vaultDirectoryURL.appendingPathComponent("secure_vault.v4.dat"), keys: MacCredentialRootKeyStore())
        }
        func clearSession() {
            lock.lock(); defer { lock.unlock() }
            memoryVault.removeAll(); isLoaded = false
        }
        var failure: String? { lock.lock(); defer { lock.unlock() }; return lastFailure }

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
            guard KeychainStore.isVaultSessionUnlocked else { return }
            ensureLoaded()
        }

        func data(for account: String) -> Data? {
            lock.lock()
            defer { lock.unlock() }
            guard KeychainStore.isVaultSessionUnlocked, ensureLoaded() else { return nil }
            if let inMemory = memoryVault[account] {
                return inMemory
            }
            if !isLegacyMigrationFinished(), let legacyData = queryLegacyKeychain(account: account) {
                memoryVault[account] = legacyData
                guard persistVault() else { memoryVault.removeValue(forKey: account); return nil }
                deleteLegacyKeychainItem(account: account)
                return legacyData
            }
            return nil
        }

        func set(_ data: Data, for account: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard KeychainStore.isVaultSessionUnlocked, ensureLoaded() else { return false }
            let previous = memoryVault
            memoryVault[account] = data
            guard persistVault() else { memoryVault = previous; return false }
            deleteLegacyKeychainItem(account: account)
            return true
        }

        func delete(_ account: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard KeychainStore.isVaultSessionUnlocked, ensureLoaded() else { return false }
            let previous = memoryVault
            guard memoryVault[account] != nil else { return true }
            memoryVault.removeValue(forKey: account)
            guard persistVault() else { memoryVault = previous; return false }
            deleteLegacyKeychainItem(account: account)
            return true
        }

        // MARK: - Protected storage and one-time legacy migration

        @discardableResult private func ensureLoaded() -> Bool {
            guard !isLoaded else { return true }
            do {
                lastFailure = nil
                var retirement: (() -> Void)?
                memoryVault = try storage.load(afterMigration: { retirement?() }) {
                    let plan = try legacyMigrationPlan()
                    retirement = plan.retire
                    return plan.values
                }
                isLoaded = true
                // Existing v4 storage never consults weak files/defaults or repeats their retirement.
                return true
            } catch {
                memoryVault.removeAll(); isLoaded = false; lastFailure = error.localizedDescription
                return false
            }
        }

        private func persistVault() -> Bool {
            do { try storage.save(memoryVault); lastFailure = nil; return true }
            catch { lastFailure = error.localizedDescription; return false }
        }

        private func deriveHardwareBoundKey() -> SymmetricKey? {
            let hwUUID = getHardwareUUID() ?? "YAAM-FALLBACK-MAC-UUID"
            let userHome = NSHomeDirectory()
            let bundleID = Bundle.main.bundleIdentifier ?? "ASIS.YAAM"
            let ikmString = "\(hwUUID):\(userHome):\(bundleID)"
            let ikmData = ikmString.data(using: .utf8) ?? Data("YAAM-ROOT-KEY".utf8)

            guard let salt = try? Data(contentsOf: saltFileURL), salt.count >= 32 else { return nil }

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

        private func deriveAlternateHardwareBoundKey() -> SymmetricKey? {
            let hwUUID = getHardwareUUID() ?? "YAAM-FALLBACK-MAC-UUID"
            let bundleID = Bundle.main.bundleIdentifier ?? "ASIS.YAAM"
            let userHome = FileManager.default.homeDirectoryForCurrentUser.path
            let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
                || NSHomeDirectory().contains("/Library/Containers/")
            let altHome = isSandboxed ? userHome : "\(userHome)/Library/Containers/\(bundleID)/Data"
            let ikmString = "\(hwUUID):\(altHome):\(bundleID)"
            guard let ikmData = ikmString.data(using: .utf8) else { return nil }
            guard let salt = try? Data(contentsOf: saltFileURL), salt.count >= 32 else { return nil }
            let inputKey = SymmetricKey(data: ikmData)
            return HKDF<SHA256>.deriveKey(
                inputKeyMaterial: inputKey,
                salt: salt,
                info: "ASIS.YAAM.HardwareBoundVault.v3".data(using: .utf8)!,
                outputByteCount: 32
            )
        }

        private func legacyMigrationPlan() throws -> (values: [String: Data], retire: () -> Void) {
            let fm = FileManager.default
            var values: [String: Data] = [:]
            var files: [URL] = []
            var defaultsToRemove: [String] = []
            var accountsToRemove = Set<String>()
            var keychainMigrationSucceeded = isLegacyMigrationFinished()
            if fm.fileExists(atPath: vaultFileURL.path) {
                let bytes = try Data(contentsOf: vaultFileURL)
                guard let key = deriveHardwareBoundKey() else { throw ProtectedCredentialStorage.Failure.unreadableVault }
                let keys = [key] + [deriveAlternateHardwareBoundKey()].compactMap { $0 }
                let decoded = try ProtectedCredentialStorage.decodeLegacy(bytes, using: keys)
                values = decoded; files += [vaultFileURL, saltFileURL]
            }
            let bundle = Bundle.main.bundleIdentifier ?? "ASIS.YAAM"
            let home = fm.homeDirectoryForCurrentUser.path
            let sandboxed = NSHomeDirectory().contains("/Library/Containers/") || ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            let siblingHome = sandboxed ? home : "\(home)/Library/Containers/\(bundle)/Data"
            let sibling = URL(fileURLWithPath: siblingHome).appendingPathComponent("Library/Application Support/ASIS.YAAM")
            let oldFile = sibling.appendingPathComponent("secure_vault.dat"), oldSalt = sibling.appendingPathComponent(".vault_salt")
            if oldFile.standardizedFileURL != vaultFileURL.standardizedFileURL,
               let bytes = try? Data(contentsOf: oldFile), let salt = try? Data(contentsOf: oldSalt), salt.count >= 32 {
                let input = Data("\(getHardwareUUID() ?? "YAAM-FALLBACK-MAC-UUID"):\(siblingHome):\(bundle)".utf8)
                let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: input), salt: salt,
                    info: Data("ASIS.YAAM.HardwareBoundVault.v3".utf8), outputByteCount: 32)
                if let decoded = try? ProtectedCredentialStorage.decodeLegacy(bytes, using: [key]) {
                    for (account, value) in decoded where values[account] == nil { values[account] = value }
                    files += [oldFile, oldSalt]
                }
            }
            let defaults = UserDefaults.standard
            let legacyKeys: [(SecureCredential, String)] = [(.qrzPassword,"qrzPassword"), (.qrzAPIKey,"qrzApiKey"),
                (.lotwPassword,"lotwPassword"), (.hamqthPassword,"hamqthPassword"), (.eqslPassword,"eqslPassword"),
                (.clubLogPassword,"clubLogPassword"), (.clubLogAPIKey,"clubLogAPIKey"), (.smtpPassword,"smtpPass"),
                (.qrzCookieHeader,"qrzSessionCookie")]
            for (credential, name) in legacyKeys {
                if let text = defaults.string(forKey: name), !text.isEmpty {
                    if values[credential.rawValue] == nil { values[credential.rawValue] = Data(text.utf8) }
                    defaultsToRemove.append(name)
                }
            }
            if let data = defaults.data(forKey: "qrzSessionCookies") {
                if values[SecureCredential.qrzCookieArchive.rawValue] == nil { values[SecureCredential.qrzCookieArchive.rawValue] = data }
                defaultsToRemove.append("qrzSessionCookies")
            }
            if !isLegacyMigrationFinished() {
                keychainMigrationSucceeded = true
                for service in Set([bundle, "ASIS.YAAM"]) {
                    let context = LAContext(); context.interactionNotAllowed = true
                    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: service, kSecReturnAttributes as String: true,
                        kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitAll,
                        kSecUseAuthenticationContext as String: context]
                    var result: CFTypeRef?
                    let status = SecItemCopyMatching(query as CFDictionary, &result)
                    if status != errSecSuccess && status != errSecItemNotFound { keychainMigrationSucceeded = false }
                    let items = (result as? [[String: Any]]) ?? (result as? [String: Any]).map { [$0] } ?? []
                    for item in items {
                        guard let account = item[kSecAttrAccount as String] as? String,
                              account != "ASIS.YAAM.MasterVaultKey", let data = item[kSecValueData as String] as? Data else { continue }
                        if values[account] == nil { values[account] = data }
                        accountsToRemove.insert(account)
                    }
                }
            }
            return (values, { [self] in
                for file in files where fm.fileExists(atPath: file.path) {
                    do { try fm.removeItem(at: file) }
                    catch { lastFailure = "The protected vault was saved, but a legacy credential copy could not be removed. Check the app's Application Support folder permissions." }
                }
                for name in defaultsToRemove { defaults.removeObject(forKey: name) }
                for account in accountsToRemove { deleteLegacyKeychainItem(account: account) }
                if keychainMigrationSucceeded { markLegacyMigrationFinished() }
            })
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
                var request = query
                let context = LAContext(); context.interactionNotAllowed = true
                request[kSecUseAuthenticationContext as String] = context
                var result: CFTypeRef?
                let status = SecItemCopyMatching(request as CFDictionary, &result)
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


    }

    private static let vault = VaultManager()
    public static var storageFailure: String? { vault.failure }

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
            lockSession()
        }
    }

    private static let sessionLock = NSLock()
    private static var sessionGate = CredentialSessionGate()

    public static var isVaultSessionUnlocked: Bool {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return sessionGate.allowsAccess(requiresAuthentication: isBiometricLockEnabled)
    }

    private static func completeAuthentication(ticket: Int, success: Bool) -> Bool {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return sessionGate.completeAuthentication(ticket: ticket, success: success)
    }

    public static func lockSession() {
        sessionLock.lock()
        sessionGate.lock()
        sessionLock.unlock()
        vault.clearSession()
    }

    @discardableResult
    public static func authenticateWithBiometrics(
        reason: String = "Scan your fingerprint to securely unlock YAAM radio credentials"
    ) async -> Bool {
        let ticket = sessionLock.withLock { sessionGate.generation }
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: reason
                )
                let granted = completeAuthentication(ticket: ticket, success: success)
                if granted { prewarm() }
                return granted
            } catch {
                return false
            }
        } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: reason
                )
                let granted = completeAuthentication(ticket: ticket, success: success)
                if granted { prewarm() }
                return granted
            } catch {
                return false
            }
        }

        return false
    }

    // MARK: - Session-gated credential access

    public static func prewarm() {
        guard isVaultSessionUnlocked else { return }
        vault.prewarm()
    }

    public static func data(for account: String) -> Data? {
        guard isVaultSessionUnlocked else { return nil }
        return vault.data(for: account)
    }

    public static func dataIfAvailableWithoutPrompt(for account: String) -> Data? {
        guard isVaultSessionUnlocked else { return nil }
        return vault.data(for: account)
    }

    public static func string(for account: String) -> String {
        guard isVaultSessionUnlocked else { return "" }
        guard let d = vault.data(for: account) else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }

    @discardableResult
    public static func set(_ value: String, for account: String) -> Bool {
        set(Data(value.utf8), for: account)
    }

    @discardableResult
    public static func set(_ data: Data, for account: String) -> Bool {
        guard isVaultSessionUnlocked else { return false }
        return vault.set(data, for: account)
    }

    @discardableResult
    public static func delete(_ account: String) -> Bool {
        guard isVaultSessionUnlocked else { return false }
        return vault.delete(account)
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

    /// When a credential was last saved: only the time, never the value. Sync queues again the uploads that a
    /// service's rejected credentials blocked once they are saved again (AppState.qslCredentialsChangedAt).
    static func changedAt(_ credential: SecureCredential) -> Date? {
        UserDefaults.standard.object(forKey: changedAtKey(account: credential.rawValue)) as? Date
    }

    static func stationQRZAPIKeyChangedAt(profileID: UUID) -> Date? {
        UserDefaults.standard.object(forKey: changedAtKey(account: stationQRZAccount(profileID: profileID))) as? Date
    }

    private static func changedAtKey(account: String) -> String { "credentialVault.changedAt." + account }

    private static func markChanged(account: String) {
        UserDefaults.standard.set(Date(), forKey: changedAtKey(account: account))
    }

    @discardableResult
    static func set(_ value: String, for credential: SecureCredential) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let result = KeychainStore.delete(credential.rawValue)
            if result { setPresence(false, account: credential.rawValue); markChanged(account: credential.rawValue) }
            return result
        }
        let result = KeychainStore.set(trimmed, for: credential.rawValue)
        if result { setPresence(true, account: credential.rawValue); markChanged(account: credential.rawValue) }
        return result
    }

    @discardableResult
    static func set(_ data: Data, for credential: SecureCredential) -> Bool {
        guard !data.isEmpty else {
            let result = KeychainStore.delete(credential.rawValue)
            if result { setPresence(false, account: credential.rawValue); markChanged(account: credential.rawValue) }
            return result
        }
        let result = KeychainStore.set(data, for: credential.rawValue)
        if result { setPresence(true, account: credential.rawValue); markChanged(account: credential.rawValue) }
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
            if result { setPresence(false, account: account); markChanged(account: account) }
            return result
        }
        let result = KeychainStore.set(trimmed, for: account)
        if result { setPresence(true, account: account); markChanged(account: account) }
        return result
    }

    @discardableResult
    static func deleteStationCredentials(profileID: UUID) -> Bool {
        let account = stationQRZAccount(profileID: profileID)
        let result = KeychainStore.delete(account)
        if result { setPresence(false, account: account) }
        return result
    }

    /// QRZ Logbook API key for a station profile (`stationID` is `activeStationProfileID.uuidString`):
    /// the profile's own key, else the global one. Resolved at send time, never persisted in queues.
    static func qrzLogbookKey(
        stationID: String?,
        stationKey: (UUID) -> String = { stationQRZAPIKey(profileID: $0) },
        globalKey: () -> String = { value(for: .qrzAPIKey) }
    ) -> String {
        if let sid = stationID, let profileID = UUID(uuidString: sid) {
            let profileKey = stationKey(profileID).trimmingCharacters(in: .whitespacesAndNewlines)
            if !profileKey.isEmpty { return profileKey }
        }
        return globalKey().trimmingCharacters(in: .whitespacesAndNewlines)
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
