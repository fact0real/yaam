import Foundation

nonisolated enum SKEDMessagingError: LocalizedError, Equatable, Sendable {
    case invalidInput, missingToken, unavailable, identityRequired, optInRequired
    case unauthorized, recipientUnavailable, rateLimited, conflict, invalidResponse, transport
    case certificateVerificationRefused

    var errorDescription: String? {
        switch self {
        case .invalidInput: return "Use a valid callsign and 1–2,000 characters of plain text."
        case .missingToken: return "Save your personal token in Settings > QRZ Logbook Rank."
        case .unavailable: return "Messaging is not available on this server yet."
        case .identityRequired: return "Your callsign must be independently verified by the service operator before messaging can be enabled."
        case .optInRequired: return "Enable messaging before reading or sending messages."
        case .unauthorized: return "Your QRZ Rank token was refused. Check your token and service access."
        case .recipientUnavailable: return "This recipient is unavailable for messaging."
        case .rateLimited: return "Messaging limit reached. Wait at least one minute before trying again."
        case .conflict: return "This send request has expired or conflicts with a previous request. Refresh before starting a new message."
        case .invalidResponse: return "The messaging service returned an unexpected response."
        case .transport: return "Delivery could not be confirmed. Retry the same message to check safely; it will not be sent twice."
        case .certificateVerificationRefused: return "LoTW verification could not be completed. Use a current certificate for this callsign with an RSA key of at least 2,048 bits. An existing or revoked identity requires administrator review. If LoTW is unavailable, try later or contact the administrator."
        }
    }
}

nonisolated struct SKEDMessagingStatus: Codable, Sendable {
    let available: Bool
    let verifiedCallsign: String?
    let enabled: Bool
    let retentionDays: Int
    var lotwVerificationAvailable: Bool? = nil
    enum CodingKeys: String, CodingKey {
        case available, enabled
        case verifiedCallsign = "verified_callsign", retentionDays = "retention_days"
        case lotwVerificationAvailable = "lotw_verification_available"
    }
}

nonisolated struct SKEDPrivateMessage: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let clientID: String
    let sender: String
    let recipient: String
    let body: String
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, sender, recipient, body
        case clientID = "client_id", createdAt = "created_at"
    }
}

nonisolated struct SKEDMessagePage: Codable, Sendable {
    let messages: [SKEDPrivateMessage]
    let nextBefore: String?
    enum CodingKeys: String, CodingKey { case messages; case nextBefore = "next_before" }
}

nonisolated struct SKEDMessageDraft: Codable, Equatable, Sendable {
    let recipient: String
    let body: String
    let clientID: String
    init(recipient: String, body: String, id: UUID = UUID()) throws {
        let call = recipient.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard SKEDMessagingContract.validCallsign(call), SKEDMessagingContract.validBody(body) else {
            throw SKEDMessagingError.invalidInput
        }
        self.recipient = call
        self.body = body
        clientID = id.uuidString.lowercased()
    }
    enum CodingKeys: String, CodingKey { case recipient, body; case clientID = "client_id" }
}

