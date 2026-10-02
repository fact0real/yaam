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

nonisolated struct QRZCountrySummary: Codable, Identifiable, Hashable, Sendable {
    var id: String { iso }
    let iso: String
    let name: String
    let stationCount: Int?

    enum CodingKeys: String, CodingKey {
        case iso, name
        case countryIso = "country_iso"
        case countryName = "country_name"
        case stationCount = "station_count"
        case operatorCount = "operator_count"
    }

    init(iso: String, name: String, stationCount: Int? = nil) {
        self.iso = iso
        self.name = name
        self.stationCount = stationCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.iso = (try? container.decode(String.self, forKey: .iso))
            ?? (try? container.decode(String.self, forKey: .countryIso))
            ?? ""
        self.name = (try? container.decode(String.self, forKey: .name))
            ?? (try? container.decode(String.self, forKey: .countryName))
            ?? (self.iso.isEmpty ? "Unknown" : self.iso.uppercased())
        self.stationCount = (try? container.decode(Int.self, forKey: .stationCount))
            ?? (try? container.decode(Int.self, forKey: .operatorCount))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(iso, forKey: .iso)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(stationCount, forKey: .stationCount)
    }
}

nonisolated struct QRZCountryLeaderboardItem: Codable, Identifiable, Hashable, Sendable {
    var id: String { callsign }
    let rank: Int
    let callsign: String
    let score: Int
    let scoreQso: Int?
    let scoreCountries: Int?
    let scoreBand: Int?
    let rankQso: Int?
    let rankCountries: Int?
    let rankBand: Int?
    let flagUrl: String?
    let countryName: String?
    let countryIso: String?

    enum CodingKeys: String, CodingKey {
        case rank, callsign, score
        case scoreQso = "score_qso"
        case scoreCountries = "score_countries"
        case scoreBand = "score_band"
        case rankQso = "rank_qso"
        case rankCountries = "rank_countries"
        case rankBand = "rank_band"
        case flagUrl = "flag_url"
        case countryName = "country_name"
        case countryIso = "country_iso"
    }
}

nonisolated struct QRZCountryLeaderboardResponse: Codable, Sendable {
    let countryIso: String
    let countryName: String
    let category: String
    let totalStations: Int
    let leaderboard: [QRZCountryLeaderboardItem]

    enum CodingKeys: String, CodingKey {
        case countryIso = "country_iso"
        case countryName = "country_name"
        case category
        case totalStations = "total_stations"
        case leaderboard
    }
}

nonisolated struct QRZNationalStanding: Codable, Hashable, Sendable {
    let countryRankQso: Int?
    let countryRankDxcc: Int?
    let countryRankBand: Int?
    let totalCountryStations: Int?

    enum CodingKeys: String, CodingKey {
        case countryRankQso = "country_rank_qso"
        case countryRankDxcc = "country_rank_dxcc"
        case countryRankBand = "country_rank_band"
        case totalCountryStations = "total_country_stations"
    }
}

nonisolated struct QRZStationBadge: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(icon)_\(label)" }
    let icon: String
    let label: String
    let color: String
    let descriptionText: String?

    enum CodingKeys: String, CodingKey {
        case id, icon, label, title, color, description
    }

    init(icon: String, label: String, color: String, descriptionText: String? = nil) {
        self.icon = icon
        self.label = label
        self.color = color
        self.descriptionText = descriptionText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        icon = container.decodeFlexibleString(forKey: .icon) ?? "🏅"
        label = container.decodeFlexibleString(forKey: .label)
            ?? container.decodeFlexibleString(forKey: .title)
            ?? "Honor Badge"
        color = container.decodeFlexibleString(forKey: .color) ?? "cyan"
        descriptionText = container.decodeFlexibleString(forKey: .description)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(icon, forKey: .icon)
        try container.encode(label, forKey: .label)
        try container.encode(color, forKey: .color)
        try container.encodeIfPresent(descriptionText, forKey: .description)
    }
}

