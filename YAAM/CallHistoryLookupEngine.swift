//
//  CallHistoryLookupEngine.swift
//  YAAM
//
//  Contest Call History & Predictive Exchange Pre-fill Engine.
//  Supports standard N1MM/Win-Test CallHistory.txt files, automatic logbook self-learning,
//  and instant O(1) exchange resolution (Name, State, ARRL Section, CQ/ITU Zone, Grid, Exchange).
//

import Combine
import Foundation

enum CallHistorySource: String, Codable, Sendable {
    case builtInSeed = "Built-In Contest Seed"
    case logbookLearned = "Logbook History"
    case importedFile = "Imported File"
}

struct CallHistoryRecord: Identifiable, Codable, Equatable, Sendable {
    var id: String { callsign }
    let callsign: String
    var name: String
    var state: String
    var arrlSection: String
    var cqZone: Int?
    var ituZone: Int?
    var gridSquare: String
    var userExchange: String
    var source: CallHistorySource
    var lastUpdated: Date

    init(
        callsign: String,
        name: String = "",
        state: String = "",
        arrlSection: String = "",
        cqZone: Int? = nil,
        ituZone: Int? = nil,
        gridSquare: String = "",
        userExchange: String = "",
        source: CallHistorySource = .builtInSeed,
        lastUpdated: Date = Date()
    ) {
        self.callsign = callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.state = state.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.arrlSection = arrlSection.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.cqZone = cqZone
        self.ituZone = ituZone
        self.gridSquare = gridSquare.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.userExchange = userExchange.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.lastUpdated = lastUpdated
    }

    /// Summary representation for quick HUD display (e.g. "BOB • OH • Z04 • EN91")
    var previewSummary: String {
        var parts: [String] = []
        if !name.isEmpty { parts.append(name) }
        if !state.isEmpty { parts.append(state) }
        else if !arrlSection.isEmpty { parts.append(arrlSection) }
        if let z = cqZone, z > 0 { parts.append("Z\(z < 10 ? "0\(z)" : "\(z)")") }
        if !userExchange.isEmpty { parts.append(userExchange) }
        else if !gridSquare.isEmpty { parts.append(gridSquare) }
        return parts.joined(separator: " • ")
    }
}

@MainActor
final class CallHistoryLookupEngine: ObservableObject {
    static let shared = CallHistoryLookupEngine()

    @Published var totalRecordsCount: Int = 0
    @Published var lastImportedFileName: String = ""
    @Published var lastLearnedLogbookCount: Int = 0
    @Published var isEnabled: Bool = true {
        didSet { defaults.set(isEnabled, forKey: "callHistoryEnabled") }
    }