nonisolated enum SKEDMessagingContract {
    static let origin = URL(string: "https://qrz-rank.asis.sh")!
    static let maxResponseBytes = 512 * 1024

    static func validCallsign(_ value: String) -> Bool {
        value.range(of: #"^(?=.{3,16}$)(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]+(?:/[A-Z0-9]+)*$"#,
                    options: .regularExpression) != nil && value.utf8.count == value.count
    }

    static func validBody(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.unicodeScalars.count <= 2000 &&
        text.utf8.count <= 8000 && text.unicodeScalars.allSatisfy { scalar in
            let n = scalar.value
            return (n >= 32 || n == 9 || n == 10) && !(127...159).contains(n) &&
                !(0x202A...0x202E).contains(n) && !(0x2066...0x2069).contains(n)
        }
    }

    static func validID(_ id: String) -> Bool {
        (1...19).contains(id.count) && id.first != "0" && id.utf8.allSatisfy { (48...57).contains($0) }
    }

    static func request(action: String, method: String = "GET", token: String, body: Data? = nil,
                        before: String? = nil, userAgent: String) throws -> URLRequest {
        var normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("bearer ") { normalized = String(normalized.dropFirst(7)) }
        guard normalized.range(of: #"^qrz_[A-Za-z0-9_-]{40,80}$"#, options: .regularExpression) != nil else {
            throw SKEDMessagingError.missingToken
        }
        let allowed = ["status", "preferences", "messages", "blocks", "reports", "identity/lotw/challenge", "identity/lotw/verify"]
        guard allowed.contains(action) || (action.hasPrefix("blocks/") && validCallsign(String(action.dropFirst(7)))),
              ["GET", "POST", "PUT"].contains(method), body?.count ?? 0 <= 12000,
              before == nil || (action == "messages" && method == "GET" && validID(before!)) else {
            throw SKEDMessagingError.invalidInput
        }
        var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/messaging/\(action)"
        if let before { components.queryItems = [URLQueryItem(name: "before", value: before)] }
        guard let url = components.url else { throw SKEDMessagingError.invalidInput }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(normalized)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    static func validate(_ message: SKEDPrivateMessage, owner: String) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard validID(message.id), UUID(uuidString: message.clientID)?.version4 == true,
              validCallsign(message.sender), validCallsign(message.recipient), validBody(message.body),
              message.sender == owner || message.recipient == owner,
              formatter.date(from: message.createdAt) != nil else { throw SKEDMessagingError.invalidResponse }
    }
}

private extension UUID {
    nonisolated var version4: Bool { (uuid.6 >> 4) == 4 }
}

