//
//  SuperCheckPartialEngine.swift
//  YAAM
//
//  Master.scp / Super Check Partial (SCP) & Contest Intelligence Engine
//  Provides high-speed O(1) in-memory callsign validation, fuzzy matching,
//  real-time Dupe & Multiplier detection, country flags, and online Master.scp auto-update.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Match Status Enum

public enum SCPMatchStatus: String, Sendable {
    case newMultiplier = "MULT"
    case validNewCall = "NEW"
    case duplicate = "DUPE"

    public var badgeColor: Color {
        switch self {
        case .newMultiplier: return .orange
        case .validNewCall: return .green
        case .duplicate: return .secondary
        }
    }

    public var iconName: String {
        switch self {
        case .newMultiplier: return "star.fill"
        case .validNewCall: return "checkmark.circle.fill"
        case .duplicate: return "exclamationmark.circle"
        }
    }
}

// MARK: - Super Check Partial Match Model

public struct SuperCheckPartialMatch: Identifiable, Hashable, Sendable {
    public var id: String { callsign }
    public let callsign: String
    public let editDistance: Int
    public let isExact: Bool
    public let country: DXCCEntityInfo
    public var status: SCPMatchStatus
    public var workedCount: Int
    public var notes: String?

    public init(
        callsign: String,
        editDistance: Int,
        isExact: Bool,
        country: DXCCEntityInfo,
        status: SCPMatchStatus = .validNewCall,
        workedCount: Int = 0,
        notes: String? = nil
    ) {
        self.callsign = callsign
        self.editDistance = editDistance
        self.isExact = isExact
        self.country = country
        self.status = status
        self.workedCount = workedCount
        self.notes = notes
    }
}

// MARK: - Super Check Partial Engine

@MainActor
public final class SuperCheckPartialEngine: ObservableObject {
    public static let shared = SuperCheckPartialEngine()

