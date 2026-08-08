//
//  AppState.swift
//  ADIF to Excel
//
//  Created by factoreal on 7/30/26.
//

import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

// MARK: - Band Statistics Model
struct BandStatModel: Identifiable {
    let id = UUID()
    let band: String
    let qsoCount: Int
    let confirmedCount: Int
    let unconfirmedCount: Int
    let dxccCount: Int
    let percentage: Double
}

// MARK: - Country Statistics Model
struct CountryStatModel: Identifiable {
    let id = UUID()
    let country: String
    let flag: String
    let qsoCount: Int
    let confirmedCount: Int
    let unconfirmedCount: Int
}

// MARK: - Comprehensive DXCC & Country Flag Lookup Engine
func countryToFlag(_ country: String) -> String {
    let clean = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if clean.isEmpty { return "🌐" }
    
    switch clean {
    case "republic of korea", "korea, republic of", "korea (republic of)", "south korea", "korea", "rok": return "🇰🇷"
    case "democratic people's republic of korea", "dprk", "korea, d.p.r. of", "north korea": return "🇰🇵"
    case "japan": return "🇯🇵"
    case "china", "people's republic of china", "prc": return "🇨🇳"
    case "asiatic russia", "russia": return "🇷🇺"
    case "taiwan", "republic of china": return "🇹🇼"
    case "hong kong": return "🇭🇰"
    case "macao", "macau": return "🇲🇴"
    case "iran", "islamic republic of iran": return "🇮🇷"
    case "saudi arabia": return "🇸🇦"
    case "india": return "🇮🇳"
    case "pakistan": return "🇵🇰"
    case "turkey", "turkiye": return "🇹🇷"
    case "israel": return "🇮🇱"

    case "england", "uk", "united kingdom", "great britain": return "🇬🇧"
    case "scotland": return "🏴󠁧󠁢󠁳󠁣󠁴󠁿"
    case "wales": return "🏴󠁧󠁢󠁷󠁬󠁳󠁿"
    case "european russia", "kaliningrad": return "🇷🇺"
    case "germany", "fed. rep. of germany", "federal republic of germany": return "🇩🇪"
    case "france": return "🇫🇷"
    case "italy": return "🇮🇹"
    case "spain": return "🇪🇸"
    case "portugal": return "🇵🇹"
    case "greece": return "🇬🇷"
    case "netherlands": return "🇳🇱"
    case "belgium": return "🇧🇪"
    case "switzerland": return "🇨🇭"
    case "austria": return "🇦🇹"
    case "poland": return "🇵🇱"
    case "sweden": return "🇸🇪"
    case "norway": return "🇳🇴"
    case "finland": return "🇫🇮"
    case "denmark": return "🇩🇰"
    case "ukraine": return "🇺🇦"
    case "armenia": return "🇦🇲"

    case "united states", "united states of america", "usa", "u.s.a.": return "🇺🇸"
    case "canada": return "🇨🇦"
    case "mexico": return "🇲🇽"
    case "brazil": return "🇧🇷"
    case "australia": return "🇦🇺"
    case "new zealand": return "🇳🇿"
    default: break
    }
    
    if clean.contains("korea") { return "🇰🇷" }
    if clean.contains("russia") { return "🇷🇺" }
    if clean.contains("germany") { return "🇩🇪" }
    if clean.contains("japan") { return "🇯🇵" }
    if clean.contains("china") { return "🇨🇳" }
    if clean.contains("united states") || clean.contains("u.s.a") { return "🇺🇸" }
    
    if clean.count == 2 {
        let base: UInt32 = 127397
        var unicodeScalars = String.UnicodeScalarView()
        for scalar in clean.uppercased().unicodeScalars {
            if let newScalar = UnicodeScalar(base + scalar.value) {
                unicodeScalars.append(newScalar)
            }
        }
        return String(unicodeScalars)
    }
    
    return "🌐"
}

