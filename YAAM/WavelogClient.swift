//
//  WavelogClient.swift
//  YAAM
//
//  REST API Client for Wavelog & Cloudlog Amateur Radio Logging Servers
//  Handles Station Info discovery, real-time live QSO Push, batch ADIF Sync,
//  and live Transceiver Frequency web broadcast.
//

import Foundation

public struct WavelogStationProfile: Identifiable, Codable, Sendable {
    public let stationID: String
    public let stationProfileName: String
    public let stationCallsign: String
    public let stationGridsquare: String

    public var id: String { stationID }

    enum CodingKeys: String, CodingKey {
        case stationID = "station_id"
        case stationProfileName = "station_profile_name"
        case stationCallsign = "station_callsign"
        case stationGridsquare = "station_gridsquare"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle station_id as string or integer
        if let idStr = try? container.decode(String.self, forKey: .stationID) {
            self.stationID = idStr
        } else if let idInt = try? container.decode(Int.self, forKey: .stationID) {
            self.stationID = String(idInt)
        } else {
            self.stationID = "1"
        }

        self.stationProfileName = (try? container.decode(String.self, forKey: .stationProfileName)) ?? "Station \(stationID)"
        self.stationCallsign = (try? container.decode(String.self, forKey: .stationCallsign)) ?? ""
        self.stationGridsquare = (try? container.decode(String.self, forKey: .stationGridsquare)) ?? ""
    }

    public init(stationID: String, stationProfileName: String, stationCallsign: String, stationGridsquare: String) {
        self.stationID = stationID
        self.stationProfileName = stationProfileName
        self.stationCallsign = stationCallsign
        self.stationGridsquare = stationGridsquare
    }
}

public struct WavelogAPIResponse: Codable, Sendable {
    public let status: String?
    public let message: String?
    public let reason: String?
}

public enum WavelogError: LocalizedError, Sendable {
    case invalidURL
    case missingAPIKey
    case httpError(statusCode: Int, message: String)
    case serverRejected(reason: String)
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Wavelog / Cloudlog server URL."
        case .missingAPIKey: return "API Key is missing. Please configure it in Settings."
        case .httpError(let code, let msg): return "HTTP Error \(code): \(msg)"
        case .serverRejected(let reason): return "Server rejected request: \(reason)"
        case .decodingFailed: return "Failed to decode response from Wavelog / Cloudlog server."
        }
    }
}

public final class WavelogClient: Sendable {
    public static let shared = WavelogClient()

    private let urlSession: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - URL Normalization & Routing

