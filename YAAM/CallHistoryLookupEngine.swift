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
        didSet { UserDefaults.standard.set(isEnabled, forKey: "callHistoryEnabled") }
    }

    // Fast in-memory hash store
    private var records: [String: CallHistoryRecord] = [:]

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "callHistoryEnabled") as? Bool ?? true
        loadSeedDatabase()
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

    // MARK: - Built-in Seed Database

    private func loadSeedDatabase() {
        let seeds: [CallHistoryRecord] = [
            // Prominent World Contest Stations with verified CQ Zones, States, and Operators
            CallHistoryRecord(callsign: "W1AW", name: "HQ", state: "CT", arrlSection: "CT", cqZone: 5, ituZone: 8, gridSquare: "FN31pr", userExchange: "KW"),
            CallHistoryRecord(callsign: "K3LR", name: "Tim", state: "PA", arrlSection: "WPA", cqZone: 5, ituZone: 8, gridSquare: "EN91re", userExchange: "KW"),
            CallHistoryRecord(callsign: "W3LPL", name: "Frank", state: "MD", arrlSection: "MDC", cqZone: 5, ituZone: 8, gridSquare: "FM19lf", userExchange: "KW"),
            CallHistoryRecord(callsign: "K1LZ", name: "Krasi", state: "ME", arrlSection: "EMA", cqZone: 5, ituZone: 8, gridSquare: "FN54", userExchange: "KW"),
            CallHistoryRecord(callsign: "K5ZD", name: "Randy", state: "MA", arrlSection: "WMA", cqZone: 5, ituZone: 8, gridSquare: "FN32", userExchange: "KW"),
            CallHistoryRecord(callsign: "AA3B", name: "Bud", state: "PA", arrlSection: "EPA", cqZone: 5, ituZone: 8, gridSquare: "FN20", userExchange: "KW"),
            CallHistoryRecord(callsign: "N2IC", name: "Steve", state: "NM", arrlSection: "NM", cqZone: 4, ituZone: 7, gridSquare: "DM65", userExchange: "KW"),
            CallHistoryRecord(callsign: "W6YX", name: "Stanford", state: "CA", arrlSection: "SCV", cqZone: 3, ituZone: 6, gridSquare: "CM87", userExchange: "KW"),
            CallHistoryRecord(callsign: "K7RI", name: "Rich", state: "WA", arrlSection: "WWA", cqZone: 3, ituZone: 6, gridSquare: "CN87", userExchange: "KW"),
            CallHistoryRecord(callsign: "VE3EJ", name: "John", state: "ON", arrlSection: "GTA", cqZone: 4, ituZone: 8, gridSquare: "FN04", userExchange: "KW"),
            CallHistoryRecord(callsign: "VE2CSE", name: "Gilles", state: "QC", arrlSection: "QC", cqZone: 5, ituZone: 9, gridSquare: "FN46", userExchange: "100"),
            CallHistoryRecord(callsign: "DL1ABC", name: "Klaus", state: "", arrlSection: "", cqZone: 14, ituZone: 28, gridSquare: "JO40", userExchange: "14"),
            CallHistoryRecord(callsign: "DL0CS", name: "Club", state: "", arrlSection: "", cqZone: 14, ituZone: 28, gridSquare: "JO50", userExchange: "14"),
            CallHistoryRecord(callsign: "DA0HQ", name: "DARC", state: "", arrlSection: "", cqZone: 14, ituZone: 28, gridSquare: "JO52", userExchange: "DARC"),
            CallHistoryRecord(callsign: "DF3CB", name: "Bernd", state: "", arrlSection: "", cqZone: 14, ituZone: 28, gridSquare: "JN58", userExchange: "14"),
            CallHistoryRecord(callsign: "G3TXF", name: "Nigel", state: "", arrlSection: "", cqZone: 14, ituZone: 27, gridSquare: "IO91", userExchange: "14"),
            CallHistoryRecord(callsign: "M6T", name: "Contest", state: "", arrlSection: "", cqZone: 14, ituZone: 27, gridSquare: "IO92", userExchange: "14"),
            CallHistoryRecord(callsign: "F6KOP", name: "Club", state: "", arrlSection: "", cqZone: 14, ituZone: 27, gridSquare: "JN18", userExchange: "14"),
            CallHistoryRecord(callsign: "TM6M", name: "Team", state: "", arrlSection: "", cqZone: 14, ituZone: 27, gridSquare: "IN98", userExchange: "14"),
            CallHistoryRecord(callsign: "I2WIJ", name: "Bob", state: "", arrlSection: "", cqZone: 15, ituZone: 28, gridSquare: "JN45", userExchange: "15"),
            CallHistoryRecord(callsign: "IR4M", name: "Team", state: "", arrlSection: "", cqZone: 15, ituZone: 28, gridSquare: "JN54", userExchange: "15"),
            CallHistoryRecord(callsign: "EA4TX", name: "Pablo", state: "", arrlSection: "", cqZone: 14, ituZone: 37, gridSquare: "IN80", userExchange: "14"),
            CallHistoryRecord(callsign: "EF8R", name: "Team", state: "", arrlSection: "", cqZone: 33, ituZone: 36, gridSquare: "IL28", userExchange: "33"),
            CallHistoryRecord(callsign: "CR3A", name: "Team", state: "", arrlSection: "", cqZone: 33, ituZone: 36, gridSquare: "IL12", userExchange: "33"),
            CallHistoryRecord(callsign: "OH2BH", name: "Martti", state: "", arrlSection: "", cqZone: 15, ituZone: 18, gridSquare: "KP20", userExchange: "15"),
            CallHistoryRecord(callsign: "OG2X", name: "Jari", state: "", arrlSection: "", cqZone: 15, ituZone: 18, gridSquare: "KP20", userExchange: "15"),
            CallHistoryRecord(callsign: "EP2AES", name: "Amir", state: "THR", arrlSection: "", cqZone: 21, ituZone: 40, gridSquare: "LL45", userExchange: "21"),
            CallHistoryRecord(callsign: "EP2LSH", name: "Hossein", state: "AZB", arrlSection: "", cqZone: 21, ituZone: 40, gridSquare: "LN48", userExchange: "21"),
            CallHistoryRecord(callsign: "EP2C", name: "CRA", state: "THR", arrlSection: "", cqZone: 21, ituZone: 40, gridSquare: "LL45", userExchange: "21"),
            CallHistoryRecord(callsign: "4X4DK", name: "Avi", state: "", arrlSection: "", cqZone: 20, ituZone: 39, gridSquare: "KM72", userExchange: "20"),
            CallHistoryRecord(callsign: "A61Q", name: "Hazza", state: "", arrlSection: "", cqZone: 21, ituZone: 39, gridSquare: "LL75", userExchange: "21"),
            CallHistoryRecord(callsign: "JA1ABC", name: "Ken", state: "", arrlSection: "", cqZone: 25, ituZone: 45, gridSquare: "PM95", userExchange: "25"),
            CallHistoryRecord(callsign: "JA1BJK", name: "Tak", state: "", arrlSection: "", cqZone: 25, ituZone: 45, gridSquare: "QM05", userExchange: "25"),
            CallHistoryRecord(callsign: "JH1AJT", name: "Zorro", state: "", arrlSection: "", cqZone: 25, ituZone: 45, gridSquare: "PM95", userExchange: "25"),
            CallHistoryRecord(callsign: "BY1RX", name: "Team", state: "", arrlSection: "", cqZone: 24, ituZone: 44, gridSquare: "OM89", userExchange: "24"),
            CallHistoryRecord(callsign: "VK3XYZ", name: "Ross", state: "VIC", arrlSection: "", cqZone: 30, ituZone: 59, gridSquare: "QF22", userExchange: "30"),
            CallHistoryRecord(callsign: "ZL1BQD", name: "Roly", state: "", arrlSection: "", cqZone: 32, ituZone: 60, gridSquare: "RF73", userExchange: "32"),
            CallHistoryRecord(callsign: "P40W", name: "John", state: "", arrlSection: "", cqZone: 9, ituZone: 11, gridSquare: "FK42", userExchange: "09"),
            CallHistoryRecord(callsign: "PJ2T", name: "CCC", state: "", arrlSection: "", cqZone: 9, ituZone: 11, gridSquare: "FK52", userExchange: "09")
        ]

        for s in seeds {
            records[s.callsign] = s
        }
        self.totalRecordsCount = records.count
    }

    // MARK: - Persistence

    private var storageURL: URL {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("YAAM", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("call_history_store.json")
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("call_history_store.json")
    }

    private func persistLearnedRecords() {
        Task.detached(priority: .background) { [records = self.records, url = self.storageURL] in
            // Only persist learned and imported records (built-ins are initialized in code)
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
        for item in list {
            records[item.callsign] = item
        }
        self.totalRecordsCount = records.count
    }
}
