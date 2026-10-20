// swiftc -parse-as-library Tests/ProtectedCredentialStorageRegression.swift YAAM/ProtectedCredentialStorage.swift -o /tmp/yaam-protected-vault && /tmp/yaam-protected-vault
import Foundation
import CryptoKit

final class TestKeys: CredentialRootKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    var value: Data?; var denied = false; var creates = 0
    func read() throws -> Data? { lock.lock(); defer { lock.unlock() }; if denied { throw ProtectedCredentialStorage.Failure.keyUnavailable }; return value }
    func create(_ proposed: Data) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if denied { throw ProtectedCredentialStorage.Failure.keyUnavailable }
        if let value { return value }; creates += 1; value = proposed; return proposed
    }
}
@main struct ProtectedCredentialStorageRegression {
    static func main() throws {
        var gate = CredentialSessionGate()
        precondition(gate.allowsAccess(requiresAuthentication: false))
        precondition(!gate.allowsAccess(requiresAuthentication: true))
        precondition(!gate.completeAuthentication(ticket: gate.generation, success: false))
        precondition(!gate.authenticated, "Failed or cancelled authentication cannot unlock the session")
        let pending = gate.generation; gate.lock()
        precondition(!gate.completeAuthentication(ticket: pending, success: true), "A pending authentication cannot undo a later explicit lock")
        precondition(gate.completeAuthentication(ticket: gate.generation, success: true))
        precondition(gate.allowsAccess(requiresAuthentication: true))
        gate.lock(); precondition(!gate.allowsAccess(requiresAuthentication: true))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("vault.dat"), keys = TestKeys()
        let storage = ProtectedCredentialStorage(file: file, keys: keys)
        let fixture = ["test.account": Data("synthetic-test-value".utf8)]
        func rejected(_ operation: () throws -> Void) { do { try operation(); preconditionFailure("Expected refusal") } catch {} }
        let oldRoot = SymmetricKey(data: Data(repeating: 42, count: 32))
        let legacyBytes = try AES.GCM.seal(JSONEncoder().encode(fixture), using: oldRoot).combined!
        var retired = false
        let loaded = try storage.load(afterMigration: { retired = true }) { try ProtectedCredentialStorage.decodeLegacy(legacyBytes, using: [oldRoot]) }; precondition(retired)
        precondition(loaded == fixture && keys.creates == 1 && keys.value?.count == 32)
        let bytes = try Data(contentsOf: file)
        precondition(!bytes.contains(Data("synthetic-test-value".utf8)))
        let reloaded = try storage.load(afterMigration: { preconditionFailure("Never retire sources on an existing v4 load") }) { preconditionFailure("No legacy fallback after migration") }; precondition(reloaded == fixture)
        let publicMetadataKey = SymmetricKey(data: Data(repeating: 42, count: 32))
        rejected { _ = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: publicMetadataKey) }
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        precondition((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let readLock = NSLock()
        var successfulReads = 0
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            if (try? storage.load { [:] }) == fixture { readLock.lock(); successfulReads += 1; readLock.unlock() }
        }
        precondition(successfulReads == 16)
        keys.denied = true
        rejected { _ = try storage.load { [:] } }; rejected { try storage.save([:]) }
        precondition((try? Data(contentsOf: file)) == bytes)
        keys.denied = false
        let savedKey = keys.value; keys.value = nil
        rejected { _ = try storage.load { [:] } }; precondition(keys.creates == 1)
        precondition((try? Data(contentsOf: file)) == bytes)
        keys.value = savedKey
        try storage.save(["changed": Data([1, 2, 3])])
        precondition((try? storage.load { [:] }) == ["changed": Data([1, 2, 3])])
        // Corrupt protected data stays preserved; there is no fallback to a weak legacy root.
        let corrupt = Data([0, 1, 2]); try corrupt.write(to: file)
        rejected { _ = try storage.load { fixture } }; precondition((try? Data(contentsOf: file)) == corrupt)
        try FileManager.default.removeItem(at: file)
        // A failed legacy decode must not create a key or an empty replacement vault.
        retired = false
        rejected { _ = try storage.load(afterMigration: { retired = true }) { throw ProtectedCredentialStorage.Failure.unreadableVault } }
        precondition(!retired)
        precondition(!FileManager.default.fileExists(atPath: file.path))
        // Independent installations get different random roots, with no identifiers or adjacent key files.
        let otherKeys = TestKeys(), other = ProtectedCredentialStorage(file: dir.appendingPathComponent("other.dat"), keys: otherKeys)
        _ = try other.load { fixture }; precondition(otherKeys.value != savedKey)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        precondition(names == ["other.dat"])
        print("PASS protected vault: random secret, migration, recovery, denial/cancellation, corruption preservation, permissions and no plaintext fallback")
    }
}