nonisolated struct QRZWorldChampionItem: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(countryIso)_\(callsign)" }
    let callsign: String
    let countryIso: String
    let countryName: String
    let flagUrl: String?
    let rankQso: String?
    let scoreQso: String?
    let scoreCountries: String?
    let scoreBand: String?
    let valScoreQso: Int?

    var formattedScore: String {
        if let val = valScoreQso {
            return val.formatted()
        }
        return scoreQso ?? "0"
    }

    enum CodingKeys: String, CodingKey {
        case callsign
        case countryIso = "country_iso"
        case countryName = "country_name"
        case flagUrl = "flag_url"
        case rankQso = "rank_qso"
        case scoreQso = "score_qso"
        case scoreCountries = "score_countries"
        case scoreBand = "score_band"
        case valScoreQso = "val_score_qso"
    }

    init(
        callsign: String,
        countryIso: String,
        countryName: String,
        flagUrl: String? = nil,
        rankQso: String? = nil,
        scoreQso: String? = nil,
        scoreCountries: String? = nil,
        scoreBand: String? = nil,
        valScoreQso: Int? = nil
    ) {
        self.callsign = callsign
        self.countryIso = countryIso
        self.countryName = countryName
        self.flagUrl = flagUrl
        self.rankQso = rankQso
        self.scoreQso = scoreQso
        self.scoreCountries = scoreCountries
        self.scoreBand = scoreBand
        self.valScoreQso = valScoreQso
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callsign = container.decodeFlexibleString(forKey: .callsign) ?? ""
        countryIso = container.decodeFlexibleString(forKey: .countryIso) ?? ""
        countryName = container.decodeFlexibleString(forKey: .countryName) ?? ""
        flagUrl = container.decodeFlexibleString(forKey: .flagUrl)
        rankQso = container.decodeFlexibleString(forKey: .rankQso)
        scoreQso = container.decodeFlexibleString(forKey: .scoreQso)
        scoreCountries = container.decodeFlexibleString(forKey: .scoreCountries)
        scoreBand = container.decodeFlexibleString(forKey: .scoreBand)
        valScoreQso = container.decodeFlexibleInteger(forKey: .valScoreQso)
    }
}

nonisolated struct QRZWorldChampionsResponse: Codable, Sendable {
    let champions: [QRZWorldChampionItem]
}

nonisolated struct QRZOverviewTotals: Codable, Sendable {
    let totalStations: Int?
    let totalQso: Int?
    let totalCountries: Int?
    let avgQso: Double?
    let avgDxcc: Double?
    let avgBand: Double?

    enum CodingKeys: String, CodingKey {
        case totalStations = "total_stations"
        case totalQso = "total_qso"
        case totalCountries = "total_countries"
        case avgQso = "avg_qso"
        case avgDxcc = "avg_dxcc"
        case avgBand = "avg_band"
    }
}

nonisolated struct QRZOverviewResponse: Codable, Sendable {
    let totals: QRZOverviewTotals?
}


nonisolated struct QRZNextRankTarget: Codable, Hashable, Sendable {
    let callsign: String
    let gapQso: Int
    let rankQso: Int?

    enum CodingKeys: String, CodingKey {
        case callsign
        case gapQso = "gap_qso"
        case rankQso = "rank_qso"
    }
}

nonisolated struct RankSimulationResult: Hashable, Sendable {
    let callsign: String
    let originalScore: Int
    let additionalQso: Int
    let simulatedScore: Int
    let originalRank: Int?
    let simulatedRank: Int
    let leapfroggedCallsigns: [String]
    let nextStationAboveCallsign: String?
    let nextStationGap: Int?
}

nonisolated struct QRZChampionTarget: Codable, Hashable, Sendable {
    let callsign: String
    let scoreQso: Int
    let gapToChamp: Int

    enum CodingKeys: String, CodingKey {
        case callsign
        case scoreQso = "score_qso"
        case gapToChamp = "gap_to_champ"
    }
}

nonisolated struct QRZStationRecommendations: Codable, Hashable, Sendable {
    let title: String?
    let text: String?
    let immediateNextTarget: QRZNextRankTarget?
    let nationalChampion: QRZChampionTarget?

    enum CodingKeys: String, CodingKey {
        case title, text
        case immediateNextTarget = "immediate_next_target"
        case nationalChampion = "national_champion"
    }
}

nonisolated struct QRZPeerRival: Codable, Identifiable, Hashable, Sendable {
    var id: String { callsign }
    let callsign: String
    let scoreQso: Int?
    let scoreCountries: Int?
    let scoreBand: Int?
    let rankQso: Int?

    enum CodingKeys: String, CodingKey {
        case callsign
        case scoreQso = "score_qso"
        case scoreCountries = "score_countries"
        case scoreBand = "score_band"
        case rankQso = "rank_qso"
    }
}

