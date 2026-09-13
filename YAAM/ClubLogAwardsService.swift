//
//  ClubLogAwardsService.swift
//  YAAM
//
//  Fetches personal DXCC matrix from Club Log's JSON API
//  Endpoint: https://clublog.org/json_dxccchart.php
//

import Foundation

// MARK: - Data Models

nonisolated struct ClubLogBandStatus: Sendable {
    let worked: Bool
    let confirmed: Bool
}

nonisolated struct ClubLogDXCCEntity: Identifiable, Sendable {
    let id: Int           // ADIF number
    let name: String
    let prefix: String
    let continent: String
    let cqZone: Int
    let bands: [String: ClubLogBandStatus]

    var isWorked: Bool    { bands.values.contains { $0.worked } }
    var isConfirmed: Bool { bands.values.contains { $0.confirmed } }

    var confirmedBands: [String] {
        bands.filter { $0.value.confirmed }.keys.sorted { Self.bandOrder($0) < Self.bandOrder($1) }
    }
    var workedBands: [String] {
        bands.filter { $0.value.worked }.keys.sorted { Self.bandOrder($0) < Self.bandOrder($1) }
    }

    static func bandOrder(_ band: String) -> Int {
        let order = ["160m": 0, "80m": 1, "60m": 2, "40m": 3, "30m": 4, "20m": 5,
                     "17m": 6, "15m": 7, "12m": 8, "10m": 9, "6m": 10, "2m": 11, "70cm": 12]
        return order[band.lowercased()] ?? 99
    }
}

nonisolated struct ClubLogDXCCMatrix: Sendable {
    let entities: [ClubLogDXCCEntity]
    let callsign: String
    let fetchedAt: Date
    var statusMessage: String = ""

    static let hfBands  = ["160m", "80m", "40m", "20m", "15m", "10m"]
    static let allBands = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "2m"]

    // DXCC counts
    var totalWorked: Int    { entities.filter { $0.isWorked }.count }
    var totalConfirmed: Int { entities.filter { $0.isConfirmed }.count }

    // Continent sets
    var continentsConfirmed: Set<String> {
        Set(entities.filter { $0.isConfirmed }.map { $0.continent }.filter { !$0.isEmpty })
    }
    var continentsWorked: Set<String> {
        Set(entities.filter { $0.isWorked }.map { $0.continent }.filter { !$0.isEmpty })
    }

    func confirmedCount(band: String) -> Int {
        entities.filter { $0.bands[band.lowercased()]?.confirmed == true }.count
    }
    func workedCount(band: String) -> Int {
        entities.filter { $0.bands[band.lowercased()]?.worked == true }.count
    }

    // Convert to award summaries for display in QRZAwardsView
    func toAwardSummaries() -> [QRZAwardSummary] {
        var list: [QRZAwardSummary] = []

        let confirmed = totalConfirmed
        let worked    = totalWorked

        // 1. DXCC Mixed
        list.append(QRZAwardSummary(
            id: "cl_dxcc_mixed",
            title: "DXCC Mixed",
            detail: "\(confirmed) confirmed, \(worked) worked — 331 current entities",
            percentComplete: min(100, Double(confirmed) / 3.31),
            status: confirmed >= 100 ? (confirmed >= 331 ? "Honor Roll!" : "Honor Roll candidate") : "\(max(0, 100 - confirmed)) to DXCC",
            earned: confirmed >= 100,
            progressAvailable: true,
            achievement: "\(confirmed) / 331 Entities",
            awardType: "dxcc",
            ribbonURL: ""
        ))

        // 2. Per-HF-band DXCC
        for band in ClubLogDXCCMatrix.hfBands {
            let conf = confirmedCount(band: band)
            let wrk  = workedCount(band: band)
            guard wrk > 0 || conf > 0 else { continue }
            list.append(QRZAwardSummary(
                id: "cl_dxcc_\(band)",
                title: "DXCC \(band.uppercased())",
                detail: "\(conf) confirmed, \(wrk) worked on \(band)",
                percentComplete: min(100, Double(conf) / 1.0),
                status: conf >= 100 ? "DXCC achieved on \(band)!" : "\(conf) confirmed",
                earned: conf >= 100,
                progressAvailable: false,
                achievement: "\(conf) Confirmed on \(band)",
                awardType: "dxcc",
                ribbonURL: ""
            ))
        }

        // 3. WAC via ClubLog
        let wacConf = continentsConfirmed.count
        list.append(QRZAwardSummary(
            id: "cl_wac",
            title: "Worked All Continents",
            detail: "Confirmed: \(continentsConfirmed.sorted().joined(separator: ", "))",
            percentComplete: min(100, Double(wacConf) / 6.0 * 100),
            status: wacConf >= 6 ? "WAC Achieved!" : "\(6 - wacConf) continent(s) remaining",
            earned: wacConf >= 6,
            progressAvailable: true,
            achievement: "\(wacConf) / 6 Continents",
            awardType: "continent",
            ribbonURL: ""
        ))

        // 4. 6m DXCC
        let sixConf = confirmedCount(band: "6m")
        let sixWrk  = workedCount(band: "6m")
        if sixWrk > 0 || sixConf > 0 {
            list.append(QRZAwardSummary(
                id: "cl_dxcc_6m",
                title: "DXCC 6m (Magic Band)",
                detail: "\(sixConf) confirmed, \(sixWrk) worked on 50 MHz",
                percentComplete: min(100, Double(sixConf) / 1.0),
                status: sixConf >= 100 ? "6m DXCC achieved!" : "\(sixConf) entities confirmed",
                earned: sixConf >= 100,
                progressAvailable: false,
                achievement: "\(sixConf) Confirmed on 6m",
                awardType: "vhf",
                ribbonURL: ""
            ))
        }

        return list
    }
}

