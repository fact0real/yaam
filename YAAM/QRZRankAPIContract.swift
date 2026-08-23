//
//  QRZRankAPIContract.swift
//  YAAM
//

import Foundation

nonisolated struct QRZRankResponse: Codable, Sendable {
    let bid: String?
    let callsign: String?
    let country_iso: String?
    let country_name: String?
    let rank_band: String?
    let rank_countries: String?
    let rank_qso: String?
    let score_band: String?
    let score_countries: String?
    let score_qso: String?

    private enum CodingKeys: String, CodingKey {
        case bid, callsign, country_iso, country_name
        case rank_band, rank_countries, rank_qso
        case score_band, score_countries, score_qso
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bid = container.decodeFlexibleString(forKey: .bid)
        callsign = container.decodeFlexibleString(forKey: .callsign)
        country_iso = container.decodeFlexibleString(forKey: .country_iso)
        country_name = container.decodeFlexibleString(forKey: .country_name)
        rank_band = container.decodeFlexibleString(forKey: .rank_band)
        rank_countries = container.decodeFlexibleString(forKey: .rank_countries)
        rank_qso = container.decodeFlexibleString(forKey: .rank_qso)
        score_band = container.decodeFlexibleString(forKey: .score_band)
        score_countries = container.decodeFlexibleString(forKey: .score_countries)
        score_qso = container.decodeFlexibleString(forKey: .score_qso)
    }
}

nonisolated extension QRZRankResponse {
    init(
        bid: String?,
        callsign: String?,
        country_iso: String?,
        country_name: String?,
        rank_band: String?,
        rank_countries: String?,
        rank_qso: String?,
        score_band: String?,
        score_countries: String?,
        score_qso: String?
    ) {
        self.bid = bid
        self.callsign = callsign
        self.country_iso = country_iso
        self.country_name = country_name
        self.rank_band = rank_band
        self.rank_countries = rank_countries
        self.rank_qso = rank_qso
        self.score_band = score_band
        self.score_countries = score_countries
        self.score_qso = score_qso
    }

    var hasRankingValue: Bool {
        [rank_qso, rank_band, rank_countries, score_qso, score_band, score_countries]
            .contains { value in
                !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
    }
}

nonisolated struct QRZRankAPIQuota: Decodable, Equatable, Sendable {
    let limit: Int?
    let used: Int?
    let remaining: Int?
    let remainingRequests: Int?
    let unlimited: Bool
    let canMakeRequest: Bool
    let exhausted: Bool
    let status: String?
    let resetsAt: String?
    let resetInSeconds: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limit = container.decodeFlexibleInteger(forKey: .limit)
        used = container.decodeFlexibleInteger(forKey: .used)
        remaining = container.decodeFlexibleInteger(forKey: .remaining)
        remainingRequests = container.decodeFlexibleInteger(forKey: .remainingRequests) ?? remaining
        unlimited = container.decodeFlexibleBool(forKey: .unlimited) ?? false
        status = container.decodeFlexibleString(forKey: .status)
        resetsAt = container.decodeFlexibleString(forKey: .resetsAt)
        resetInSeconds = container.decodeFlexibleInteger(forKey: .resetInSeconds)

        let effectiveRemaining = remainingRequests ?? remaining
        canMakeRequest = container.decodeFlexibleBool(forKey: .canMakeRequest)
            ?? (unlimited || effectiveRemaining.map { $0 > 0 } ?? true)
        exhausted = container.decodeFlexibleBool(forKey: .exhausted)
            ?? (!unlimited && effectiveRemaining == 0)
    }

    private enum CodingKeys: String, CodingKey {
        case limit, used, remaining, unlimited, exhausted, status
        case remainingRequests = "remaining_requests"
        case canMakeRequest = "can_make_request"
        case resetsAt = "resets_at"
        case resetInSeconds = "reset_in_seconds"
    }

    var effectiveRemaining: Int? {
        remainingRequests ?? remaining
    }

    var isUnlimited: Bool {
        unlimited || status?.lowercased() == "unlimited"
    }

    var allowsRequest: Bool {
        if isUnlimited { return true }
        if exhausted || !canMakeRequest { return false }
        return effectiveRemaining.map { $0 > 0 } ?? true
    }
}

nonisolated struct QRZRankAPIEnvelope: Decodable, Sendable {
    let apiVersion: String?
    let data: QRZRankResponse
    let quota: QRZRankAPIQuota?

    private enum CodingKeys: String, CodingKey {
        case apiVersion = "api_version"
        case data, quota
    }
}

nonisolated struct QRZRankAPIQuotaEnvelope: Decodable, Sendable {
    let apiVersion: String?
    let quota: QRZRankAPIQuota

    private enum CodingKeys: String, CodingKey {
        case apiVersion = "api_version"
        case quota
    }
}

nonisolated struct QRZRankAPIErrorDetails: Decodable, Equatable, Sendable {
    let code: String
    let message: String
}

private nonisolated struct QRZRankAPIErrorEnvelope: Decodable, Sendable {
    let error: QRZRankAPIErrorDetails
}

private nonisolated struct QRZRankLegacyErrorEnvelope: Decodable, Sendable {
    let error: String?
    let message: String?
}

