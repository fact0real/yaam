import Foundation

nonisolated struct QRZIncomingConfirmation: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let callsign: String
    let qsoDate: String
    let requestedAt: String
    let rawSummary: String
    let qsoID: String

    /// QRZ's QSO ID is stable even when the page summary changes. Legacy requests keep their original ID.
    var recoveryKey: String { qsoID.isEmpty ? id : qsoID }

    enum CodingKeys: String, CodingKey {
        case id, callsign, qsoDate, requestedAt, rawSummary, qsoID
    }

    init(callsign: String, qsoDate: String, requestedAt: String, rawSummary: String, qsoID: String = "") {
        self.callsign = callsign
        self.qsoDate = qsoDate
        self.requestedAt = requestedAt
        self.rawSummary = rawSummary
        self.qsoID = qsoID
        id = "\(callsign)|\(qsoDate)|\(requestedAt)|\(rawSummary)"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callsign = try container.decode(String.self, forKey: .callsign)
        qsoDate = try container.decode(String.self, forKey: .qsoDate)
        requestedAt = try container.decode(String.self, forKey: .requestedAt)
        rawSummary = try container.decode(String.self, forKey: .rawSummary)
        qsoID = (try? container.decode(String.self, forKey: .qsoID)) ?? ""
        id = (try? container.decode(String.self, forKey: .id)) ?? "\(callsign)|\(qsoDate)|\(requestedAt)|\(rawSummary)"
    }
}

/// Requests remain reviewable after QRZ removes them; disappearance is never confirmation evidence.
nonisolated struct QRZIncomingRecoveryArchive: Codable, Equatable, Sendable {
    var requests: [QRZIncomingConfirmation] = []
    var lastReturnedKeys: Set<String> = []
    var refreshedAt: Date?

    static func linkedKeys(_ fields: [String: String]) -> Set<String> {
        var keys = Set<String>()
        if let data = fields["APP_YAAM_INCOMING_REQUESTS"]?.data(using: .utf8),
           let saved = try? JSONDecoder().decode([String].self, from: data) { keys.formUnion(saved) }
        if let legacy = fields["APP_YAAM_INCOMING_REQUEST"], !legacy.isEmpty { keys.insert(legacy) }
        return keys
    }

    mutating func retain(_ request: QRZIncomingConfirmation) {
        if let index = requests.firstIndex(where: { $0.recoveryKey == request.recoveryKey }) {
            requests[index] = request
        } else { requests.append(request) }
    }

    mutating func refresh(_ returned: [QRZIncomingConfirmation], now: Date = Date()) {
        for request in returned { retain(request) }
        lastReturnedKeys = Set(returned.map(\.recoveryKey))
        refreshedAt = now
    }

    mutating func remove(_ request: QRZIncomingConfirmation) {
        requests.removeAll { $0.recoveryKey == request.recoveryKey }
        lastReturnedKeys.remove(request.recoveryKey)
    }
}