// MARK: - Filter Criteria Model
struct FilterCriteria {
    var useDate: Bool = false
    var startDate: Date = Date()
    var endDate: Date = Date()
    
    var useBand: Bool = false
    var band: String = "All"
    
    var useMode: Bool = false
    var mode: String = "All"
    
    var useCallsign: Bool = false
    var callsign: String = ""
    
    var useOperator: Bool = false
    var operatorStation: String = ""
    
    var useZone: Bool = false
    var zone: String = ""
    
    var useCountry: Bool = false
    var selectedCountries: Set<String> = []
    
    var useQSLSent: Bool = false
    var qslSent: String = "Y"
    
    var useQSLRcvd: Bool = false
    var qslRcvd: String = "Y"
    
    var useConfirmation: Bool = false
    var confirmationType: String = "Any Method"
    var confirmationState: String = "Confirmed (Y)"
    
    var useContinent: Bool = false
    var selectedContinents: Set<String> = []
    
    var isActive: Bool {
        useDate || useBand || useMode || useCallsign || useOperator || useZone || useCountry || useQSLSent || useQSLRcvd || useConfirmation || useContinent
    }
    
    mutating func reset() {
        self = FilterCriteria()
    }
}

// MARK: - QSO Record Model
struct QSORecordModel: Identifiable {
    let id = UUID()
    var index: Int
    var fields: [String: String]
    
    var isConfirmed: Bool {
        let lotw = fields["LOTW_QSL_RCVD"]?.uppercased() ?? ""
        let qrz = fields["QRZLOG_QSL_RCVD"]?.uppercased() ?? ""
        let qsl = fields["QSL_RCVD"]?.uppercased() ?? ""
        return lotw == "Y" || lotw == "V" || qrz == "Y" || qsl == "Y"
    }
    
    subscript(key: String) -> String {
        get { return fields[key] ?? "" }
        set { fields[key] = newValue }
    }
}

