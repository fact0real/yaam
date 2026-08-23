//
//  QRZRankService.swift
//  YAAM
//

import Foundation

nonisolated struct QRZRankServiceCredentials: Sendable {
    var token: String

    var isConfigured: Bool {
        !QRZRankAPIContract.normalizedToken(token).isEmpty
    }
}

nonisolated enum QRZRankFetchFailure: LocalizedError, Equatable, Sendable {
    case invalidCallsign
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
        case .authenticationRequired(let message):
            return message.isEmpty
                ? "Add your personal QRZ Rank API token in Settings > Rank Service."
                : message
        case .authenticationFailed(let message):
            return message.isEmpty
                ? "The QRZ Rank API token is invalid or has been revoked."
                : message
        case .subscriptionRequired(let message):
            return message.isEmpty
                ? "QRZ Rank API access requires active supporter or unlimited access."
                : message
        case .callsignNotFound(let callsign):
            return "No QRZ ranking was found for \(callsign)."
        case .dailyLimitReached(let limit):
            return "The daily QRZ Rank limit of \(limit) requests has been reached. It resets at local midnight."
        case .rateLimited(let message):
            return message.isEmpty
                ? "The shared QRZ Rank daily quota has been reached. Try again after it resets."
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
        case .authenticationRequired, .authenticationFailed,
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
        case .authenticationRequired, .authenticationFailed,
             .subscriptionRequired, .dailyLimitReached, .rateLimited,
             .server, .transport, .invalidResponse:
            return false
        }
    }
}

actor QRZRankService {
    static let shared = QRZRankService()

    private let session: URLSession
    private(set) var latestQuota: QRZRankAPIQuota?

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func fetchRank(
        callsign: String,
        token: String,
        userAgent: String
    ) async throws -> QRZRankResponse {
        let normalized = QRZRankAPIContract.normalizedCallsign(callsign)
        let request: URLRequest
        do {
            request = try QRZRankAPIContract.makeRequest(
                callsign: normalized,
                token: token,
                userAgent: userAgent
            )
        } catch QRZRankAPIContractError.invalidCallsign {
            throw QRZRankFetchFailure.invalidCallsign
        } catch QRZRankAPIContractError.missingToken {
            throw QRZRankFetchFailure.authenticationRequired("")
        } catch QRZRankAPIContractError.malformedToken {
            throw QRZRankFetchFailure.authenticationFailed("The saved QRZ Rank API token is malformed. Save it again in Settings > Rank Service.")
        } catch {
            throw QRZRankFetchFailure.invalidResponse
        }

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
            let details = QRZRankAPIContract.decodeError(data)
            let message = details?.message ?? ""
            switch http.statusCode {
            case 400:
                if details?.code == "invalid_callsign" {
                    throw QRZRankFetchFailure.invalidCallsign
                }
                throw QRZRankFetchFailure.server(status: http.statusCode, message: message)
            case 401:
                throw QRZRankFetchFailure.authenticationFailed(message)
            case 403:
                throw QRZRankFetchFailure.subscriptionRequired(message)
            case 404:
                throw QRZRankFetchFailure.callsignNotFound(normalized)
            case 429:
                throw QRZRankFetchFailure.rateLimited(message)
            default:
                throw QRZRankFetchFailure.server(status: http.statusCode, message: message)
            }
        }

        let envelope: QRZRankAPIEnvelope
        do {
            envelope = try QRZRankAPIContract.decodeSuccess(data)
        } catch {
            throw QRZRankFetchFailure.invalidResponse
        }
        latestQuota = envelope.quota
        return envelope.data
    }
}

nonisolated extension QRZRankResponse {
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