    // Fast in-memory hash store
    private var records: [String: CallHistoryRecord] = [:]
    private let storageOverride: URL?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, storageURL: URL? = nil) {
        self.defaults = defaults
        self.storageOverride = storageURL
        self.isEnabled = defaults.object(forKey: "callHistoryEnabled") as? Bool ?? true
        loadPersistedRecords()
    }

    // MARK: - Query API

    func lookup(callsign: String) -> CallHistoryRecord? {
        guard isEnabled else { return nil }
        let clean = callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return records[clean]
    }

    /// Prefix search across call history records
    func search(prefix: String, limit: Int = 10) -> [CallHistoryRecord] {
        guard isEnabled else { return [] }
        let clean = prefix.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        var matches: [CallHistoryRecord] = []
        for (call, record) in records {
            if call.hasPrefix(clean) {
                matches.append(record)
                if matches.count >= limit { break }
            }
        }
        return matches.sorted(by: { $0.callsign < $1.callsign })
    }

    func recordCount(for source: CallHistorySource) -> Int {
        records.values.filter { $0.source == source }.count
    }

    // MARK: - Logbook Self-Learning

    /// Learns operator names, states, sections, zones, and grids from existing logbook QSOs.
    func learnFromLogbook(records qsoRecords: [QSORecordModel]) {
        var newLearned = 0
        for qso in qsoRecords {
            guard let call = qso.fields["CALL"]?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines),
                  call.count >= 3 else { continue }

            let name = qso.fields["NAME"] ?? ""
            let state = qso.fields["STATE"] ?? ""
            let section = qso.fields["ARRL_SECT"] ?? qso.fields["SECTION"] ?? ""
            let grid = qso.fields["GRIDSQUARE"] ?? qso.fields["GRID"] ?? ""
            let cqZone = Int(qso.fields["CQZ"] ?? qso.fields["ZONE"] ?? "")
            let ituZone = Int(qso.fields["ITUZ"] ?? "")
            let exch = qso.fields["SRX"] ?? qso.fields["EXCHANGE"] ?? ""

            // Only learn if there is useful information
            if !name.isEmpty || !state.isEmpty || !section.isEmpty || !grid.isEmpty || cqZone != nil || !exch.isEmpty {
                var existing = records[call]
                if existing == nil {
                    records[call] = CallHistoryRecord(
                        callsign: call,
                        name: name,
                        state: state,
                        arrlSection: section,
                        cqZone: cqZone,
                        ituZone: ituZone,
                        gridSquare: grid,
                        userExchange: exch,
                        source: .logbookLearned
                    )
                    newLearned += 1
                } else if existing?.source != .importedFile {
                    // Enrich existing record with non-empty fields
                    if !name.isEmpty { existing?.name = name }
                    if !state.isEmpty { existing?.state = state }
                    if !section.isEmpty { existing?.arrlSection = section }
                    if !grid.isEmpty { existing?.gridSquare = grid }
                    if let cq = cqZone { existing?.cqZone = cq }
                    if let itu = ituZone { existing?.ituZone = itu }
                    if !exch.isEmpty { existing?.userExchange = exch }
                    existing?.source = .logbookLearned
                    existing?.lastUpdated = Date()
                    if let updated = existing {
                        records[call] = updated
                    }
                }
            }
        }

        self.lastLearnedLogbookCount = newLearned
        self.totalRecordsCount = records.count
        persistLearnedRecords()
    }

    // MARK: - File Import Parser (N1MM / Win-Test Format)

    func importCallHistory(content: String, filename: String = "CallHistory.txt") -> Int {
        let lines = content.components(separatedBy: .newlines)
        var columnOrder: [String] = []
        var importedCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { continue }

            // Check header directive e.g. "!!Order!!, Call, Name, Sec, State, CK, Class, User1, Grid"
            if trimmed.lowercased().hasPrefix("!!order!!") {
                let parts = trimmed.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                columnOrder = Array(parts.dropFirst())
                continue
            }

            // Split line by comma (or tab if no commas)
            let delimiter: Character = trimmed.contains(",") ? "," : "\t"
            let tokens = trimmed.split(separator: delimiter, omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard !tokens.isEmpty else { continue }

            var call = ""
            var name = ""
            var state = ""
            var sect = ""
            var grid = ""
            var zone: Int? = nil
            var itu: Int? = nil
            var exch = ""

            if !columnOrder.isEmpty {
                for (idx, key) in columnOrder.enumerated() {
                    guard idx < tokens.count else { break }
                    let val = tokens[idx]
                    guard !val.isEmpty else { continue }

                    switch key {
                    case "call", "callsign":
                        call = val.uppercased()
                    case "name":
                        name = val
                    case "state", "st":
                        state = val.uppercased()
                    case "sec", "sect", "section", "arrl_sect":
                        sect = val.uppercased()
                    case "zone", "cqz", "cq":
                        zone = Int(val)
                    case "itu", "ituz":
                        itu = Int(val)
                    case "grid", "loc":
                        grid = val.uppercased()
                    case "exch", "exchange", "ck", "class", "user1", "user2":
                        if exch.isEmpty { exch = val } else { exch += " " + val }
                    default:
                        break
                    }
                }
            } else {
                // Default heuristic order: Call, Name, State/Sec, Zone/Exch, Grid
                call = tokens[0].uppercased()
                if tokens.count > 1 { name = tokens[1] }
                if tokens.count > 2 {
                    let token2 = tokens[2].uppercased()
                    if token2.count == 2 { state = token2 } else { sect = token2 }
                }
                if tokens.count > 3 {
                    if let z = Int(tokens[3]) { zone = z } else { exch = tokens[3] }
                }
                if tokens.count > 4 {
                    grid = tokens[4].uppercased()
                }
            }

            guard !call.isEmpty && call.count >= 3 else { continue }

            let record = CallHistoryRecord(
                callsign: call,
                name: name,
                state: state,
                arrlSection: sect,
                cqZone: zone,
                ituZone: itu,
                gridSquare: grid,
                userExchange: exch,
                source: .importedFile
            )
            records[call] = record
            importedCount += 1
        }

        self.lastImportedFileName = filename
        self.totalRecordsCount = records.count
        persistLearnedRecords()
        return importedCount
    }

    func importFromURL(_ url: URL) throws -> Int {
        let content = try String(contentsOf: url, encoding: .utf8)
        return importCallHistory(content: content, filename: url.lastPathComponent)
    }

    func clearImportedRecords() {
        records = records.filter { $0.value.source != .importedFile }
        totalRecordsCount = records.count
        lastImportedFileName = ""
        persistLearnedRecords()
    }

    // MARK: - Persistence

    private var storageURL: URL {
        if let storageOverride { return storageOverride }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("YAAM", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("call_history_store.json")
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("call_history_store.json")
    }

    private func persistLearnedRecords() {
        Task.detached(priority: .background) { [records = self.records, url = self.storageURL] in
            // Only persist learned and imported records; legacy demonstration entries are discarded.
            let nonSeed = records.values.filter { $0.source != .builtInSeed }
            if let data = try? JSONEncoder().encode(Array(nonSeed)) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func loadPersistedRecords() {
        guard let data = try? Data(contentsOf: storageURL),
              let list = try? JSONDecoder().decode([CallHistoryRecord].self, from: data) else {
            return
        }
        for item in list where item.source != .builtInSeed {
            records[item.callsign] = item
        }
        self.totalRecordsCount = records.count
    }
}