    @Published public var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "scpEnabled") }
    }
    @Published public var autoUpdate: Bool {
        didSet { UserDefaults.standard.set(autoUpdate, forKey: "scpAutoUpdate") }
    }
    @Published public var lastUpdatedTimestamp: Double {
        didSet { UserDefaults.standard.set(lastUpdatedTimestamp, forKey: "scpLastUpdated") }
    }

    @Published public var totalCallsigns: Int = 0
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var statusMessage: String = "Ready"

    // Primary in-memory index for fast lookup
    private var callsignSet: Set<String> = []
    private var callsignList: [String] = []

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "scpEnabled") as? Bool ?? true
        self.autoUpdate = UserDefaults.standard.object(forKey: "scpAutoUpdate") as? Bool ?? true
        self.lastUpdatedTimestamp = UserDefaults.standard.double(forKey: "scpLastUpdated")
        loadStoredDatabase()
    }

    public var localFileURL: URL {
        let docs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = docs.appendingPathComponent("YAAM", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("MASTER.SCP")
    }

    // MARK: - Database Loading

    public func loadStoredDatabase() {
        let file = localFileURL
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let content = try String(contentsOf: file, encoding: .utf8)
                parseMasterSCP(content)
                statusMessage = "Loaded \(totalCallsigns) callsigns from Master.scp"
                return
            } catch {
                // Leave the index empty if the cached roster cannot be read.
            }
        }

        // Demonstration identities must not become operational matches.
        self.callsignSet = []
        self.callsignList = []
        self.totalCallsigns = 0
        self.statusMessage = "No roster loaded. Import MASTER.SCP or download an update."
    }

    private func parseMasterSCP(_ content: String) {
        var set = Set<String>()
        var list: [String] = []

        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !trimmed.isEmpty, !trimmed.hasPrefix("//"), !trimmed.hasPrefix("#") else { return }
            if trimmed.count >= 3 && trimmed.count <= 12 {
                if set.insert(trimmed).inserted {
                    list.append(trimmed)
                }
            }
        }

        self.callsignSet = set
        self.callsignList = list
        self.totalCallsigns = set.count
    }

    // MARK: - Online Update

    public func updateDatabaseFromWeb() async {
        guard !isDownloading else { return }
        isDownloading = true
        statusMessage = "Downloading latest MASTER.SCP..."

        let url = URL(string: "https://www.supercheckpartial.com/MASTER.SCP")!
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty {
                try data.write(to: localFileURL)
                if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                    parseMasterSCP(text)
                    lastUpdatedTimestamp = Date().timeIntervalSince1970
                    statusMessage = "Updated Master.scp (\(totalCallsigns) callsigns)"
                }
            } else {
                statusMessage = "Server returned error: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            }
        } catch {
            statusMessage = "Update failed: \(error.localizedDescription)"
        }
        isDownloading = false
    }

    // MARK: - Query & Super Check Partial Matching

    public func isKnownContestCallsign(_ callsign: String) -> Bool {
        let clean = callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return callsignSet.contains(clean)
    }

    public func findMatches(for partial: String, maxResults: Int = 10) -> [SuperCheckPartialMatch] {
        findEnrichedMatches(for: partial, band: "", mode: "", workedCallsignsOnBand: [], workedEntities: [], maxResults: maxResults)
    }

    /// Public enriched matching using plain collections for testing and general callers.
    public func findEnrichedMatches(
        for partial: String,
        band: String = "",
        mode: String = "",
        workedCallsignsOnBand: Set<String> = [],
        workedEntities: Set<String> = [],
        maxResults: Int = 12
    ) -> [SuperCheckPartialMatch] {
        let clean = partial.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return [] }

        var results: [SuperCheckPartialMatch] = []
        var seenCalls = Set<String>()

        func statusFor(call: String, entity: String) -> (status: SCPMatchStatus, count: Int) {
            if workedCallsignsOnBand.contains(call) {
                return (.duplicate, 1)
            }
            if !workedEntities.contains(entity) && !entity.isEmpty && entity != "Unknown" && entity != "International" {
                return (.newMultiplier, 0)
            }
            return (.validNewCall, 0)
        }

        // 1. Exact match check
        if callsignSet.contains(clean) {
            let dxcc = DXCCDatabase.resolve(callsign: clean)
            let (status, count) = statusFor(call: clean, entity: dxcc.entityName)
            results.append(SuperCheckPartialMatch(callsign: clean, editDistance: 0, isExact: true, country: dxcc, status: status, workedCount: count))
            seenCalls.insert(clean)
        }

        // 2. Prefix matches
        for candidate in callsignList {
            if seenCalls.contains(candidate) { continue }
            if candidate.hasPrefix(clean) {
                let dxcc = DXCCDatabase.resolve(callsign: candidate)
                let (status, count) = statusFor(call: candidate, entity: dxcc.entityName)
                let dist = abs(candidate.count - clean.count)
                results.append(SuperCheckPartialMatch(callsign: candidate, editDistance: dist, isExact: false, country: dxcc, status: status, workedCount: count))
                seenCalls.insert(candidate)
                if results.count >= maxResults * 2 { break }
            }
        }

        // 3. Substring matches
        if results.count < maxResults {
            for candidate in callsignList {
                if seenCalls.contains(candidate) { continue }
                if candidate.contains(clean) {
                    let dxcc = DXCCDatabase.resolve(callsign: candidate)
                    let (status, count) = statusFor(call: candidate, entity: dxcc.entityName)
                    let dist = abs(candidate.count - clean.count) + 2
                    results.append(SuperCheckPartialMatch(callsign: candidate, editDistance: dist, isExact: false, country: dxcc, status: status, workedCount: count))
                    seenCalls.insert(candidate)
                    if results.count >= maxResults * 2 { break }
                }
            }
        }

        results.sort {
            if $0.isExact != $1.isExact { return $0.isExact }
            if $0.status != $1.status {
                return statusPriority($0.status) < statusPriority($1.status)
            }
            return $0.editDistance < $1.editDistance
        }

        return Array(results.prefix(maxResults))
    }

    /// Internal enriched matching directly against YAAM's logbook QSORecordModel instances.
    func findEnrichedMatches(
        for partial: String,
        band: String = "",
        mode: String = "",
        qsoRecords: [QSORecordModel],
        maxResults: Int = 12
    ) -> [SuperCheckPartialMatch] {
        let clean = partial.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return [] }

        var results: [SuperCheckPartialMatch] = []
        var seenCalls = Set<String>()

        // 1. Exact match check
        if callsignSet.contains(clean) {
            let dxcc = DXCCDatabase.resolve(callsign: clean)
            let (status, count) = evaluateContestStatus(for: clean, entity: dxcc.entityName, band: band, mode: mode, qsoRecords: qsoRecords)
            results.append(SuperCheckPartialMatch(callsign: clean, editDistance: 0, isExact: true, country: dxcc, status: status, workedCount: count))
            seenCalls.insert(clean)
        }

        // 2. Prefix matches (highest relevance: callsign starts with query)
        for candidate in callsignList {
            if seenCalls.contains(candidate) { continue }
            if candidate.hasPrefix(clean) {
                let dxcc = DXCCDatabase.resolve(callsign: candidate)
                let (status, count) = evaluateContestStatus(for: candidate, entity: dxcc.entityName, band: band, mode: mode, qsoRecords: qsoRecords)
                let dist = abs(candidate.count - clean.count)
                results.append(SuperCheckPartialMatch(callsign: candidate, editDistance: dist, isExact: false, country: dxcc, status: status, workedCount: count))
                seenCalls.insert(candidate)
                if results.count >= maxResults * 2 { break }
            }
        }

        // 3. Substring matches (contains query anywhere in callsign)
        if results.count < maxResults {
            for candidate in callsignList {
                if seenCalls.contains(candidate) { continue }
                if candidate.contains(clean) {
                    let dxcc = DXCCDatabase.resolve(callsign: candidate)
                    let (status, count) = evaluateContestStatus(for: candidate, entity: dxcc.entityName, band: band, mode: mode, qsoRecords: qsoRecords)
                    let dist = abs(candidate.count - clean.count) + 2
                    results.append(SuperCheckPartialMatch(callsign: candidate, editDistance: dist, isExact: false, country: dxcc, status: status, workedCount: count))
                    seenCalls.insert(candidate)
                    if results.count >= maxResults * 2 { break }
                }
            }
        }

        // Sort: Exact match first, then Multipliers, then New Calls, then Dupes, ordered by edit distance
        results.sort {
            if $0.isExact != $1.isExact { return $0.isExact }
            if $0.status != $1.status {
                return statusPriority($0.status) < statusPriority($1.status)
            }
            return $0.editDistance < $1.editDistance
        }

        return Array(results.prefix(maxResults))
    }

    private func statusPriority(_ status: SCPMatchStatus) -> Int {
        switch status {
        case .newMultiplier: return 0
        case .validNewCall: return 1
        case .duplicate: return 2
        }
    }

    private func evaluateContestStatus(
        for callsign: String,
        entity: String,
        band: String,
        mode: String,
        qsoRecords: [QSORecordModel]
    ) -> (status: SCPMatchStatus, workedCount: Int) {
        let cleanCall = callsign.uppercased()
        let cleanBand = band.uppercased()
        let cleanMode = mode.uppercased()

        // Count matching QSOs in current logbook
        var totalMatches = 0
        var isBandModeDupe = false

        for qso in qsoRecords {
            let call = qso.fields["CALL"]?.uppercased() ?? ""
            if call == cleanCall {
                totalMatches += 1
                let qBand = qso.fields["BAND"]?.uppercased() ?? ""
                let qMode = qso.fields["MODE"]?.uppercased() ?? ""
                let matchesBand = cleanBand.isEmpty || qBand == cleanBand
                let matchesMode = cleanMode.isEmpty || qMode == cleanMode
                if matchesBand && matchesMode {
                    isBandModeDupe = true
                }
            }
        }

        if isBandModeDupe {
            return (.duplicate, totalMatches)
        }

        // Check if entity is a new multiplier
        let hasWorkedEntity = qsoRecords.contains(where: { q in
            let call = q.fields["CALL"] ?? ""
            let qEntity = DXCCDatabase.resolve(callsign: call).entityName
            return qEntity == entity
        })

        if !hasWorkedEntity && !entity.isEmpty && entity != "Unknown" && entity != "International" {
            return (.newMultiplier, totalMatches)
        }

        return (.validNewCall, totalMatches)
    }
}
