//
//  SecureVaultRegression.swift
//  YAAM Tests
//

import CryptoKit
import Foundation
import IOKit

func getHardwareUUIDTest() -> String? {
    let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    guard platformExpert != 0 else { return nil }
    defer { IOObjectRelease(platformExpert) }
    guard let property = IORegistryEntryCreateCFProperty(platformExpert, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0) else {
        return nil
    }
    return property.takeRetainedValue() as? String
}

func deriveHardwareKeyTest(salt: Data) -> SymmetricKey {
    let hwUUID = getHardwareUUIDTest() ?? "TEST-HW-UUID"
    let userHome = NSHomeDirectory()
    let bundleID = "ASIS.YAAM"
    let ikm = "\(hwUUID):\(userHome):\(bundleID)".data(using: .utf8)!
    let inputKey = SymmetricKey(data: ikm)
    return HKDF<SHA256>.deriveKey(
        inputKeyMaterial: inputKey,
        salt: salt,
        info: "ASIS.YAAM.HardwareBoundVault.v3".data(using: .utf8)!,
        outputByteCount: 32
    )
}

@main
struct SecureVaultRegression {
    static func main() {
        print("Running Hardware-Bound Secure Vault & Zero-Prompt Cryptography Tests...")

        testHardwareUUIDRetrieval()
        testHardwareBoundKeyDerivationAndEncryption()

        print("All Hardware-Bound Secure Vault Regression Tests PASSED successfully!")
    }

    private static func testHardwareUUIDRetrieval() {
        let uuid = getHardwareUUIDTest()
        precondition(uuid != nil && !uuid!.isEmpty, "Failed to retrieve hardware UUID")
        print("Verified Hardware UUID: \(uuid!)")
    }

    private static func testHardwareBoundKeyDerivationAndEncryption() {
        let salt = Data([UInt8](repeating: 42, count: 32))
        let key1 = deriveHardwareKeyTest(salt: salt)
        let key2 = deriveHardwareKeyTest(salt: salt)

        // Keys derived with same hardware parameters and salt must match identically
        let keyData1 = key1.withUnsafeBytes { Data($0) }
        let keyData2 = key2.withUnsafeBytes { Data($0) }
        precondition(keyData1 == keyData2, "Key derivation is non-deterministic")

        // Encrypt test credentials
        let testCredentials: [String: Data] = [
            "qrz.password": Data("MyQRZPassSecret#1".utf8),
            "lotw.password": Data("LoTWPassCert#2".utf8),
            "smtp.password": Data("SMTPMailSecret#3".utf8),
            "station.profile.qrz-api-key": Data("XYZ-999-ABC".utf8)
        ]

        let encoded = try! JSONEncoder().encode(testCredentials)
        let sealed = try! AES.GCM.seal(encoded, using: key1)
        let combined = sealed.combined!

        // Decrypt with key2
        let openedBox = try! AES.GCM.SealedBox(combined: combined)
        let decrypted = try! AES.GCM.open(openedBox, using: key2)
        let restored = try! JSONDecoder().decode([String: Data].self, from: decrypted)

        precondition(restored.count == 4)
        precondition(String(data: restored["qrz.password"]!, encoding: .utf8) == "MyQRZPassSecret#1")
        precondition(String(data: restored["lotw.password"]!, encoding: .utf8) == "LoTWPassCert#2")
        precondition(String(data: restored["smtp.password"]!, encoding: .utf8) == "SMTPMailSecret#3")
        precondition(String(data: restored["station.profile.qrz-api-key"]!, encoding: .utf8) == "XYZ-999-ABC")
    }
}