nonisolated final class SKEDMessagingSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor SKEDMessagingService {
    private let session: URLSession
    private let userAgent: String

    init(userAgent: String) {
        self.userAgent = userAgent
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForResource = 30
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        session = URLSession(configuration: config, delegate: SKEDMessagingSessionDelegate(), delegateQueue: nil)
    }

    #if MESSAGING_REGRESSION
    init(userAgent: String, session: URLSession) {
        self.userAgent = userAgent
        self.session = session
    }
    #endif

    func status(token: String) async throws -> SKEDMessagingStatus {
        let value: SKEDMessagingStatus = try await perform(action: "status", token: token)
        return try validated(value)
    }

    func lotwChallenge(call: String, certificate: String, token: String) async throws -> LoTWProofChallenge {
        try await perform(action: "identity/lotw/challenge", method: "POST", token: token,
            body: JSONSerialization.data(withJSONObject: ["callsign": call, "certificate": certificate]))
    }

    func verifyLoTW(challenge: LoTWProofChallenge, proof: LoTWPublicProof, token: String) async throws -> LoTWProofResult {
        try await perform(action: "identity/lotw/verify", method: "POST", token: token,
            body: JSONSerialization.data(withJSONObject: ["challenge_id": challenge.challengeID,
                "certificate": proof.certificate, "signature": proof.signature]))
    }

    func setEnabled(_ enabled: Bool, token: String) async throws -> SKEDMessagingStatus {
        let result: SKEDMessagingStatus = try await perform(action: "preferences", method: "PUT", token: token,
            body: JSONSerialization.data(withJSONObject: ["enabled": enabled]))
        return try validated(result)
    }

    private func validated(_ value: SKEDMessagingStatus) throws -> SKEDMessagingStatus {
        guard value.available, value.retentionDays == 30,
              value.verifiedCallsign.map(SKEDMessagingContract.validCallsign) ?? !value.enabled else {
            throw SKEDMessagingError.invalidResponse
        }
        return value
    }

    func messages(token: String, owner: String, before: String? = nil) async throws -> SKEDMessagePage {
        let page: SKEDMessagePage = try await perform(action: "messages", token: token, before: before)
        guard page.messages.count <= 50, Set(page.messages.map(\.id)).count == page.messages.count,
              page.nextBefore.map(SKEDMessagingContract.validID) ?? true,
              page.nextBefore == nil || (page.messages.count == 50 && page.nextBefore == page.messages.last?.id) else {
            throw SKEDMessagingError.invalidResponse
        }
        for message in page.messages { try SKEDMessagingContract.validate(message, owner: owner) }
        let ids = page.messages.compactMap { UInt64($0.id) }
        guard ids.count == page.messages.count,
              zip(ids, ids.dropFirst()).allSatisfy({ $0 > $1 }),
              before.flatMap(UInt64.init).map({ bound in ids.allSatisfy { $0 < bound } }) ?? true else {
            throw SKEDMessagingError.invalidResponse
        }
        return page
    }

    func send(_ draft: SKEDMessageDraft, token: String, owner: String) async throws -> SKEDPrivateMessage {
        struct Envelope: Decodable, Sendable { let message: SKEDPrivateMessage }
        let result: Envelope = try await perform(action: "messages", method: "POST", token: token, body: JSONEncoder().encode(draft))
        try SKEDMessagingContract.validate(result.message, owner: owner)
        guard result.message.sender == owner, result.message.recipient == draft.recipient,
              result.message.clientID == draft.clientID, result.message.body == draft.body else { throw SKEDMessagingError.invalidResponse }
        return result.message
    }

    func blocks(token: String) async throws -> [String] {
        struct Envelope: Decodable, Sendable { let callsigns: [String] }
        let value: Envelope = try await perform(action: "blocks", token: token)
        guard value.callsigns.count <= 500, value.callsigns.allSatisfy(SKEDMessagingContract.validCallsign) else {
            throw SKEDMessagingError.invalidResponse
        }
        return value.callsigns
    }

    func block(_ call: String, blocked: Bool, token: String) async throws {
        let result: Acknowledgement = try await perform(action: "blocks/\(call)", method: "PUT", token: token,
            body: JSONSerialization.data(withJSONObject: ["blocked": blocked]))
        guard result.ok else { throw SKEDMessagingError.invalidResponse }
    }

    func report(_ message: SKEDPrivateMessage, reason: String, token: String) async throws {
        guard ["spam", "abuse", "impersonation"].contains(reason) else { throw SKEDMessagingError.invalidInput }
        let result: Acknowledgement = try await perform(action: "reports", method: "POST", token: token,
            body: JSONSerialization.data(withJSONObject: ["message_id": message.id, "reason": reason]))
        guard result.ok else { throw SKEDMessagingError.invalidResponse }
    }

    private struct Acknowledgement: Decodable, Sendable { let ok: Bool }

    private func perform<T: Decodable & Sendable>(action: String, method: String = "GET", token: String,
                        body: Data? = nil, before: String? = nil) async throws -> T {
        let request = try SKEDMessagingContract.request(action: action, method: method, token: token, body: body,
                                                       before: before, userAgent: userAgent)
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse, http.url?.scheme == "https",
                  http.url?.host == SKEDMessagingContract.origin.host else { throw SKEDMessagingError.invalidResponse }
            if http.statusCode != 200 {
                if action.hasPrefix("identity/lotw/"), [400, 403, 409, 422, 503].contains(http.statusCode) {
                    throw SKEDMessagingError.certificateVerificationRefused
                }
                switch http.statusCode {
                case 401: throw SKEDMessagingError.unauthorized
                case 403:
                    if action == "preferences" { throw SKEDMessagingError.identityRequired }
                    throw SKEDMessagingError.optInRequired
                case 404: throw action == "messages" && method == "POST" ? SKEDMessagingError.recipientUnavailable : .unavailable
                case 409: throw SKEDMessagingError.conflict
                case 429: throw SKEDMessagingError.rateLimited
                case 400, 413: throw SKEDMessagingError.invalidInput
                default: throw SKEDMessagingError.unavailable
                }
            }
            guard http.mimeType == "application/json", response.expectedContentLength <= SKEDMessagingContract.maxResponseBytes else {
                throw SKEDMessagingError.invalidResponse
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < SKEDMessagingContract.maxResponseBytes else { throw SKEDMessagingError.invalidResponse }
                data.append(byte)
            }
            try Task.checkCancellation()
            return try JSONDecoder().decode(T.self, from: data)
        } catch is CancellationError { throw CancellationError() }
        catch let error as SKEDMessagingError { throw error }
        catch is DecodingError { throw SKEDMessagingError.invalidResponse }
        catch { throw SKEDMessagingError.transport }
    }
}