// MARK: - Global Application State Manager
class AppState: NSObject, ObservableObject {
    var currentVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.7.0"
    }
    
    @Published var logText: String = "Welcome to ADIF Log Processor & Master.\nPlease import an ADIF log file.\n"
    @Published var isCheckingUpdates: Bool = false
    @Published var isLoading: Bool = false
    @Published var isSyncingAPI: Bool = false
    
    // Search & Smart Sorting States
    @Published var searchText: String = ""
    @Published var sortHeader: String? = nil
    @Published var sortAscending: Bool = true
    
    // Loaded Log Data & Database Tracking
    @Published var loadedFileURL: URL? = nil
    @Published var loadedFileName: String = ""
    @Published var tableHeaders: [String] = []
    @Published var qsoRecords: [QSORecordModel] = []
    @Published var recentLogFiles: [URL] = []
    @Published var selectedTab: Int = 0
    
    // Persistent Local Confirmations Memory Database Cache
    private var localConfirmedKeys: Set<String> = []
    
    // Filter & Modal Sheet States
    @Published var filterCriteria = FilterCriteria()
    @Published var showFilterSheet: Bool = false
    @Published var showStatsSheet: Bool = false
    
    // Global User Alerts
    @Published var showAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""

    override init() {
        super.init()
        loadPersistentConfirmationCache()
    }

    var availableCountries: [String] {
        let countries = Set(qsoRecords.compactMap { $0["COUNTRY"].isEmpty ? nil : $0["COUNTRY"] })
        return Array(countries).sorted()
    }

    var activeModesCount: Int {
        Set(qsoRecords.compactMap { $0["MODE"].isEmpty ? nil : $0["MODE"] }).count
    }

    var uniqueCallsignCount: Int {
        Set(qsoRecords.compactMap { $0["CALL"].isEmpty ? nil : $0["CALL"].uppercased() }).count
    }

    var totalConfirmedCount: Int {
        qsoRecords.filter { $0.isConfirmed }.count
    }

    var totalUnconfirmedCount: Int {
        qsoRecords.count - totalConfirmedCount
    }

    var bandStatistics: [BandStatModel] {
        guard !qsoRecords.isEmpty else { return [] }
        
        var bandMap: [String: (total: Int, confirmed: Int, countries: Set<String>)] = [:]
        let total = Double(qsoRecords.count)
        
        for record in qsoRecords {
            let band = record["BAND"].isEmpty ? "UNKNOWN" : record["BAND"].uppercased()
            let country = record["COUNTRY"]
            let confirmed = record.isConfirmed
            
            if bandMap[band] == nil {
                bandMap[band] = (total: 0, confirmed: 0, countries: Set<String>())
            }
            bandMap[band]?.total += 1
            if confirmed { bandMap[band]?.confirmed += 1 }
            if !country.isEmpty { bandMap[band]?.countries.insert(country) }
        }
        
        return bandMap.map { (bandKey, data) in
            let pct = (Double(data.total) / total) * 100.0
            let unconf = data.total - data.confirmed
            return BandStatModel(band: bandKey, qsoCount: data.total, confirmedCount: data.confirmed, unconfirmedCount: unconf, dxccCount: data.countries.count, percentage: pct)
        }.sorted { $0.qsoCount > $1.qsoCount }
    }

    var countryStatistics: [CountryStatModel] {
        guard !qsoRecords.isEmpty else { return [] }
        
        var countryMap: [String: (total: Int, confirmed: Int)] = [:]
        
        for record in qsoRecords {
            let c = record["COUNTRY"].isEmpty ? "Unknown" : record["COUNTRY"]
            if countryMap[c] == nil { countryMap[c] = (total: 0, confirmed: 0) }
            countryMap[c]?.total += 1
            if record.isConfirmed { countryMap[c]?.confirmed += 1 }
        }
        
        return countryMap.map { (cName, data) in
            let unconf = data.total - data.confirmed
            return CountryStatModel(country: cName, flag: countryToFlag(cName), qsoCount: data.total, confirmedCount: data.confirmed, unconfirmedCount: unconf)
        }.sorted { $0.qsoCount > $1.qsoCount }
    }

    var filteredRecords: [QSORecordModel] {
        var records = qsoRecords
        
        if filterCriteria.isActive {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            
            let startStr = formatter.string(from: filterCriteria.startDate)
            let endStr = formatter.string(from: filterCriteria.endDate)
            
            records = records.filter { record in
                if filterCriteria.useDate {
                    let qsoDate = record["QSO_DATE"]
                    if qsoDate < startStr || qsoDate > endStr { return false }
                }
                if filterCriteria.useBand && filterCriteria.band != "All" {
                    if record["BAND"].uppercased() != filterCriteria.band.uppercased() { return false }
                }
                if filterCriteria.useMode && filterCriteria.mode != "All" {
                    let recMode = record["MODE"].uppercased()
                    let recSubmode = record["SUBMODE"].uppercased()
                    let target = filterCriteria.mode.uppercased()
                    if recMode != target && recSubmode != target { return false }
                }
                if filterCriteria.useCallsign, !filterCriteria.callsign.isEmpty {
                    if !record["CALL"].localizedCaseInsensitiveContains(filterCriteria.callsign.trimmingCharacters(in: .whitespaces)) { return false }
                }
                if filterCriteria.useOperator, !filterCriteria.operatorStation.isEmpty {
                    let op = record["OPERATOR"].isEmpty ? record["STATION_CALLSIGN"] : record["OPERATOR"]
                    if !op.localizedCaseInsensitiveContains(filterCriteria.operatorStation.trimmingCharacters(in: .whitespaces)) { return false }
                }
                if filterCriteria.useZone, !filterCriteria.zone.isEmpty {
                    if record["CQZ"] != filterCriteria.zone.trimmingCharacters(in: .whitespaces) { return false }
                }
                if filterCriteria.useCountry, !filterCriteria.selectedCountries.isEmpty {
                    if !filterCriteria.selectedCountries.contains(record["COUNTRY"]) { return false }
                }
                if filterCriteria.useQSLSent {
                    let val = record["QSL_SENT"].uppercased()
                    if filterCriteria.qslSent == "Blank" && !val.isEmpty { return false }
                    if filterCriteria.qslSent != "Blank" && val != filterCriteria.qslSent { return false }
                }
                if filterCriteria.useQSLRcvd {
                    let val = record["QSL_RCVD"].uppercased()
                    if filterCriteria.qslRcvd == "Blank" && !val.isEmpty { return false }
                    if filterCriteria.qslRcvd != "Blank" && val != filterCriteria.qslRcvd { return false }
                }
                if filterCriteria.useConfirmation {
                    let wantConfirmed = (filterCriteria.confirmationState == "Confirmed (Y)")
                    if wantConfirmed != record.isConfirmed { return false }
                }
                if filterCriteria.useContinent, !filterCriteria.selectedContinents.isEmpty {
                    if !filterCriteria.selectedContinents.contains(record["CONT"].uppercased()) { return false }
                }
                return true
            }
        }
        
        if !searchText.isEmpty {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            records = records.filter { record in
                record.fields.values.contains { $0.lowercased().contains(query) } ||
                tableHeaders.contains { $0.lowercased().contains(query) }
            }
        }
        
        if let sortKey = sortHeader {
            records.sort { r1, r2 in
                let v1 = r1[sortKey].trimmingCharacters(in: .whitespaces)
                let v2 = r2[sortKey].trimmingCharacters(in: .whitespaces)
                
                let isAscending: Bool
                if let d1 = Double(v1), let d2 = Double(v2) {
                    isAscending = d1 < d2
                } else if sortKey == "QSO_DATE" || sortKey == "TIME_ON" || sortKey == "TIME_OFF" {
                    isAscending = v1 < v2
                } else {
                    isAscending = v1.localizedCaseInsensitiveCompare(v2) == .orderedAscending
                }
                
                return sortAscending ? isAscending : !isAscending
            }
        }
        
        return records
    }

    func toggleSort(for header: String) {
        if sortHeader == header {
            if sortAscending {
                sortAscending = false
            } else {
                sortHeader = nil
                sortAscending = true
            }
        } else {
            sortHeader = header
            sortAscending = true
        }
    }

    func appendLog(_ text: String) {
        logText += "\(text)\n"
    }

    func deleteRecord(id: UUID) {
        if let idx = qsoRecords.firstIndex(where: { $0.id == id }) {
            let recordNum = qsoRecords[idx].index
            let call = qsoRecords[idx]["CALL"]
            qsoRecords.remove(at: idx)
            
            for i in 0..<qsoRecords.count {
                qsoRecords[i].index = i + 1
            }
            appendLog("Deleted QSO record #\(recordNum) (\(call)).")
        }
    }

    func updateCell(recordID: UUID, header: String, newValue: String) {
        if let idx = qsoRecords.firstIndex(where: { $0.id == recordID }) {
            qsoRecords[idx].fields[header] = newValue
            appendLog("Updated record #\(qsoRecords[idx].index) [\(header)] ➔ '\(newValue)'")
        }
    }

    func deleteColumn(header: String) {
        tableHeaders.removeAll(where: { $0 == header })
        for i in 0..<qsoRecords.count {
            qsoRecords[i].fields.removeValue(forKey: header)
        }
        appendLog("Removed column '\(header)' from log structure.")
    }

    // MARK: - Persistent Local Confirmation JSON Database Engine
    
    private var confirmationCacheFileURL: URL? {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("ADIFMaster")
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("confirmed_cache.json")
    }
    
    private func loadPersistentConfirmationCache() {
        guard let fileURL = confirmationCacheFileURL,
              let data = try? Data(contentsOf: fileURL),
              let keys = try? JSONDecoder().decode(Set<String>.self, from: data) else { return }
        self.localConfirmedKeys = keys
    }
    
    private func savePersistentConfirmationCache() {
        guard let fileURL = confirmationCacheFileURL,
              let data = try? JSONEncoder().encode(localConfirmedKeys) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    
    private func normalizeCallsign(_ call: String) -> String {
        var clean = call.uppercased().trimmingCharacters(in: .whitespaces)
        if let slashIdx = clean.firstIndex(of: "/") {
            clean = String(clean[..<slashIdx])
        }
        return clean
    }

    private func applyPersistentConfirmationCache(to records: inout [QSORecordModel]) -> Int {
        var matchedCount = 0
        for i in 0..<records.count {
            let call = normalizeCallsign(records[i]["CALL"])
            let date = records[i]["QSO_DATE"]
            let band = records[i]["BAND"].uppercased().trimmingCharacters(in: .whitespaces)
            
            let strictKey = "\(call)_\(date)_\(band)"
            let fallbackKey = "\(call)_\(date)"
            
            if localConfirmedKeys.contains(strictKey) || localConfirmedKeys.contains(fallbackKey) {
                if !records[i].isConfirmed {
                    records[i].fields["LOTW_QSL_RCVD"] = "Y"
                    records[i].fields["QRZLOG_QSL_RCVD"] = "Y"
                    records[i].fields["QSL_RCVD"] = "Y"
                    matchedCount += 1
                }
            } else if records[i].isConfirmed {
                localConfirmedKeys.insert(strictKey)
                localConfirmedKeys.insert(fallbackKey)
            }
        }
        
        if matchedCount > 0 {
            savePersistentConfirmationCache()
        }
        return matchedCount
    }

    // MARK: - Internal Database Operations
    
    private var internalDatabaseURL: URL? {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dbURL = appSupport.appendingPathComponent("YAAM/Logs")
        if !fm.fileExists(atPath: dbURL.path) {
            try? fm.createDirectory(at: dbURL, withIntermediateDirectories: true)
        }
        return dbURL
    }
    
    func loadRecentLogsFromDatabase() {
        guard let dbURL = internalDatabaseURL else { return }
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: dbURL, includingPropertiesForKeys: [.creationDateKey]) {
            let sortedFiles = files.filter { $0.pathExtension == "adi" || $0.pathExtension == "adif" }
                .sorted {
                    let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return d1 > d2
                }
            DispatchQueue.main.async {
                self.recentLogFiles = sortedFiles
            }
        }
    }
    
    private func archiveLogToDatabase(originalURL: URL) {
        guard let dbURL = internalDatabaseURL else { return }
        
        if originalURL.deletingLastPathComponent().path == dbURL.path {
            loadRecentLogsFromDatabase()
            return
        }
        
        let fm = FileManager.default
        let destination = dbURL.appendingPathComponent(originalURL.lastPathComponent)
        
        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: originalURL, to: destination)
            loadRecentLogsFromDatabase()
        } catch {
            print("Database archiving failed: \(error)")
        }
    }

    // MARK: - Asynchronous File Importer
    
    func loadADIFFile(from url: URL) {
        isLoading = true
        appendLog("Loading file '\(url.lastPathComponent)' in background...")
        archiveLogToDatabase(originalURL: url)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var rawContent: String? = try? String(contentsOfFile: url.path, encoding: .utf8)
            if rawContent == nil {
                rawContent = try? String(contentsOfFile: url.path, encoding: .isoLatin1)
            }
            
            guard let content = rawContent else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.appendLog("Error: Unable to read file encoding for \(url.lastPathComponent).")
                }
                return
            }
            
            let (headers, records) = parseADIF(content: content)
            var qsoModels = records.enumerated().map { (idx, dict) in
                QSORecordModel(index: idx + 1, fields: dict)
            }
            
            var finalHeaders = headers
            if !finalHeaders.contains("LOTW_QSL_RCVD") { finalHeaders.append("LOTW_QSL_RCVD") }
            if !finalHeaders.contains("QRZLOG_QSL_RCVD") { finalHeaders.append("QRZLOG_QSL_RCVD") }
            if !finalHeaders.contains("QSL_RCVD") { finalHeaders.append("QSL_RCVD") }
            
            let offlineMatched = self.applyPersistentConfirmationCache(to: &qsoModels)
            
            DispatchQueue.main.async {
                self.tableHeaders = finalHeaders
                self.qsoRecords = qsoModels
                self.loadedFileURL = url
                self.loadedFileName = url.lastPathComponent
                self.isLoading = false
                
                self.appendLog("Successfully loaded \(records.count) QSOs from \(url.lastPathComponent).")
                if offlineMatched > 0 {
                    self.appendLog("Offline Database Engine: Cross-referenced and matched \(offlineMatched) confirmations instantly from local storage.")
                }
            }
        }
    }

    // MARK: - Save & Export Handlers
    
    func saveCurrentLog() {
        guard let url = loadedFileURL else {
            saveAsCurrentLog()
            return
        }
        writeRecordsToFileAsync(records: qsoRecords.map { $0.fields }, to: url)
    }

    func saveAsCurrentLog() {
        let panel = NSSavePanel()
        var types: [UTType] = [.plainText]
        if let adiType = UTType(filenameExtension: "adi") { types.append(adiType) }
        types.append(.commaSeparatedText)
        
        panel.allowedContentTypes = types
        panel.nameFieldStringValue = loadedFileName.isEmpty ? "modified_log.adi" : loadedFileName
        
        if panel.runModal() == .OK, let url = panel.url {
            writeRecordsToFileAsync(records: qsoRecords.map { $0.fields }, to: url)
            self.loadedFileURL = url
            self.loadedFileName = url.lastPathComponent
        }
    }

    func exportFilteredLogAs() {
        let panel = NSSavePanel()
        var types: [UTType] = [.plainText]
        if let adiType = UTType(filenameExtension: "adi") { types.append(adiType) }
        types.append(.commaSeparatedText)
        
        panel.allowedContentTypes = types
        let baseName = loadedFileName.isEmpty ? "filtered_log" : URL(fileURLWithPath: loadedFileName).deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(baseName)_Filtered_Slice.adi"
        
        if panel.runModal() == .OK, let url = panel.url {
            let filteredDicts = filteredRecords.map { $0.fields }
            writeRecordsToFileAsync(records: filteredDicts, to: url)
        }
    }

    private func writeRecordsToFileAsync(records: [[String: String]], to url: URL) {
        isLoading = true
        let isCSV = url.pathExtension.lowercased() == "csv"
        let headers = tableHeaders
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if isCSV {
                let csvContent = generateCSV(headers: headers, records: records)
                let finalOutput = "\u{FEFF}" + csvContent
                do {
                    try finalOutput.write(to: url, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.appendLog("Successfully wrote CSV file to: \(url.lastPathComponent)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.appendLog("Error saving CSV file: \(error.localizedDescription)")
                    }
                }
            } else {
                let adifOutput = generateADIF(originalContent: "", records: records)
                do {
                    try adifOutput.write(to: url, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.appendLog("Successfully wrote ADIF file to: \(url.lastPathComponent)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.appendLog("Error saving ADIF file: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Offline-First Hybrid Cloud Sync Engine (LoTW & QRZ)
    
    func syncConfirmations(forceFullSync: Bool = false) {
        guard !qsoRecords.isEmpty else {
            appendLog("Error: No log loaded to sync.")
            return
        }
        
        let offlineMatched = applyPersistentConfirmationCache(to: &qsoRecords)
        if offlineMatched > 0 {
            objectWillChange.send()
            appendLog("Applied \(offlineMatched) confirmation matches from local database.")
        }
        
        let lotwUser = UserDefaults.standard.string(forKey: "lotwUsername") ?? ""
        let lotwPass = UserDefaults.standard.string(forKey: "lotwPassword") ?? ""
        let qrzKey = UserDefaults.standard.string(forKey: "qrzApiKey") ?? ""
        
        if lotwUser.isEmpty && qrzKey.isEmpty {
            self.alertTitle = "Offline Database Applied 🟢"
            self.alertMessage = "Applied \(offlineMatched) matches from local database.\nTo fetch new online confirmations from the server, please enter your LoTW/QRZ credentials in Preferences (Cmd+,)."
            self.showAlert = true
            return
        }
        
        isSyncingAPI = true
        
        let lastSyncDate = forceFullSync ? nil : (UserDefaults.standard.object(forKey: "lastLoTWSyncDate") as? Date)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let sinceDateString = lastSyncDate != nil ? dateFormatter.string(from: lastSyncDate!) : "1900-01-01"
        appendLog("Connecting to LoTW server (Since: \(sinceDateString))...")
        
        guard let encodedUser = lotwUser.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedPass = lotwPass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let lotwEndpoint = URL(string: "https://lotw.arrl.org/lotwuser/lotwreport.adi?login=\(encodedUser)&password=\(encodedPass)&qso_query=1&qso_qslsince=\(sinceDateString)") else {
            self.isSyncingAPI = false
            self.appendLog("Error: Invalid LoTW query URL encoding.")
            return
        }
        
        var request = URLRequest(url: lotwEndpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.setValue("YAAM-macOS/1.0.0", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.isSyncingAPI = false
                    self.appendLog("Network Offline/Error: \(error.localizedDescription)")
                    self.alertTitle = "Network Error (Offline Cache Retained) 🟠"
                    self.alertMessage = "Unable to connect to LoTW server (\(error.localizedDescription)).\n\nYour local persistent database was applied successfully! Check internet or enable 'Outgoing Connections (Client)' in Xcode Sandbox settings."
                    self.showAlert = true
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    DispatchQueue.main.async {
                        self.isSyncingAPI = false
                        self.appendLog("LoTW Error: Authentication failed (HTTP \(httpResponse.statusCode)).")
                        self.alertTitle = "Authentication Failed 🔴"
                        self.alertMessage = "Invalid LoTW Username or Password. Please check your credentials in Preferences (Cmd+,)."
                        self.showAlert = true
                    }
                    return
                }
            }
            
            guard let data = data, let reportADIF = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                DispatchQueue.main.async {
                    self.isSyncingAPI = false
                    self.appendLog("Error: Received empty response from LoTW server.")
                }
                return
            }
            
            if reportADIF.lowercased().contains("invalid password") || reportADIF.lowercased().contains("access denied") || reportADIF.lowercased().contains("<html") {
                DispatchQueue.main.async {
                    self.isSyncingAPI = false
                    self.appendLog("LoTW Authentication Failure: Server returned login error page.")
                    self.alertTitle = "LoTW Login Failed 🔴"
                    self.alertMessage = "LoTW rejected the credentials provided. Please verify your Username and Password in Preferences (Cmd+,)."
                    self.showAlert = true
                }
                return
            }
            
            let (_, serverRecords) = parseADIF(content: reportADIF)
            
            if serverRecords.isEmpty && !forceFullSync && lastSyncDate != nil {
                DispatchQueue.main.async {
                    self.appendLog("Incremental sync returned 0 records. Retrying full historical sync...")
                    self.syncConfirmations(forceFullSync: true)
                }
                return
            }
            
            for rec in serverRecords {
                let call = self.normalizeCallsign(rec["CALL"] ?? "")
                let date = rec["QSO_DATE"] ?? ""
                let band = (rec["BAND"] ?? "").uppercased().trimmingCharacters(in: .whitespaces)
                
                let lotwRcvd = (rec["LOTW_QSL_RCVD"] ?? "").uppercased()
                let qslRcvd = (rec["QSL_RCVD"] ?? "").uppercased()
                
                if lotwRcvd == "Y" || lotwRcvd == "V" || qslRcvd == "Y" {
                    self.localConfirmedKeys.insert("\(call)_\(date)_\(band)")
                    self.localConfirmedKeys.insert("\(call)_\(date)")
                }
            }
            self.savePersistentConfirmationCache()
            
            DispatchQueue.main.async {
                let totalUpdated = self.applyPersistentConfirmationCache(to: &self.qsoRecords)
                self.isSyncingAPI = false
                UserDefaults.standard.set(Date(), forKey: "lastLoTWSyncDate")
                
                self.appendLog("LoTW Server returned \(serverRecords.count) confirmed records. \(totalUpdated) new matches updated in local log.")
                
                if totalUpdated > 0 {
                    self.objectWillChange.send()
                    self.alertTitle = "Cloud Sync Complete 🟢"
                    self.alertMessage = "Successfully fetched and saved new confirmations to persistent local database!\nUpdated \(totalUpdated) QSO(s) in active view."
                    self.showAlert = true
                    self.saveCurrentLog()
                } else {
                    self.alertTitle = "Log Up To Date ⚪"
                    self.alertMessage = "Server report processed. All matches are already up to date in your local database."
                    self.showAlert = true
                }
            }
        }.resume()
    }

    // MARK: - Dialogs & Updates
    
    func importADIFDialog() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText]
        if let adiType = UTType(filenameExtension: "adi") { types.append(adiType) }
        if let adifType = UTType(filenameExtension: "adif") { types.append(adifType) }
        
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            loadADIFFile(from: url)
        }
    }

    func showAboutDialog() {
        alertTitle = "About YAAM"
        alertMessage = """
        YAAM - Yet Another ADIF Manager
        Version \(currentVersion)

        Developed by EP2AES

        A fast, native macOS Amateur Radio logbook manager featuring offline QSL caching, live LoTW cloud sync, interactive grid editing, and advanced analytics.
        """
        showAlert = true
    }

    func checkForUpdates() {
        appendLog("Checking for updates...")
        isCheckingUpdates = true
        
        guard let url = URL(string: "https://api.github.com/repos/factoreal/ADIF-to-Excel/releases/latest") else {
            isCheckingUpdates = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isCheckingUpdates = false
                
                if let error = error {
                    self.appendLog("Update check failed: \(error.localizedDescription)")
                    self.alertTitle = "Check Updates"
                    self.alertMessage = "Unable to connect to update server.\nYou are currently running version \(self.currentVersion)."
                    self.showAlert = true
                    return
                }
                
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let latestTag = json["tag_name"] as? String {
                    let cleanTag = latestTag.replacingOccurrences(of: "v", with: "")
                    if cleanTag != self.currentVersion {
                        self.appendLog("New update available: \(latestTag)")
                        self.alertTitle = "Update Available!"
                        self.alertMessage = "A new version (\(latestTag)) is available.\nYour current version is \(self.currentVersion)."
                        
                        if let htmlUrl = json["html_url"] as? String, let downloadURL = URL(string: htmlUrl) {
                            NSWorkspace.shared.open(downloadURL)
                        }
                    } else {
                        self.appendLog("You are running the latest version.")
                        self.alertTitle = "Up to Date"
                        self.alertMessage = "You are running the latest version (\(self.currentVersion))."
                    }
                } else {
                    self.appendLog("You are running the latest version.")
                    self.alertTitle = "Up to Date"
                    self.alertMessage = "You are running the latest version (\(self.currentVersion))."
                }
                self.showAlert = true
            }
        }.resume()
    }
}