// MARK: - Error

enum ClubLogAwardsError: LocalizedError {
    case missingCredentials
    case networkError(String)
    case parseError(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "ClubLog API key or callsign not configured. Go to Settings → Integrations → Club Log."
        case .networkError(let m): return "Network error: \(m)"
        case .parseError(let m):   return "Could not parse ClubLog response: \(m)"
        case .apiError(let m):     return "Club Log API: \(m)"
        }
    }
}

// MARK: - Service Actor

actor ClubLogAwardsService {
    static let shared = ClubLogAwardsService()
    private let cacheKey = "clubLogDXCCMatrix.v2"

    func fetchDXCCMatrix(
        callsign: String,
        apiKey: String,
        email: String = "",
        password: String = ""
    ) async throws -> ClubLogDXCCMatrix {
        guard !callsign.isEmpty, !apiKey.isEmpty else {
            throw ClubLogAwardsError.missingCredentials
        }

        var items: [URLQueryItem] = [
            URLQueryItem(name: "call",  value: callsign.uppercased()),
            URLQueryItem(name: "api",   value: apiKey),
            URLQueryItem(name: "mode",  value: "0")
        ]
        if !email.isEmpty    { items.append(URLQueryItem(name: "email",    value: email)) }
        if !password.isEmpty { items.append(URLQueryItem(name: "password", value: password)) }

        var components = URLComponents(string: "https://clublog.org/json_dxccchart.php")!
        components.queryItems = items

        guard let url = components.url else {
            throw ClubLogAwardsError.networkError("Could not build request URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("YAAM/2.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ClubLogAwardsError.networkError("HTTP \(http.statusCode)")
        }

        let matrix = try parseMatrix(data: data, callsign: callsign)
        cacheMatrix(matrix)
        return matrix
    }

    func loadCachedMatrix() -> ClubLogDXCCMatrix? {
        guard let data   = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(CachedMatrix.self, from: data),
              Date().timeIntervalSince(cached.fetchedAt) < 86400 else { return nil }
        return cached.toMatrix()
    }

    // MARK: Private

    private func cacheMatrix(_ matrix: ClubLogDXCCMatrix) {
        let cached = CachedMatrix(from: matrix)
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func parseMatrix(data: Data, callsign: String) throws -> ClubLogDXCCMatrix {
        // Check for text-based error first
        if let str = String(data: data, encoding: .utf8) {
            let lower = str.lowercased()
            if lower.hasPrefix("error") || lower.hasPrefix("invalid") || lower.hasPrefix("not found") {
                throw ClubLogAwardsError.apiError(String(str.prefix(300)))
            }
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClubLogAwardsError.parseError("Expected JSON object but got different format")
        }

        // ClubLog may return top-level error keys
        if let err = json["Error"] as? String { throw ClubLogAwardsError.apiError(err) }
        if let err = json["error"] as? String { throw ClubLogAwardsError.apiError(err) }

        let bandKeys = ["160m", "80m", "60m", "40m", "30m", "20m",
                        "17m", "15m", "12m", "10m", "6m", "2m", "70cm"]

        var entities: [ClubLogDXCCEntity] = []

        for (prefix, rawVal) in json {
            guard let entityData = rawVal as? [String: Any] else { continue }

            let adif = entityData["Adif"] as? Int ?? 0
            let name = entityData["Name"] as? String ?? prefix
            let cont = entityData["Cont"] as? String ?? ""
            let cqz  = entityData["CQZ"]  as? Int ?? 0

            var bands: [String: ClubLogBandStatus] = [:]
            for band in bandKeys {
                // ClubLog uses capitalized band keys like "40m" but let's be safe
                let key = band
                guard let bandData = entityData[key] as? [String: Any] else { continue }
                let w = boolFromAny(bandData["Worked"])
                let c = boolFromAny(bandData["Confirmed"])
                if w || c { bands[band] = ClubLogBandStatus(worked: w, confirmed: c) }
            }

            guard !bands.isEmpty else { continue }

            entities.append(ClubLogDXCCEntity(
                id: adif, name: name, prefix: prefix,
                continent: cont, cqZone: cqz, bands: bands
            ))
        }

        entities.sort { $0.name < $1.name }
        return ClubLogDXCCMatrix(entities: entities, callsign: callsign, fetchedAt: Date())
    }

    private func boolFromAny(_ val: Any?) -> Bool {
        if let b = val as? Bool { return b }
        if let i = val as? Int  { return i > 0 }
        return false
    }
}

// MARK: - Cache Codable

private nonisolated struct CachedMatrix: Codable, Sendable {
    let callsign: String
    let fetchedAt: Date
    let entities: [CE]

    struct CE: Codable, Sendable {
        let id: Int; let name: String; let prefix: String
        let continent: String; let cqZone: Int
        let bands: [String: CBS]
    }
    struct CBS: Codable, Sendable { let worked: Bool; let confirmed: Bool }

    init(from m: ClubLogDXCCMatrix) {
        callsign  = m.callsign
        fetchedAt = m.fetchedAt
        entities  = m.entities.map { e in
            CE(id: e.id, name: e.name, prefix: e.prefix, continent: e.continent, cqZone: e.cqZone,
               bands: e.bands.mapValues { CBS(worked: $0.worked, confirmed: $0.confirmed) })
        }
    }

    func toMatrix() -> ClubLogDXCCMatrix {
        let ents = entities.map { e in
            ClubLogDXCCEntity(id: e.id, name: e.name, prefix: e.prefix,
                              continent: e.continent, cqZone: e.cqZone,
                              bands: e.bands.mapValues { ClubLogBandStatus(worked: $0.worked, confirmed: $0.confirmed) })
        }
        return ClubLogDXCCMatrix(entities: ents, callsign: callsign, fetchedAt: fetchedAt)
    }
}
