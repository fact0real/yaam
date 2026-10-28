// Generate an ephemeral synthetic PKCS#12 fixture outside the repository, then:
// swiftc -parse-as-library Tests/LoTWProofRegression.swift YAAM/LoTWProofSigner.swift
// YAAM/SKEDMessagingService.swift -o /tmp/lotw-proof-test
// /tmp/lotw-proof-test /tmp/.../synthetic.p12 /tmp/.../public-proof.json
import Foundation
import CryptoKit
import Security

@main struct LoTWProofRegression {
    static func main() async throws {
        let signer = LoTWProofSigner()
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        do { _ = try await signer.load(url: url, password: "wrong"); fatalError("Wrong password accepted") }
        catch { }
        let encoded = try await signer.load(url: url, password: "synthetic-test-only")
        let certificate = Data(base64Encoded: encoded)!
        let fingerprint = SHA256.hash(data: certificate).map { String(format: "%02x", $0) }.joined()
        let nonce = String(repeating: "a", count: 64)
        let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(240))
        let payload = "YAAM LoTW callsign proof v1\norigin=https://qrz-rank.asis.sh\nuser=4\ncallsign=K1ABC\ncertificate_sha256=\(fingerprint)\nnonce=\(nonce)\nexpires=\(expiry)\n"
        let challenge = LoTWProofChallenge(challengeID: nonce, payload: payload, expiresAt: expiry)
        let proof = try await signer.sign(challenge, call: "K1ABC")
        let cert = SecCertificateCreateWithData(nil, certificate as CFData)!
        let publicKey = SecCertificateCopyKey(cert)!
        precondition(SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
            Data(payload.utf8) as CFData, Data(base64Encoded: proof.signature)! as CFData, nil))
        for altered in [payload.replacingOccurrences(of: "qrz-rank.asis.sh", with: "evil.invalid"),
                        payload.replacingOccurrences(of: "callsign=K1ABC", with: "callsign=G0JHC"),
                        payload + "QSO arbitrary text", payload.replacingOccurrences(of: fingerprint, with: String(repeating: "0", count: 64))] {
            do {
                _ = try await signer.sign(LoTWProofChallenge(challengeID: nonce, payload: altered, expiresAt: expiry), call: "K1ABC")
                fatalError("Altered purpose accepted")
            } catch LoTWProofError.invalidChallenge { }
        }
        let expired = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-10))
        do {
            try LoTWProofContract.validate(LoTWProofChallenge(challengeID: nonce,
                payload: payload.replacingOccurrences(of: expiry, with: expired), expiresAt: expired), call: "K1ABC", fingerprint: fingerprint)
            fatalError("Expired challenge accepted")
        } catch LoTWProofError.invalidChallenge { }
        // This synthetic certificate must not have been permanently imported.
        let query = [kSecClass as String: kSecClassCertificate,
                     kSecAttrSerialNumber as String: SecCertificateCopySerialNumberData(cert, nil)!,
                     kSecAttrIssuer as String: SecCertificateCopyNormalizedIssuerSequence(cert)!,
                     kSecReturnRef as String: true] as CFDictionary
        var item: CFTypeRef?
        precondition(SecItemCopyMatching(query, &item) == errSecItemNotFound, "Memory-only import persisted a certificate")
        let output = try JSONSerialization.data(withJSONObject: ["certificate": proof.certificate,
            "signature": proof.signature, "payload": payload])
        try output.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        await signer.clear()
        do { _ = try await signer.sign(challenge, call: "K1ABC"); fatalError("Cleared key reused") }
        catch LoTWProofError.importFailed { }
        print("PASS: memory-only import, wrong password, SHA-256 signature, hostile/expired challenge, no persistent certificate and key release")
    }
}
