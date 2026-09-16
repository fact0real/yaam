//
//  ClubLogLeagueService.swift
//  YAAM
//
//  Fetches DXCC League rankings from Club Log API
//  Endpoint: https://clublog.org/league_api.php
//

import Foundation

// MARK: - Enums

public enum ClubLogLeagueMode: Int, CaseIterable, Identifiable, Sendable {
    case mixed = 0
    case cw    = 1
    case phone = 2
    case data  = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .mixed: return "All Modes"
        case .cw:    return "CW"
        case .phone: return "Phone (SSB)"
        case .data:  return "Digital"
        }
    }

    public var icon: String {
        switch self {
        case .mixed: return "waveform.badge.magnifyingglass"
        case .cw:    return "dot.radiowaves.left.and.right"
        case .phone: return "mic.fill"
        case .data:  return "waveform"
        }
    }
}

public enum ClubLogLeagueQSL: Int, CaseIterable, Identifiable, Sendable {
    case confirmed = 1
    case worked    = 0

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .confirmed: return "Confirmed"
        case .worked:    return "Worked"
        }
    }

    public var icon: String {
        switch self {
        case .confirmed: return "checkmark.seal.fill"
        case .worked:    return "antenna.radiowaves.left.and.right"
        }
    }
}

public enum ClubLogLeagueDate: Int, CaseIterable, Identifiable, Sendable {
    case allTime      = 0
    case thisYear     = 3
    case last12Months = 1
    case lastYear     = 4

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .allTime:      return "All Time"
        case .thisYear:     return "This Year"
        case .last12Months: return "12 Months"
        case .lastYear:     return "Last Year"
        }
    }
}

// MARK: - Entry Model

public struct ClubLogLeagueEntry: Identifiable, Sendable, Equatable {
    public var id: String { "\(rank)-\(callsign)" }
    public let rank: Int
    public let callsign: String
    public let dxccs: Int
    public let slots: Int
    public let bands: [String: Int]

    public var entityInfo: DXCCEntityInfo {
        DXCCDatabase.resolve(callsign: callsign)
    }

    public var flagEmoji: String {
        entityInfo.flagEmoji
    }

    public var countryName: String {
        entityInfo.entityName
    }

    public func bandCount(_ band: String) -> Int {
        bands[band] ?? 0
    }

    public static func == (lhs: ClubLogLeagueEntry, rhs: ClubLogLeagueEntry) -> Bool {
        lhs.rank == rhs.rank && lhs.callsign == rhs.callsign && lhs.dxccs == rhs.dxccs && lhs.slots == rhs.slots
    }
}

// MARK: - Service Actor

public actor ClubLogLeagueService {
    public static let shared = ClubLogLeagueService()

    private var cache: [String: (entries: [ClubLogLeagueEntry], fetchedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 600 // 10 minutes

    public func fetchLeague(
        mode: ClubLogLeagueMode = .mixed,
        qsl: ClubLogLeagueQSL = .confirmed,
        date: ClubLogLeagueDate = .allTime
    ) async throws -> [ClubLogLeagueEntry] {
        let cacheKey = "mode=\(mode.rawValue)&qsl=\(qsl.rawValue)&date=\(date.rawValue)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.entries
        }

        var components = URLComponents(string: "https://clublog.org/league_api.php")!
        components.queryItems = [
            URLQueryItem(name: "mode", value: "\(mode.rawValue)"),
            URLQueryItem(name: "qsl",  value: "\(qsl.rawValue)"),
            URLQueryItem(name: "date", value: "\(date.rawValue)")
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("YAAM/2.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        let parsed = try parseLeagueJSON(data)
        cache[cacheKey] = (parsed, Date())
        return parsed
    }

    private func parseLeagueJSON(_ data: Data) throws -> [ClubLogLeagueEntry] {
        guard let rawArray = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Expected JSON array"))
        }

        var entries: [ClubLogLeagueEntry] = []
        entries.reserveCapacity(rawArray.count)

        for item in rawArray {
            guard let row = item as? [Any], row.count >= 4 else { continue }
            let rank = (row[0] as? Int) ?? Int("\(row[0])") ?? 0
            let callsign = "\(row[1])".trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !callsign.isEmpty else { continue }
            let dxccs = (row[2] as? Int) ?? Int("\(row[2])") ?? 0
            let slots = (row[3] as? Int) ?? Int("\(row[3])") ?? 0

            var bands: [String: Int] = [:]
            if row.count >= 5, let bandMap = row[4] as? [String: Any] {
                for (b, val) in bandMap {
                    bands[b] = (val as? Int) ?? Int("\(val)") ?? 0
                }
            }

            entries.append(ClubLogLeagueEntry(
                rank: rank,
                callsign: callsign,
                dxccs: dxccs,
                slots: slots,
                bands: bands
            ))
        }

        return entries
    }
}