nonisolated enum QRZRankAPIContractError: LocalizedError, Equatable, Sendable {
    case invalidCallsign
    case missingToken
    case malformedToken
    case invalidURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCallsign:
            return "Enter a valid callsign."
        case .missingToken:
            return "Add your personal QRZ Rank API token in Settings > Rank Service."
        case .malformedToken:
            return "The QRZ Rank API token contains invalid whitespace or control characters."
        case .invalidURL, .invalidResponse:
            return "QRZ Rank Service returned an invalid response."
        }
    }
}

nonisolated enum QRZRankAPIContract {
    static let baseURL = URL(string: "https://qrz-rank.asis.sh")!

    static func normalizedCallsign(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func isPlausibleCallsign(_ callsign: String) -> Bool {
        let normalized = normalizedCallsign(callsign)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/")
        guard (3...16).contains(normalized.count),
              normalized.contains(where: { $0.isASCII && $0.isLetter }),
              normalized.contains(where: { $0.isASCII && $0.isNumber }) else {
            return false
        }
        return normalized.unicodeScalars.allSatisfy(allowed.contains)
    }

    static func normalizedToken(_ value: String) -> String {
        var token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.count >= 7,
           String(token.prefix(7)).caseInsensitiveCompare("Bearer ") == .orderedSame {
            token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token
    }

    static func makeRequest(
        callsign: String,
        token rawToken: String,
        userAgent: String
    ) throws -> URLRequest {
        let normalizedCallsign = normalizedCallsign(callsign)
        guard isPlausibleCallsign(normalizedCallsign) else {
            throw QRZRankAPIContractError.invalidCallsign
        }

        let pathSegmentAllowed = CharacterSet.alphanumerics
        guard let encodedCallsign = normalizedCallsign.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) else {
            throw QRZRankAPIContractError.invalidURL
        }
        return try makeAuthorizedRequest(
            path: "/api/v1/rank/\(encodedCallsign)",
            token: rawToken,
            userAgent: userAgent
        )
    }

    static func makeQuotaRequest(
        token rawToken: String,
        userAgent: String
    ) throws -> URLRequest {
        try makeAuthorizedRequest(
            path: "/api/v1/quota",
            token: rawToken,
            userAgent: userAgent
        )
    }

    static func decodeSuccess(_ data: Data) throws -> QRZRankAPIEnvelope {
        let envelope: QRZRankAPIEnvelope
        do {
            envelope = try JSONDecoder().decode(QRZRankAPIEnvelope.self, from: data)
        } catch {
            throw QRZRankAPIContractError.invalidResponse
        }
        guard envelope.apiVersion == nil || envelope.apiVersion == "v1",
              envelope.data.callsign?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              envelope.data.hasRankingValue else {
            throw QRZRankAPIContractError.invalidResponse
        }
        return envelope
    }

    static func decodeQuota(_ data: Data) throws -> QRZRankAPIQuotaEnvelope {
        let envelope: QRZRankAPIQuotaEnvelope
        do {
            envelope = try JSONDecoder().decode(QRZRankAPIQuotaEnvelope.self, from: data)
        } catch {
            throw QRZRankAPIContractError.invalidResponse
        }
        guard envelope.apiVersion == nil || envelope.apiVersion == "v1" else {
            throw QRZRankAPIContractError.invalidResponse
        }
        return envelope
    }

    static func decodeError(_ data: Data) -> QRZRankAPIErrorDetails? {
        if let envelope = try? JSONDecoder().decode(QRZRankAPIErrorEnvelope.self, from: data) {
            return QRZRankAPIErrorDetails(
                code: sanitized(envelope.error.code),
                message: sanitized(envelope.error.message)
            )
        }
        if let legacy = try? JSONDecoder().decode(QRZRankLegacyErrorEnvelope.self, from: data) {
            let message = sanitized(legacy.message ?? legacy.error ?? "")
            if !message.isEmpty {
                return QRZRankAPIErrorDetails(code: "", message: message)
            }
        }
        return nil
    }

    private static func sanitized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(500))
    }

    private static func makeAuthorizedRequest(
        path: String,
        token rawToken: String,
        userAgent: String
    ) throws -> URLRequest {
        let token = normalizedToken(rawToken)
        guard !token.isEmpty else {
            throw QRZRankAPIContractError.missingToken
        }
        let forbiddenCharacters = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard token.unicodeScalars.allSatisfy({ !forbiddenCharacters.contains($0) }) else {
            throw QRZRankAPIContractError.malformedToken
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw QRZRankAPIContractError.invalidURL
        }
        components.percentEncodedPath = path
        guard let url = components.url else {
            throw QRZRankAPIContractError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}

private extension KeyedDecodingContainer {
    nonisolated func decodeFlexibleString(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return value.rounded() == value ? String(Int(value)) : String(value)
        }
        return nil
    }

    nonisolated func decodeFlexibleInteger(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    nonisolated func decodeFlexibleBool(forKey key: Key) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decode(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "y", "1": return true
            case "false", "no", "n", "0": return false
            default: return nil
            }
        }
        return nil
    }
}
