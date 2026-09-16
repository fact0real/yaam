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

    static let hfBands        = ["160m", "80m", "40m", "20m", "15m", "10m"]
    static let warcBands       = ["30m", "17m", "12m"]
    static let classic5Bands   = ["80m", "40m", "20m", "15m", "10m"]
    static let all9Bands       = ["160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m"]
    static let challengeBands  = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"]
    static let allBands        = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "2m", "70cm"]

    // DXCC counts
    var totalWorked: Int    { entities.filter { $0.isWorked }.count }
    var totalConfirmed: Int { entities.filter { $0.isConfirmed }.count }

    // Continent sets
    var continentsConfirmed: Set<String> {
        Set(entities.filter { $0.isConfirmed }.map { $0.continent.uppercased() }.filter { !$0.isEmpty })
    }
    var continentsWorked: Set<String> {
        Set(entities.filter { $0.isWorked }.map { $0.continent.uppercased() }.filter { !$0.isEmpty })
    }

    // CQ Zones (1..40)
    var cqZonesConfirmed: Set<Int> {
        Set(entities.filter { $0.isConfirmed && $0.cqZone >= 1 && $0.cqZone <= 40 }.map { $0.cqZone })
    }
    var cqZonesWorked: Set<Int> {
        Set(entities.filter { $0.isWorked && $0.cqZone >= 1 && $0.cqZone <= 40 }.map { $0.cqZone })
    }

    // DXCC Challenge Points (Total confirmed band-entities across 160m..6m)
    var dxccChallengePoints: Int {
        Self.challengeBands.reduce(0) { $0 + confirmedCount(band: $1) }
    }

    // 5-Band DXCC stats (80m, 40m, 20m, 15m, 10m)
    var fiveBandDXCCCompletedBands: Int {
        Self.classic5Bands.filter { confirmedCount(band: $0) >= 100 }.count
    }
    var fiveBandDXCCSlots: Int {
        Self.classic5Bands.reduce(0) { $0 + min(100, confirmedCount(band: $1)) }
    }

    // 9-Band DXCC stats (160m..10m)
    var nineBandDXCCCompletedBands: Int {
        Self.all9Bands.filter { confirmedCount(band: $0) >= 100 }.count
    }

    // CDXC Challenges
    var cdxcLFPoints: Int {
        confirmedCount(band: "160m") + confirmedCount(band: "80m") + confirmedCount(band: "40m")
    }
    var cdxcHFPoints: Int {
        confirmedCount(band: "15m") + confirmedCount(band: "12m") + confirmedCount(band: "10m") + confirmedCount(band: "6m")
    }

    func confirmedCount(band: String) -> Int {
        entities.filter { $0.bands[band.lowercased()]?.confirmed == true }.count
    }
    func workedCount(band: String) -> Int {
        entities.filter { $0.bands[band.lowercased()]?.worked == true }.count
    }

    func continentConfirmedCount(_ code: String) -> Int {
        entities.filter { $0.continent.uppercased() == code.uppercased() && $0.isConfirmed }.count
    }
    func continentWorkedCount(_ code: String) -> Int {
        entities.filter { $0.continent.uppercased() == code.uppercased() && $0.isWorked }.count
    }

    static func empty(callsign: String = "") -> ClubLogDXCCMatrix {
        ClubLogDXCCMatrix(entities: [], callsign: callsign, fetchedAt: Date())
    }

    static func matrixFromLogbook(records: [QSORecordModel], callsign: String = "") -> ClubLogDXCCMatrix {
        guard !records.isEmpty else { return empty(callsign: callsign) }

        var entityMap: [String: (id: Int, name: String, prefix: String, continent: String, cqZone: Int, bands: [String: ClubLogBandStatus])] = [:]

        for r in records {
            let dxccStr = r["DXCC"].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dxccStr.isEmpty, dxccStr != "0", dxccStr != "UNKNOWN" else { continue }
            let adif = Int(dxccStr) ?? 0
            let cont = r["CONT"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let cqzStr = r["CQZ"].isEmpty ? r["CQZONE"] : r["CQZ"]
            let cqz = Int(cqzStr.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let country = r["COUNTRY"].isEmpty ? "DXCC \(dxccStr)" : r["COUNTRY"]
            let band = r["BAND"].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isConf = r.isConfirmed

            var current = entityMap[dxccStr] ?? (id: adif, name: country, prefix: dxccStr, continent: cont, cqZone: cqz, bands: [:])
            if current.continent.isEmpty && !cont.isEmpty { current.continent = cont }
            if current.cqZone == 0 && cqz > 0 { current.cqZone = cqz }

            if !band.isEmpty {
                let existing = current.bands[band]
                let nowWorked = true
                let nowConf = (existing?.confirmed == true) || isConf
                current.bands[band] = ClubLogBandStatus(worked: nowWorked, confirmed: nowConf)
            }
            entityMap[dxccStr] = current
        }

        let ents = entityMap.values.map {
            ClubLogDXCCEntity(id: $0.id, name: $0.name, prefix: $0.prefix, continent: $0.continent, cqZone: $0.cqZone, bands: $0.bands)
        }.sorted { $0.name < $1.name }

        return ClubLogDXCCMatrix(entities: ents, callsign: callsign, fetchedAt: Date())
    }

    // Convert to award summaries for display in QRZAwardsView
    func toAwardSummaries() -> [QRZAwardSummary] {
        var list: [QRZAwardSummary] = []

        let confirmed = totalConfirmed
        let worked    = totalWorked

        // Helper to construct awards consistently
        func makeAward(
            id: String,
            title: String,
            count: Int,
            target: Int,
            unit: String,
            detail: String,
            awardType: String
        ) -> QRZAwardSummary {
            let pct = target > 0 ? min(100.0, max(0.0, Double(count) / Double(target) * 100.0)) : 0.0
            let achieved = count >= target
            let status = achieved ? "✓ Achieved!" : "\(max(0, target - count)) \(unit) remaining"
            let achievement = "\(count) / \(target) \(unit)"
            return QRZAwardSummary(
                id: id,
                title: title,
                detail: detail,
                percentComplete: pct,
                status: status,
                earned: achieved,
                progressAvailable: true,
                achievement: achievement,
                awardType: awardType,
                ribbonURL: ""
            )
        }

        // 1. DXCC Mixed (340 Current Entities)
        let mixedStatus: String
        if confirmed >= 340 {
            mixedStatus = "🏆 #1 Honor Roll Achieved!"
        } else if confirmed >= 331 {
            mixedStatus = "🎖️ Honor Roll Achieved!"
        } else if confirmed >= 100 {
            mixedStatus = "✓ DXCC Achieved (\(331 - confirmed) to Honor Roll)"
        } else {
            mixedStatus = "\(max(0, 100 - confirmed)) to DXCC"
        }
        list.append(QRZAwardSummary(
            id: "cl_dxcc_mixed",
            title: "DXCC Mixed",
            detail: "\(confirmed) confirmed, \(worked) worked — 340 active DXCC entities",
            percentComplete: min(100.0, Double(confirmed) / 100.0 * 100.0),
            status: mixedStatus,
            earned: confirmed >= 100,
            progressAvailable: true,
            achievement: "\(confirmed) / 100 Entities (of 340)",
            awardType: "dxcc",
            ribbonURL: ""
        ))

        // 2. DXCC Challenge (Target 1,000 band-points across 160m–6m)
        let chalPoints = dxccChallengePoints
        let chalAchieved = chalPoints >= 1000
        let chalStatus: String
        if chalPoints >= 1500 {
            chalStatus = "🏆 1,500+ Challenge Medallion!"
        } else if chalPoints >= 1000 {
            chalStatus = "✓ 1,000 Plaque Achieved!"
        } else {
            chalStatus = "\(1000 - chalPoints) points remaining"
        }
        list.append(QRZAwardSummary(
            id: "cl_dxcc_challenge",
            title: "DXCC Challenge",
            detail: "\(chalPoints) band-entities confirmed across 160m–6m (ARRL/Club Log rules)",
            percentComplete: min(100.0, Double(chalPoints) / 1000.0 * 100.0),
            status: chalStatus,
            earned: chalAchieved,
            progressAvailable: true,
            achievement: "\(chalPoints) / 1,000 Points",
            awardType: "challenge",
            ribbonURL: ""
        ))

        // 3. 5-Band DXCC (5BDXCC) (80m, 40m, 20m, 15m, 10m with 100+ each)
        let fiveDone = fiveBandDXCCCompletedBands
        let fiveSlots = fiveBandDXCCSlots
        list.append(QRZAwardSummary(
            id: "cl_5bdxcc",
            title: "5-Band DXCC (5BDXCC)",
            detail: "80m: \(confirmedCount(band: "80m")), 40m: \(confirmedCount(band: "40m")), 20m: \(confirmedCount(band: "20m")), 15m: \(confirmedCount(band: "15m")), 10m: \(confirmedCount(band: "10m"))",
            percentComplete: min(100.0, Double(fiveSlots) / 500.0 * 100.0),
            status: fiveDone >= 5 ? "✓ 5BDXCC Achieved!" : "\(5 - fiveDone) band(s) remaining",
            earned: fiveDone >= 5,
            progressAvailable: true,
            achievement: "\(fiveDone) / 5 Bands (100+)",
            awardType: "5bdx",
            ribbonURL: ""
        ))

        // 4. 9-Band DXCC (9BDXCC) (160m to 10m classic + WARC)
        let nineDone = nineBandDXCCCompletedBands
        list.append(QRZAwardSummary(
            id: "cl_9bdxcc",
            title: "9-Band DXCC (9BDXCC)",
            detail: "\(nineDone) of 9 HF/WARC bands confirmed with 100+ entities",
            percentComplete: min(100.0, Double(nineDone) / 9.0 * 100.0),
            status: nineDone >= 9 ? "✓ 9BDXCC Achieved!" : "\(9 - nineDone) band(s) remaining",
            earned: nineDone >= 9,
            progressAvailable: true,
            achievement: "\(nineDone) / 9 Bands (100+)",
            awardType: "9bdx",
            ribbonURL: ""
        ))

        // 5. Worked All Zones (CQ WAZ - 40 Zones)
        let wazConf = cqZonesConfirmed.count
        let wazWrk  = cqZonesWorked.count
        list.append(QRZAwardSummary(
            id: "cl_cq_waz",
            title: "Worked All Zones (CQ WAZ)",
            detail: "\(wazConf) confirmed, \(wazWrk) worked of 40 CQ Zones",
            percentComplete: min(100.0, Double(wazConf) / 40.0 * 100.0),
            status: wazConf >= 40 ? "✓ 40 Zones Achieved!" : "\(40 - wazConf) zone(s) remaining",
            earned: wazConf >= 40,
            progressAvailable: true,
            achievement: "\(wazConf) / 40 Zones",
            awardType: "zone",
            ribbonURL: ""
        ))

        // 6. Worked All Continents (WAC)
        let wacConf = continentsConfirmed.count
        list.append(QRZAwardSummary(
            id: "cl_wac",
            title: "Worked All Continents (WAC)",
            detail: continentsConfirmed.isEmpty ? "No continents confirmed yet via Club Log" : "Confirmed: \(continentsConfirmed.sorted().joined(separator: ", "))",
            percentComplete: min(100.0, Double(wacConf) / 6.0 * 100.0),
            status: wacConf >= 6 ? "✓ WAC Achieved!" : "\(6 - wacConf) continent(s) remaining",
            earned: wacConf >= 6,
            progressAvailable: true,
            achievement: "\(wacConf) / 6 Continents",
            awardType: "continent",
            ribbonURL: ""
        ))

        // 7. Individual Band DXCC Awards (HF, WARC, VHF, UHF)
        let bandDefinitions: [(band: String, label: String, target: Int, note: String)] = [
            ("160m", "160m Topband",      100, "1.8 MHz MF"),
            ("80m",  "80m Band",          100, "3.5 MHz HF"),
            ("60m",  "60m Band",           50, "5.3 MHz HF"),
            ("40m",  "40m Band",          100, "7 MHz HF"),
            ("30m",  "30m WARC",          100, "10.1 MHz HF"),
            ("20m",  "20m Band",          100, "14 MHz HF"),
            ("17m",  "17m WARC",          100, "18.1 MHz HF"),
            ("15m",  "15m Band",          100, "21 MHz HF"),
            ("12m",  "12m WARC",          100, "24.9 MHz HF"),
            ("10m",  "10m Band",          100, "28 MHz HF"),
            ("6m",   "6m Magic Band",     100, "50 MHz VHF"),
            ("2m",   "2m VHF",             25, "144 MHz VHF"),
            ("70cm", "70cm UHF",           10, "432 MHz UHF")
        ]

        for def in bandDefinitions {
            let conf = confirmedCount(band: def.band)
            let wrk  = workedCount(band: def.band)
            list.append(QRZAwardSummary(
                id: "cl_dxcc_\(def.band)",
                title: "DXCC \(def.label)",
                detail: "\(conf) confirmed, \(wrk) worked on \(def.note)",
                percentComplete: min(100.0, Double(conf) / Double(def.target) * 100.0),
                status: conf >= def.target ? "✓ Achieved on \(def.band)!" : "\(max(0, def.target - conf)) entities remaining",
                earned: conf >= def.target,
                progressAvailable: true,
                achievement: "\(conf) / \(def.target) Entities",
                awardType: def.band.contains("m") && (def.band == "6m" || def.band == "2m" || def.band == "70cm") ? "vhf" : "band",
                ribbonURL: ""
            ))
        }

        // 8. Continental Awards
        let continents: [(code: String, title: String, target: Int)] = [
            ("EU", "Europe DXCC",        50),
            ("AS", "Asia DXCC",          40),
            ("AF", "Africa DXCC",        30),
            ("NA", "North America DXCC", 30),
            ("SA", "South America DXCC", 12),
            ("OC", "Oceania DXCC",       20)
        ]

        for c in continents {
            let conf = continentConfirmedCount(c.code)
            let wrk  = continentWorkedCount(c.code)
            list.append(makeAward(
                id: "cl_cont_\(c.code.lowercased())",
                title: c.title,
                count: conf,
                target: c.target,
                unit: "Entities",
                detail: "\(conf) confirmed, \(wrk) worked in \(c.code)",
                awardType: "geographic"
            ))
        }

        // 9. CDXC Challenges
        let lf = cdxcLFPoints
        list.append(makeAward(
            id: "cl_cdxc_lf",
            title: "CDXC LF Challenge",
            count: lf,
            target: 150,
            unit: "Points",
            detail: "\(lf) confirmed band-entities across 160m, 80m and 40m",
            awardType: "challenge"
        ))

        let hf = cdxcHFPoints
        list.append(makeAward(
            id: "cl_cdxc_hf",
            title: "CDXC HF Challenge",
            count: hf,
            target: 200,
            unit: "Points",
            detail: "\(hf) confirmed band-entities across 15m, 12m, 10m and 6m",
            awardType: "challenge"
        ))

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
