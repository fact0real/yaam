import CryptoKit
import Foundation
import Security
import LocalAuthentication

nonisolated protocol CredentialRootKeyStore: Sendable {
    func read() throws -> Data?
    func create(_ proposed: Data) throws -> Data
}

/// This key is a secret in the macOS login Keychain; machine identifiers are never key material.
nonisolated struct MacCredentialRootKeyStore: CredentialRootKeyStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "ASIS.YAAM.ProtectedVault.v1",
         kSecAttrAccount as String: "random-root-key",
         kSecAttrSynchronizable as String: false]
    }
    func read() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw ProtectedCredentialStorage.Failure.keyUnavailable
        }
        return data
    }
    func create(_ proposed: Data) throws -> Data {
        var request = query
        request[kSecValueData as String] = proposed
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(request as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try read() { return existing }
        guard status == errSecSuccess else { throw ProtectedCredentialStorage.Failure.keyUnavailable }
        guard try read() == proposed else { throw ProtectedCredentialStorage.Failure.keyUnavailable }
        return proposed
    }
}

/// The owner serializes access. Tests supply an isolated directory and an in-memory key store.
nonisolated struct ProtectedCredentialStorage {
    enum Failure: LocalizedError {
        case keyUnavailable, unreadableVault
        var errorDescription: String? {
            switch self {
            case .keyUnavailable: return "The credential key is unavailable in the macOS Keychain. Unlock the login Keychain and retry. If its key was removed, restore it or re-enter credentials; the saved vault has been preserved."
            case .unreadableVault: return "The saved credential vault could not be decrypted. It has been preserved; restore the matching key/vault or re-enter credentials in a fresh installation."
            }
        }
    }
    let file: URL
    let keys: any CredentialRootKeyStore
    func load(afterMigration: () -> Void = {}, legacy: () throws -> [String: Data]) throws -> [String: Data] {
        if FileManager.default.fileExists(atPath: file.path) {
            guard let root = try keys.read() else { throw Failure.keyUnavailable }
            return try decode(Data(contentsOf: file), root: root)
        }
        // Decode legacy data before creating anything; corrupt legacy files must never become empty vaults.
        let values = try legacy()
        let root: Data
        if let existing = try keys.read() { root = existing }
        else {
            var random = Data(count: 32)
            let status = random.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
            guard status == errSecSuccess else { throw Failure.keyUnavailable }
            root = try keys.create(random)
        }
        try write(values, root: root)
        afterMigration()
        return values
    }
    static func decodeLegacy(_ data: Data, using keys: [SymmetricKey]) throws -> [String: Data] {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { throw Failure.unreadableVault }
        for key in keys {
            if let clear = try? AES.GCM.open(box, using: key), let values = try? JSONDecoder().decode([String: Data].self, from: clear) { return values }
        }
        throw Failure.unreadableVault
    }
    func save(_ values: [String: Data]) throws {
        guard let root = try keys.read() else { throw Failure.keyUnavailable }
        try write(values, root: root)
    }
    private func decode(_ data: Data, root: Data) throws -> [String: Data] {
        guard root.count == 32,
              let box = try? AES.GCM.SealedBox(combined: data),
              let clear = try? AES.GCM.open(box, using: SymmetricKey(data: root)),
              let values = try? JSONDecoder().decode([String: Data].self, from: clear) else { throw Failure.unreadableVault }
        return values
    }
    private func write(_ values: [String: Data], root: Data) throws {
        guard root.count == 32 else { throw Failure.keyUnavailable }
        let clear = try JSONEncoder().encode(values)
        let box = try AES.GCM.seal(clear, using: SymmetricKey(data: root))
        guard let data = box.combined, try decode(data, root: root) == values else { throw Failure.unreadableVault }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        guard try decode(Data(contentsOf: file), root: root) == values else { throw Failure.unreadableVault }
    }
}

nonisolated struct CredentialSessionGate {
    private(set) var generation = 0
    private(set) var authenticated = false
    func allowsAccess(requiresAuthentication: Bool) -> Bool { !requiresAuthentication || authenticated }
    mutating func lock() { authenticated = false; generation += 1 }
    mutating func completeAuthentication(ticket: Int, success: Bool) -> Bool {
        guard success, ticket == generation else { return false }
        authenticated = true
        return true
    }
}
