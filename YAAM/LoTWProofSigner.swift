import Foundation
import Security
import CryptoKit

nonisolated struct LoTWProofChallenge: Codable, Sendable {
    let challengeID: String
    let payload: String
    let expiresAt: String
    enum CodingKeys: String, CodingKey {
        case payload
        case challengeID = "challenge_id", expiresAt = "expires_at"
    }
}

nonisolated struct LoTWPublicProof: Sendable {
    let certificate: String
    let signature: String
}

nonisolated struct LoTWProofResult: Decodable, Sendable {
    let verifiedCallsign: String
    let enabled: Bool
    enum CodingKeys: String, CodingKey { case enabled; case verifiedCallsign = "verified_callsign" }
}

nonisolated enum LoTWProofError: LocalizedError {
    case importFailed, unsupportedKey, invalidChallenge
    var errorDescription: String? {
        switch self {
        case .importFailed: return "Cannot open this certificate backup. Check the PKCS#12 file and its password. No key was saved."
        case .unsupportedKey: return "This certificate needs an RSA key of at least 2,048 bits and SHA-256 signing support. Use administrator review for an older certificate."
        case .invalidChallenge: return "The verification challenge is invalid or expired. Start again."
        }
    }
}

/// The server's text is untrusted input. Sign only this exact purpose/host/schema,
/// never arbitrary text and never a log/QSO payload. No key or password is encoded.
nonisolated enum LoTWProofContract {
    static func validate(_ challenge: LoTWProofChallenge, call: String, fingerprint: String, now: Date = Date()) throws {
        guard challenge.challengeID.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              challenge.payload.utf8.count <= 1024, SKEDMessagingContract.validCallsign(call),
              fingerprint.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw LoTWProofError.invalidChallenge
        }
        let lines = challenge.payload.components(separatedBy: "\n")
        let date = ISO8601DateFormatter().date(from: challenge.expiresAt)
        guard lines.count == 8,
              lines[0] == "YAAM LoTW callsign proof v1",
              lines[1] == "origin=https://qrz-rank.asis.sh",
              lines[2].range(of: "^user=[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
              lines[3] == "callsign=\(call)", lines[4] == "certificate_sha256=\(fingerprint)",
              lines[5] == "nonce=\(challenge.challengeID)", lines[6] == "expires=\(challenge.expiresAt)",
              lines[7] == "",
              let date, date > now, date.timeIntervalSince(now) <= 310 else {
            throw LoTWProofError.invalidChallenge
        }
    }
}

actor LoTWProofSigner {
    private var key: SecKey?
    private var certificate: Data?
    private var fingerprint = ""

    func clear() { key = nil; certificate = nil; fingerprint = "" }

    func load(url: URL, password: String) throws -> String {
        clear()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL else { throw LoTWProofError.importFailed }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = try handle.read(upToCount: 1024 * 1024 + 1) ?? Data()
        defer { data.resetBytes(in: data.startIndex..<data.endIndex) }
        guard !data.isEmpty, data.count <= 1024 * 1024 else { throw LoTWProofError.importFailed }
        var items: CFArray?
        let options = [kSecImportExportPassphrase as String: password,
                       kSecImportToMemoryOnly as String: true] as CFDictionary
        guard SecPKCS12Import(data as CFData, options, &items) == errSecSuccess,
              let entries = items as? [[String: Any]], entries.count == 1,
              let raw = entries[0][kSecImportItemIdentity as String],
              CFGetTypeID(raw as CFTypeRef) == SecIdentityGetTypeID() else { throw LoTWProofError.importFailed }
        let identity = raw as! SecIdentity
        var cert: SecCertificate?
        var privateKey: SecKey?
        guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess,
              SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess,
              let cert, let privateKey,
              let attrs = SecKeyCopyAttributes(privateKey) as? [String: Any],
              attrs[kSecAttrKeyType as String] as? String == kSecAttrKeyTypeRSA as String,
              let bits = attrs[kSecAttrKeySizeInBits as String] as? Int, (2048...8192).contains(bits),
              SecKeyIsAlgorithmSupported(privateKey, .sign, .rsaSignatureMessagePKCS1v15SHA256) else {
            throw LoTWProofError.unsupportedKey
        }
        let publicData = SecCertificateCopyData(cert) as Data
        guard publicData.count <= 6000 else { throw LoTWProofError.importFailed }
        key = privateKey
        certificate = publicData
        fingerprint = SHA256.hash(data: publicData).map { String(format: "%02x", $0) }.joined()
        return publicData.base64EncodedString()
    }

    func sign(_ challenge: LoTWProofChallenge, call: String) throws -> LoTWPublicProof {
        guard let key, let certificate else { throw LoTWProofError.importFailed }
        try LoTWProofContract.validate(challenge, call: call, fingerprint: fingerprint)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256,
            Data(challenge.payload.utf8) as CFData, &error) as Data? else {
            throw LoTWProofError.unsupportedKey
        }
        return LoTWPublicProof(certificate: certificate.base64EncodedString(), signature: signature.base64EncodedString())
    }
}
