//
//  QRZRankService.swift
//  YAAM
//

import Foundation

nonisolated struct QRZRankServiceCredentials: Sendable {
    var username: String
    var password: String
}

nonisolated enum QRZRankFetchFailure: LocalizedError, Equatable, Sendable {
    case invalidCallsign
    case guestLimit(String)
    case authenticationRequired(String)
    case authenticationFailed(String)
    case subscriptionRequired(String)
    case callsignNotFound(String)
    case dailyLimitReached(Int)
    case rateLimited(String)
    case server(status: Int, message: String)
    case transport(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCallsign:
            return "Enter a valid callsign."
        case .guestLimit(let message):
            return message.isEmpty
                ? "The QRZ Rank guest allowance has ended. Sign in to QRZ Rank Service in Settings."
                : message
        case .authenticationRequired(let message):
            return message.isEmpty ? "Sign in to QRZ Rank Service in Settings." : message
        case .authenticationFailed(let message):
            return message.isEmpty ? "QRZ Rank Service did not accept the account credentials." : message
        case .subscriptionRequired(let message):
            return message.isEmpty ? "The QRZ Rank Service account requires an active subscription." : message
        case .callsignNotFound(let callsign):
            return "No QRZ ranking was found for \(callsign)."
        case .dailyLimitReached(let limit):
            return "The daily QRZ Rank limit of \(limit) requests has been reached. It resets at local midnight."
        case .rateLimited(let message):
            return message.isEmpty
                ? "QRZ Rank Service is temporarily rate limiting requests. Try again later."
                : message
        case .server(let status, let message):
            return message.isEmpty ? "QRZ Rank Service returned HTTP \(status)." : message
        case .transport(let message):
            return "QRZ Rank Service is unavailable: \(message)"
        case .invalidResponse:
            return "QRZ Rank Service returned an invalid ranking response."
        }
    }

    var shouldStopBatch: Bool {
        switch self {
        case .guestLimit, .authenticationRequired, .authenticationFailed,
             .subscriptionRequired, .dailyLimitReached, .rateLimited:
            return true
        case .invalidCallsign, .callsignNotFound, .server, .transport, .invalidResponse:
            return false
        }
    }

    var shouldRecordLookupOutcome: Bool {
        switch self {
        case .invalidCallsign, .callsignNotFound:
            return true
        case .guestLimit, .authenticationRequired, .authenticationFailed,
             .subscriptionRequired, .dailyLimitReached, .rateLimited,
             .server, .transport, .invalidResponse:
            return false
        }
    }
}

