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

/// Keys in station_info/check_auth URLs must never follow a redirect or enter the shared disk cache.
private final class WavelogSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum WavelogKeyRights: String, Sendable {
    case readOnly = "r"
    case readWrite = "rw"
}

public final class WavelogClient: Sendable {
    public static let shared = WavelogClient()
    private let urlSession: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.urlSession = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 60
            config.urlCache = nil
            config.httpCookieStorage = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.urlSession = URLSession(configuration: config, delegate: WavelogSessionDelegate(), delegateQueue: nil)
        }
    }

    private func buildEndpointURL(baseURL: String, path: String, pathKey: String?) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.contains("://") { base = "https://" + base }
        guard var parts = URLComponents(string: base),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return nil }
        parts.percentEncodedPath = parts.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .isEmpty ? "" : "/" + parts.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.percentEncodedPath += "/" + path
        if let pathKey {
            guard let encoded = pathKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
            parts.percentEncodedPath += "/" + encoded
        }
        return parts.url
    }

    /// Only route-not-found errors try index.php. Never repeat a possibly accepted write after a transport error.
    /// Error messages deliberately contain only the fixed API route, never URLs, keys or server-echoed QSO data.
    private func request(baseURL: String, route: String, apiKey: String,
                         pathKey: Bool = false, payload: [String: Any]? = nil) async throws -> (Data, Int) {
        guard !apiKey.isEmpty else { throw WavelogError.missingAPIKey }
        for prefix in ["api/", "index.php/api/"] {
            try Task.checkCancellation()
            guard let url = buildEndpointURL(baseURL: baseURL, path: prefix + route, pathKey: pathKey ? apiKey : nil) else {
                throw WavelogError.invalidURL
            }
            var request = URLRequest(url: url)
            request.httpMethod = pathKey ? "GET" : "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("YAAM-macOS-WavelogClient/1.0", forHTTPHeaderField: "User-Agent")
            if let payload { request.httpBody = try JSONSerialization.data(withJSONObject: payload) }
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await urlSession.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw WavelogError.serverRejected(reason: "Network request to api/\(route) failed; check the server connection.")
            }
            guard let http = response as? HTTPURLResponse else { throw WavelogError.decodingFailed }
            if WavelogPushOutcome.shouldTryFallbackEndpoint(statusCode: http.statusCode), prefix == "api/" { continue }
            return (data, http.statusCode)
        }
        throw WavelogError.invalidURL
    }

    private func requireHTTP(_ status: Int, route: String) throws {
        guard (200...299).contains(status) else {
            throw WavelogError.httpError(statusCode: status, message: "api/\(route)")
        }
    }

    /// Read-only authentication check; this does not create, edit or upload any QSO.
    public func checkAuth(baseURL: String, apiKey: String) async throws -> WavelogKeyRights {
        let (data, status) = try await request(baseURL: baseURL, route: "check_auth", apiKey: apiKey, pathKey: true)
        try requireHTTP(status, route: "check_auth")
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["status"] as? String == "valid", let raw = json["rights"] as? String,
              let rights = WavelogKeyRights(rawValue: raw) else { throw WavelogError.decodingFailed }
        return rights
    }

    public func fetchStationProfiles(baseURL: String, apiKey: String) async throws -> [WavelogStationProfile] {
        let (data, status) = try await request(baseURL: baseURL, route: "station_info", apiKey: apiKey, pathKey: true)
        try requireHTTP(status, route: "station_info")
        guard let profiles = try? JSONDecoder().decode([WavelogStationProfile].self, from: data) else {
            throw WavelogError.decodingFailed
        }
        return profiles
    }

    func pushQSO(record: QSORecordModel, baseURL: String, apiKey: String, stationProfileID: String) async -> WavelogPushOutcome {
        guard !apiKey.isEmpty else { return .notConfigured }
        do {
            return try await pushADIF(formatSingleADIF(record), baseURL: baseURL, apiKey: apiKey, stationProfileID: stationProfileID)
        } catch WavelogError.invalidURL {
            return .rejected("Invalid Wavelog server URL.")
        } catch is CancellationError {
            return .rejected("Wavelog upload cancelled; acceptance was not confirmed.")
        } catch {
            return .networkError(error.localizedDescription)
        }
    }

    private func pushADIF(_ adif: String, baseURL: String, apiKey: String, stationProfileID: String) async throws -> WavelogPushOutcome {
        let (data, status) = try await request(baseURL: baseURL, route: "qso", apiKey: apiKey, payload: [
            "key": apiKey, "station_profile_id": stationProfileID, "type": "adif", "string": adif
        ])
        let outcome = WavelogPushOutcome.classify(statusCode: status, body: data)
        // The server may echo the request in its error: do not store that in YAAM's outbox or diagnostics.
        switch outcome {
        case .rejected: return .rejected("api/qso refused the upload (HTTP \(status)); check key write rights and station profile.")
        case .networkError: return .networkError("api/qso is temporarily unavailable (HTTP \(status)).")
        default: return outcome
        }
    }

    public func uploadBatchADIF(adifContent: String, baseURL: String, apiKey: String,
                                stationProfileID: String) async throws -> (success: Bool, message: String) {
        let (_, records) = parseADIF(content: adifContent)
        guard !records.isEmpty else { throw WavelogError.serverRejected(reason: "No QSOs to upload.") }
        // A final privacy boundary also covers callers supplying a prebuilt ADIF file.
        let safe = generateADIF(originalContent: "", records: records.map { QSLUploadStatus.uploadFields($0, for: .wavelog) })
        let outcome = try await pushADIF(safe, baseURL: baseURL, apiKey: apiKey, stationProfileID: stationProfileID)
        guard outcome.isDelivered else { throw WavelogError.serverRejected(reason: outcome.message) }
        return (true, outcome == .duplicate ? "QSOs already in Wavelog." : "Wavelog accepted the batch upload.")
    }

    /// The v1 export is JSON-wrapped and bounded by the server. Follow its cursor until an empty page.
    public func exportADIF(baseURL: String, apiKey: String, stationProfileID: String) async throws -> String {
        var cursor = 0
        var records: [[String: String]] = []
        var bytes = 0
        for _ in 0..<100 {
            let (data, status) = try await request(baseURL: baseURL, route: "get_contacts_adif", apiKey: apiKey, payload: [
                "key": apiKey, "station_id": stationProfileID, "fetchfromid": cursor
            ])
            try requireHTTP(status, route: "get_contacts_adif")
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  json["status"] as? String == "successful",
                  let count = json["exported_qsos"] as? Int, count >= 0,
                  let next = json["lastfetchedid"] as? Int else { throw WavelogError.decodingFailed }
            if count == 0 { return records.isEmpty ? "" : generateADIF(originalContent: "", records: records) }
            guard let adif = json["adif"] as? String else { throw WavelogError.decodingFailed }
            guard next > cursor else { throw WavelogError.serverRejected(reason: "api/get_contacts_adif returned a non-advancing cursor.") }
            let (_, page) = parseADIF(content: adif)
            guard page.count == count else { throw WavelogError.decodingFailed }
            bytes += adif.utf8.count
            guard bytes <= 64 * 1024 * 1024 else { throw WavelogError.serverRejected(reason: "Wavelog export exceeds the 64 MB safety limit.") }
            records.append(contentsOf: page)
            cursor = next
        }
        throw WavelogError.serverRejected(reason: "Wavelog export exceeded 100 pages; no partial log was imported.")
    }

    public func broadcastRadio(baseURL: String, apiKey: String, radioName: String, frequencyHz: Double,
                               mode: String, powerWatts: Double = 100) async throws -> Bool {
        guard frequencyHz.isFinite, frequencyHz > 0, frequencyHz < Double(Int.max),
              powerWatts.isFinite, powerWatts >= 0, powerWatts < Double(Int.max) else { return false }
        let (_, status) = try await request(baseURL: baseURL, route: "radio", apiKey: apiKey, payload: [
            "key": apiKey, "radio": radioName, "frequency": Int(frequencyHz), "mode": mode,
            "power": Int(powerWatts), "prop_mode": ""
        ])
        try requireHTTP(status, route: "radio")
        return true
    }

    // MARK: - Helper ADIF Formatter

    private func formatSingleADIF(_ record: QSORecordModel) -> String {
        var adif = ""
        // Only the fields Wavelog may get, with the comment cleaned (QSLUploadStatus.uploadFields).
        var normalizedFields = QSLUploadStatus.uploadFields(record.fields, for: .wavelog)
        let currentMode = normalizedFields["MODE"] ?? ""
        let currentSubmode = normalizedFields["SUBMODE"] ?? ""
        let freq = Double(normalizedFields["FREQ"] ?? "")
        let effective = AmateurBandPlan.effectiveADIFMode(mode: currentMode, submode: currentSubmode, frequencyMHz: freq)
        if !effective.isEmpty {
            normalizedFields["MODE"] = effective
            if effective == "FT8" || effective == "FT4" || effective == "JS8" {
                normalizedFields["SUBMODE"] = effective
            }
        }
        for (key, val) in normalizedFields {
            let cleanVal = val.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanVal.isEmpty {
                adif += "<\(key):\(cleanVal.utf8.count)>\(cleanVal) "
            }
        }
        adif += "<EOR>"
        return adif
    }
}