nonisolated struct QRZRankAnalysisResponse: Codable, Sendable {
    let callsign: String
    let countryIso: String
    let countryName: String
    let nationalStanding: QRZNationalStanding?
    let badges: [QRZStationBadge]
    let recommendations: QRZStationRecommendations?
    let peerRivals: [QRZPeerRival]

    enum CodingKeys: String, CodingKey {
        case callsign
        case countryIso = "country_iso"
        case countryName = "country_name"
        case nationalStanding = "national_standing"
        case badges, recommendations
        case peerRivals = "peer_rivals"
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

    static func makeCountriesRequest(
        token: String? = nil,
        userAgent: String
    ) throws -> URLRequest {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                throw QRZRankAPIContractError.invalidURL
            }
            components.percentEncodedPath = "/api/v1/countries"
            guard let url = components.url else { throw QRZRankAPIContractError.invalidURL }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 15
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            return req
        }
        return try makeAuthorizedRequest(path: "/api/v1/countries", token: token, userAgent: userAgent)
    }

    static func makeCountryLeaderboardRequest(
        countryIso: String,
        category: String = "qso",
        limit: Int = 50,
        token: String? = nil,
        userAgent: String
    ) throws -> URLRequest {
        let cleanIso = countryIso.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw QRZRankAPIContractError.invalidURL
        }
        components.percentEncodedPath = "/api/v1/leaderboard/country/\(cleanIso)"
        components.queryItems = [
            URLQueryItem(name: "category", value: category),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else { throw QRZRankAPIContractError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            req.setValue("Bearer \(normalizedToken(token))", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    static func makeCountryLeaderboardCSVRequest(
        countryIso: String,
        category: String,
        token: String? = nil,
        userAgent: String
    ) throws -> URLRequest {
        let iso = countryIso.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard iso.count == 2, iso.unicodeScalars.allSatisfy(CharacterSet.letters.contains),
              ["qso", "countries", "band"].contains(category),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw QRZRankAPIContractError.invalidURL
        }
        components.path = "/api/v1/leaderboard/country/\(iso)/csv"
        components.queryItems = [URLQueryItem(name: "category", value: category)]
        guard let url = components.url else { throw QRZRankAPIContractError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("text/csv", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let token, !normalizedToken(token).isEmpty {
            request.setValue("Bearer \(normalizedToken(token))", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func makeAnalysisRequest(
        callsign: String,
        token: String? = nil,
        userAgent: String
    ) throws -> URLRequest {
        let normalizedCallsign = normalizedCallsign(callsign)
        guard isPlausibleCallsign(normalizedCallsign) else {
            throw QRZRankAPIContractError.invalidCallsign
        }
        guard let encodedCallsign = normalizedCallsign.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            throw QRZRankAPIContractError.invalidURL
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw QRZRankAPIContractError.invalidURL
        }
        components.percentEncodedPath = "/api/v1/rank/\(encodedCallsign)/analysis"
        guard let url = components.url else { throw QRZRankAPIContractError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            req.setValue("Bearer \(normalizedToken(token))", forHTTPHeaderField: "Authorization")
        }
        return req
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

    static func decodeCountries(_ data: Data) throws -> [QRZCountrySummary] {
        struct Envelope: Decodable {
            let countries: [QRZCountrySummary]
        }
        do {
            let decoded = try JSONDecoder().decode(Envelope.self, from: data)
            return decoded.countries
        } catch {
            throw QRZRankAPIContractError.invalidResponse
        }
    }

    static func decodeCountryLeaderboard(_ data: Data) throws -> QRZCountryLeaderboardResponse {
        do {
            return try JSONDecoder().decode(QRZCountryLeaderboardResponse.self, from: data)
        } catch {
            throw QRZRankAPIContractError.invalidResponse
        }
    }

    static func makeWorldChampionsRequest(
        token: String? = nil,
        userAgent: String
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw QRZRankAPIContractError.invalidURL
        }
        components.percentEncodedPath = "/api/v1/leaderboard/champions"
        guard let url = components.url else { throw QRZRankAPIContractError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            req.setValue("Bearer \(normalizedToken(token))", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    static func decodeWorldChampions(_ data: Data) throws -> [QRZWorldChampionItem] {
        do {
            let decoded = try JSONDecoder().decode(QRZWorldChampionsResponse.self, from: data)
            return decoded.champions
        } catch {
            throw QRZRankAPIContractError.invalidResponse
        }
    }

    static func decodeAnalysis(_ data: Data) throws -> QRZRankAnalysisResponse {
        do {
            return try JSONDecoder().decode(QRZRankAnalysisResponse.self, from: data)
        } catch {
            throw QRZRankAPIContractError.invalidResponse
        }
    }

    static func makeOverviewStatsRequest(userAgent: String) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw QRZRankAPIContractError.invalidURL
        }
        components.percentEncodedPath = "/api/v1/stats/overview"
        guard let url = components.url else { throw QRZRankAPIContractError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return req
    }

    static func decodeOverviewStats(_ data: Data) throws -> QRZOverviewResponse {
        do {
            return try JSONDecoder().decode(QRZOverviewResponse.self, from: data)
        } catch {
            throw QRZRankAPIContractError.invalidResponse
        }
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