private nonisolated struct QRZRankErrorPayload: Decodable, Sendable {
    let error: String?
    let message: String?

    var bestMessage: String {
        (error ?? message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor QRZRankService {
    static let shared = QRZRankService()

    private let baseURL = URL(string: "https://qrz-rank.asis.sh")!
    private let session: URLSession
    private var authenticatedUsername = ""
    private var authenticationTask: Task<Void, Error>?

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func resetAuthentication() async {
        authenticationTask?.cancel()
        authenticationTask = nil
        authenticatedUsername = ""
        await withCheckedContinuation { continuation in
            session.reset { continuation.resume() }
        }
    }

    func fetchRank(
        callsign: String,
        username: String,
        password: String,
        userAgent: String
    ) async throws -> QRZRankResponse {
        let normalized = callsign
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard Self.isPlausibleCallsign(normalized) else {
            throw QRZRankFetchFailure.invalidCallsign
        }

        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedUsername.isEmpty, !password.isEmpty {
            try await authenticate(username: normalizedUsername, password: password, userAgent: userAgent)
        }
        return try await requestRank(callsign: normalized, userAgent: userAgent)
    }

    private func authenticate(username: String, password: String, userAgent: String) async throws {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUsername.isEmpty, !password.isEmpty else {
            throw QRZRankFetchFailure.authenticationRequired("")
        }
        if authenticatedUsername.caseInsensitiveCompare(normalizedUsername) == .orderedSame {
            return
        }

        if let authenticationTask {
            try await authenticationTask.value
            guard authenticatedUsername.caseInsensitiveCompare(normalizedUsername) == .orderedSame else {
                throw QRZRankFetchFailure.authenticationFailed("The active QRZ Rank session belongs to another account.")
            }
            return
        }

        let task = Task {
            try await performAuthentication(
                username: normalizedUsername,
                password: password,
                userAgent: userAgent
            )
        }
        authenticationTask = task
        do {
            try await task.value
            authenticationTask = nil
        } catch {
            authenticationTask = nil
            throw error
        }
    }

    private func performAuthentication(username normalizedUsername: String, password: String, userAgent: String) async throws {

        var request = URLRequest(url: baseURL.appendingPathComponent("api/auth/login"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": normalizedUsername,
            "password": password
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw QRZRankFetchFailure.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw QRZRankFetchFailure.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw QRZRankFetchFailure.authenticationFailed(Self.message(from: data))
        }
        authenticatedUsername = normalizedUsername
    }

    private func requestRank(callsign: String, userAgent: String) async throws -> QRZRankResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/rank/\(callsign)"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw QRZRankFetchFailure.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw QRZRankFetchFailure.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = Self.message(from: data)
            switch http.statusCode {
            case 401:
                throw QRZRankFetchFailure.authenticationRequired(message)
            case 403:
                let lower = message.lowercased()
                if lower.contains("guest") || lower.contains("free quer") || lower.contains("limit") {
                    throw QRZRankFetchFailure.guestLimit(message)
                }
                if lower.contains("subscription") || lower.contains("premium") || lower.contains("payment") {
                    throw QRZRankFetchFailure.subscriptionRequired(message)
                }
                throw QRZRankFetchFailure.authenticationRequired(message)
            case 404:
                throw QRZRankFetchFailure.callsignNotFound(callsign)
            case 429:
                throw QRZRankFetchFailure.rateLimited(message)
            default:
                throw QRZRankFetchFailure.server(status: http.statusCode, message: message)
            }
        }

        guard let decoded = try? JSONDecoder().decode(QRZRankResponse.self, from: data),
              decoded.callsign?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              decoded.hasRankingValue else {
            throw QRZRankFetchFailure.invalidResponse
        }
        return decoded
    }

    private static func message(from data: Data) -> String {
        if let payload = try? JSONDecoder().decode(QRZRankErrorPayload.self, from: data),
           !payload.bestMessage.isEmpty {
            return payload.bestMessage
        }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func isPlausibleCallsign(_ callsign: String) -> Bool {
        guard (3...16).contains(callsign.count),
              callsign.contains(where: \.isLetter),
              callsign.contains(where: \.isNumber) else { return false }
        return callsign.allSatisfy { $0.isLetter || $0.isNumber || $0 == "/" || $0 == "-" }
    }
}

nonisolated extension QRZRankResponse {
    var hasRankingValue: Bool {
        [rank_qso, rank_band, rank_countries, score_qso, score_band, score_countries]
            .contains { value in
                !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
    }

    init(snapshot: QRZRankHistorySnapshot) {
        self.init(
            bid: nil,
            callsign: snapshot.callsign,
            country_iso: snapshot.countryIso,
            country_name: nil,
            rank_band: snapshot.bandRank.map { "#\($0)" },
            rank_countries: snapshot.dxccRank.map { "#\($0)" },
            rank_qso: snapshot.qsoRank.map { "#\($0)" },
            score_band: snapshot.bandScore.map(String.init),
            score_countries: snapshot.dxccScore.map(String.init),
            score_qso: snapshot.qsoScore.map(String.init)
        )
    }

    static func placeholder(callsign: String) -> QRZRankResponse {
        QRZRankResponse(
            bid: nil,
            callsign: callsign,
            country_iso: nil,
            country_name: nil,
            rank_band: nil,
            rank_countries: nil,
            rank_qso: nil,
            score_band: nil,
            score_countries: nil,
            score_qso: nil
        )
    }
}