    private func buildEndpointURL(baseURL: String, path: String) -> URL? {
        var cleanBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanBase.lowercased().hasPrefix("http://") && !cleanBase.lowercased().hasPrefix("https://") {
            cleanBase = "https://" + cleanBase
        }
        if cleanBase.hasSuffix("/") {
            cleanBase = String(cleanBase.dropLast())
        }

        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: "\(cleanBase)/\(cleanPath)")
    }

    // MARK: - Station Info Discovery

    public func fetchStationProfiles(baseURL: String, apiKey: String) async throws -> [WavelogStationProfile] {
        guard !apiKey.isEmpty else { throw WavelogError.missingAPIKey }

        // Try direct /api/station_info first, then fallback to /index.php/api/station_info
        let endpoints = ["api/station_info", "index.php/api/station_info"]

        var lastError: Error = WavelogError.invalidURL

        for endpoint in endpoints {
            guard let url = buildEndpointURL(baseURL: baseURL, path: endpoint) else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("YAAM-macOS-WavelogClient/1.0", forHTTPHeaderField: "User-Agent")

            let payload: [String: Any] = ["key": apiKey]
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { continue }

                if (200...299).contains(httpResponse.statusCode) {
                    if let profiles = try? JSONDecoder().decode([WavelogStationProfile].self, from: data) {
                        return profiles
                    }
                }
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    // MARK: - Real-Time Single QSO Push

    func pushQSO(
        record: QSORecordModel,
        baseURL: String,
        apiKey: String,
        stationProfileID: String
    ) async throws -> Bool {
        guard !apiKey.isEmpty else { throw WavelogError.missingAPIKey }

        let adifString = formatSingleADIF(record)
        let endpoints = ["api/qso", "index.php/api/qso"]

        for endpoint in endpoints {
            guard let url = buildEndpointURL(baseURL: baseURL, path: endpoint) else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("YAAM-macOS-WavelogClient/1.0", forHTTPHeaderField: "User-Agent")

            let payload: [String: Any] = [
                "key": apiKey,
                "station_profile_id": stationProfileID,
                "type": "adif",
                "string": adifString
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { continue }

                if let res = try? JSONDecoder().decode(WavelogAPIResponse.self, from: data) {
                    if res.status?.lowercased() == "successful" || res.status?.lowercased() == "created" {
                        return true
                    }
                }
                return true
            } catch {
                continue
            }
        }

        throw WavelogError.serverRejected(reason: "Failed to push QSO to Wavelog.")
    }

    // MARK: - Batch ADIF Upload

    public func uploadBatchADIF(
        adifContent: String,
        baseURL: String,
        apiKey: String,
        stationProfileID: String
    ) async throws -> (success: Bool, message: String) {
        guard !apiKey.isEmpty else { throw WavelogError.missingAPIKey }

        let endpoints = ["api/adif", "index.php/api/adif"]

        for endpoint in endpoints {
            guard let url = buildEndpointURL(baseURL: baseURL, path: endpoint) else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let payload: [String: Any] = [
                "key": apiKey,
                "station_profile_id": stationProfileID,
                "type": "adif",
                "string": adifContent
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { continue }

                let raw = String(data: data, encoding: .utf8) ?? ""
                return (true, "Batch upload successful. (\(raw))")
            } catch {
                continue
            }
        }

        throw WavelogError.serverRejected(reason: "Batch ADIF upload failed.")
    }

    // MARK: - Export / Pull ADIF from Server

    public func exportADIF(
        baseURL: String,
        apiKey: String,
        stationProfileID: String
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw WavelogError.missingAPIKey }

        let endpoints = ["api/adif_export", "index.php/api/adif_export"]

        for endpoint in endpoints {
            guard let url = buildEndpointURL(baseURL: baseURL, path: endpoint) else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let payload: [String: Any] = [
                "key": apiKey,
                "station_profile_id": stationProfileID,
                "fetch_all": true
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { continue }

                if let adifString = String(data: data, encoding: .utf8), !adifString.isEmpty {
                    return adifString
                }
            } catch {
                continue
            }
        }

        throw WavelogError.serverRejected(reason: "Could not export ADIF from Wavelog.")
    }

    // MARK: - Live Radio CAT Telemetry Broadcast

    public func broadcastRadio(
        baseURL: String,
        apiKey: String,
        radioName: String,
        frequencyHz: Double,
        mode: String,
        powerWatts: Double = 100.0
    ) async throws -> Bool {
        guard !apiKey.isEmpty else { return false }

        let endpoints = ["api/radio", "index.php/api/radio"]
        for endpoint in endpoints {
            guard let url = buildEndpointURL(baseURL: baseURL, path: endpoint) else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let payload: [String: Any] = [
                "key": apiKey,
                "radio": radioName,
                "frequency": Int(frequencyHz),
                "mode": mode,
                "power": Int(powerWatts),
                "prop_mode": ""
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            if let (_, response) = try? await urlSession.data(for: request),
               let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return true
            }
        }
        return false
    }

    // MARK: - Helper ADIF Formatter

    private func formatSingleADIF(_ record: QSORecordModel) -> String {
        var adif = ""
        for (key, val) in record.fields {
            let cleanVal = val.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanVal.isEmpty {
                adif += "<\(key):\(cleanVal.utf8.count)>\(cleanVal) "
            }
        }
        adif += "<EOR>"
        return adif
    }
}
