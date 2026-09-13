//
//  CTYDatabaseManager.swift
//  YAAM
//
//  Offline Country Files (CTY.DAT / CTY_WT.DAT) and 4-Character Grid Locator Database Engine.
//  Provides high-performance prefix resolution, ADIF DXCC entity lookup, zone overrides,
//  and automatic staleness detection with web sync capabilities.
//

import Foundation
import Combine

public struct CTYEntityInfo: Sendable, Equatable, Hashable {
    public let adifCode: Int
    public let entityName: String
    public let cqZone: Int
    public let ituZone: Int
    public let continent: String
    public let latitude: Double
    public let longitude: Double
    public let timeOffset: Double
    public let primaryPrefix: String
    public let flagEmoji: String
}

public struct CTYLookupResult: Sendable, Equatable {
    public let entity: CTYEntityInfo
    public let matchedPattern: String
    public let cqZone: Int
    public let ituZone: Int
    public let latitude: Double
    public let longitude: Double
    public let isExactMatch: Bool
}

public final class CTYDatabaseManager: ObservableObject {
    public static let shared = CTYDatabaseManager()

    @Published public private(set) var isLoaded: Bool = false
    @Published public private(set) var releaseVersion: String = "Loading..."
    @Published public private(set) var releaseDate: Date? = nil
    @Published public private(set) var isStale: Bool = false // > 30 days old
    @Published public private(set) var entityCount: Int = 0
    @Published public private(set) var prefixRuleCount: Int = 0
    @Published public private(set) var isUpdating: Bool = false
    @Published public private(set) var lastUpdateError: String? = nil

    private struct PrefixRule {
        let pattern: String
        let entity: CTYEntityInfo
        let cqOverride: Int?
        let ituOverride: Int?
        let latOverride: Double?
        let lonOverride: Double?
    }

    private var entitiesByADIF: [Int: CTYEntityInfo] = [:]
    private var exactCallsignMap: [String: CTYLookupResult] = [:]
    private var prefixMapByLength: [Int: [String: PrefixRule]] = [:] // Length 1..12 -> [Prefix: Rule]
    private var maxPrefixLength: Int = 0
    private var grid4Map: [String: Int] = [:] // 4-char grid -> ADIF code
    private let queue = DispatchQueue(label: "app.yaam.cty-database", qos: .userInitiated)
    private let lock = NSLock()

    private var ctyCacheFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let yaamDir = appSupport.appendingPathComponent("YAAM", isDirectory: true)
        try? FileManager.default.createDirectory(at: yaamDir, withIntermediateDirectories: true)
        return yaamDir.appendingPathComponent("cty_wt.dat")
    }

    private var gridCacheFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let yaamDir = appSupport.appendingPathComponent("YAAM", isDirectory: true)
        return yaamDir.appendingPathComponent("grid_dxcc_4char_simple.csv")
    }

    private init() {
        loadAsync()
    }

    // MARK: - Asynchronous Database Loading

    public func loadAsync() {
        queue.async { [weak self] in
            guard let self else { return }
            self.loadSync()
        }
    }

    public func loadSync() {
        // Ensure files exist in Application Support; if not, copy from bundle or project resources
        ensureResourceFile(named: "cty_wt.dat", destination: ctyCacheFileURL)
        ensureResourceFile(named: "grid_dxcc_4char_simple.csv", destination: gridCacheFileURL)

        // 1. Parse Grid Database
        if let gridData = try? Data(contentsOf: gridCacheFileURL) {
            parseGridCSV(gridData)
        }

        // 2. Parse CTY.DAT Database
        if let ctyData = try? Data(contentsOf: ctyCacheFileURL) {
            parseCTYDAT(ctyData)
        }
    }

    private func ensureResourceFile(named fileName: String, destination: URL) {
        if !FileManager.default.fileExists(atPath: destination.path) {
            if let bundleURL = Bundle.main.url(forResource: fileName, withExtension: nil) {
                try? FileManager.default.copyItem(at: bundleURL, to: destination)
            } else {
                let devURL = URL(fileURLWithPath: "YAAM/Resources/\(fileName)")
                if FileManager.default.fileExists(atPath: devURL.path) {
                    try? FileManager.default.copyItem(at: devURL, to: destination)
                }
            }
        }
    }

    // MARK: - Parsing

    private func parseGridCSV(_ data: Data) {
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }
        var tempGrid: [String: Int] = [:]
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }
            let parts = trimmed.split(separator: ",")
            if parts.count >= 2,
               let adif = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                let grid = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
                tempGrid[grid] = adif
            }
        }

        lock.lock()
        self.grid4Map = tempGrid
        lock.unlock()
    }

    private func parseCTYDAT(_ data: Data) {
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }

        var versionString = "CTY-3630"
        var parsedReleaseDate: Date? = nil
        var tempEntities: [Int: CTYEntityInfo] = [:]
        var tempExact: [String: CTYLookupResult] = [:]
        var tempPrefixMap: [Int: [String: PrefixRule]] = [:]
        var maxLen = 0
        var totalRules = 0

        var pendingADIF: Int = 0
        var currentEntity: CTYEntityInfo? = nil
        var currentTokens = ""

        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            if trimmed.hasPrefix("#") {
                if trimmed.contains("RELEASE") {
                    let parts = trimmed.components(separatedBy: "RELEASE")
                    if parts.count > 1 {
                        versionString = parts[1].trimmingCharacters(in: .whitespaces)
                        // Try parsing date YYYY.MM.DD
                        let dateParts = versionString.split(separator: ".")
                        if dateParts.count >= 3,
                           let year = Int(dateParts[0]),
                           let month = Int(dateParts[1]),
                           let day = Int(dateParts[2]) {
                            var comp = DateComponents()
                            comp.year = year
                            comp.month = month
                            comp.day = day
                            parsedReleaseDate = Calendar(identifier: .gregorian).date(from: comp)
                        }
                    }
                } else if trimmed.contains("ADIF") {
                    let parts = trimmed.components(separatedBy: "ADIF")
                    if parts.count > 1, let adif = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                        pendingADIF = adif
                    }
                }
                return
            }

            // Check if this is an entity header line (ends with a colon ':')
            if currentEntity == nil {
                // Header format: Name: CQ: ITU: Cont: Lat: Lon: Offset: PrimaryPrefix:
                let fields = trimmed.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                if fields.count >= 8 {
                    let name = fields[0]
                    let cq = Int(fields[1]) ?? 0
                    let itu = Int(fields[2]) ?? 0
                    let cont = fields[3]
                    let lat = Double(fields[4]) ?? 0.0
                    let lon = Double(fields[5]) ?? 0.0
                    let offset = Double(fields[6]) ?? 0.0
                    let primaryPrefix = fields[7]
                    let adif = pendingADIF > 0 ? pendingADIF : (Int(primaryPrefix) ?? 0)

                    let flag = countryToFlag(name)
                    let entity = CTYEntityInfo(
                        adifCode: adif,
                        entityName: name,
                        cqZone: cq,
                        ituZone: itu,
                        continent: cont,
                        latitude: lat,
                        longitude: lon,
                        timeOffset: offset,
                        primaryPrefix: primaryPrefix,
                        flagEmoji: flag
                    )
                    currentEntity = entity
                    tempEntities[adif] = entity
                    pendingADIF = 0
                    currentTokens = ""
                }
            } else {
                // Prefix lines follow header
                currentTokens.append(" ")
                currentTokens.append(trimmed)

                if trimmed.contains(";") {
                    // Semicolon marks the end of prefixes for this entity
                    if let entity = currentEntity {
                        let tokens = currentTokens
                            .replacingOccurrences(of: ";", with: "")
                            .components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }

                        for rawToken in tokens {
                            let (cleanPattern, isExact, cqOvr, ituOvr, latOvr, lonOvr) = self.parseToken(rawToken)
                            guard !cleanPattern.isEmpty else { continue }
                            totalRules += 1

                            if isExact {
                                let res = CTYLookupResult(
                                    entity: entity,
                                    matchedPattern: cleanPattern,
                                    cqZone: cqOvr ?? entity.cqZone,
                                    ituZone: ituOvr ?? entity.ituZone,
                                    latitude: latOvr ?? entity.latitude,
                                    longitude: lonOvr ?? entity.longitude,
                                    isExactMatch: true
                                )
                                tempExact[cleanPattern] = res
                            } else {
                                let rule = PrefixRule(
                                    pattern: cleanPattern,
                                    entity: entity,
                                    cqOverride: cqOvr,
                                    ituOverride: ituOvr,
                                    latOverride: latOvr,
                                    lonOverride: lonOvr
                                )
                                let len = cleanPattern.count
                                if tempPrefixMap[len] == nil {
                                    tempPrefixMap[len] = [:]
                                }
                                tempPrefixMap[len]?[cleanPattern] = rule
                                if len > maxLen { maxLen = len }
                            }
                        }
                    }

                    // Reset for next entity
                    currentEntity = nil
                    currentTokens = ""
                }
            }
        }

        let isDatabaseStale: Bool
        if let release = parsedReleaseDate {
            isDatabaseStale = Date().timeIntervalSince(release) > (30 * 86_400)
        } else {
            isDatabaseStale = false
        }

        lock.lock()
        self.entitiesByADIF = tempEntities
        self.exactCallsignMap = tempExact
        self.prefixMapByLength = tempPrefixMap
        self.maxPrefixLength = maxLen
        lock.unlock()

        DispatchQueue.main.async {
            self.releaseVersion = versionString
            self.releaseDate = parsedReleaseDate
            self.isStale = isDatabaseStale
            self.entityCount = tempEntities.count
            self.prefixRuleCount = totalRules
            self.isLoaded = true
        }
    }

    private func parseToken(_ token: String) -> (pattern: String, isExact: Bool, cqOverride: Int?, ituOverride: Int?, latOverride: Double?, lonOverride: Double?) {
        var str = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let isExact = str.hasPrefix("=")
        if isExact {
            str.removeFirst()
        }

        var cqOvr: Int? = nil
        var ituOvr: Int? = nil
        var latOvr: Double? = nil
        var lonOvr: Double? = nil

        // Extract (CQ)
        if let start = str.firstIndex(of: "("), let end = str.firstIndex(of: ")"), start < end {
            let inside = String(str[str.index(after: start)..<end])
            cqOvr = Int(inside)
            str.removeSubrange(start...end)
        }

        // Extract [ITU]
        if let start = str.firstIndex(of: "["), let end = str.firstIndex(of: "]"), start < end {
            let inside = String(str[str.index(after: start)..<end])
            ituOvr = Int(inside)
            str.removeSubrange(start...end)
        }

        // Extract <lat/lon>
        if let start = str.firstIndex(of: "<"), let end = str.firstIndex(of: ">"), start < end {
            let inside = String(str[str.index(after: start)..<end])
            let coords = inside.split(separator: "/")
            if coords.count == 2 {
                latOvr = Double(coords[0])
                lonOvr = Double(coords[1])
            }
            str.removeSubrange(start...end)
        }

        // Extract ~offset~
        if let start = str.firstIndex(of: "~"), let end = str.lastIndex(of: "~"), start < end {
            str.removeSubrange(start...end)
        }

        let clean = str.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return (clean, isExact, cqOvr, ituOvr, latOvr, lonOvr)
    }

    // MARK: - Public Queries

    /// Fast O(1) lookup of a callsign against exact callsign overrides and longest prefix match
    public func lookup(callsign: String) -> CTYLookupResult? {
        let clean = cleanCallsign(callsign)
        guard !clean.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }

        // 1. Exact callsign match
        if let exact = exactCallsignMap[clean] {
            return exact
        }

        // 2. Handle guest operating prefix: e.g. VP8/G4XYZ or G4XYZ/VP8
        let targetPrefix: String
        if clean.contains("/") {
            let parts = clean.components(separatedBy: "/")
            if parts.count == 2 {
                let firstPart = parts[0]
                let lastPart = parts[1]
                let portableSuffixes: Set<String> = ["P", "M", "MM", "AM", "QRP", "R", "B", "LGT", "LH", "J", "A", "FF", "POTA", "SOTA"]

                if !portableSuffixes.contains(firstPart) && firstPart.count <= lastPart.count {
                    targetPrefix = firstPart
                } else if !portableSuffixes.contains(lastPart) && lastPart.count < firstPart.count {
                    targetPrefix = lastPart
                } else {
                    targetPrefix = firstPart
                }
            } else {
                targetPrefix = clean
            }
        } else {
            targetPrefix = clean
        }

        // 3. Longest prefix match: check from maxPrefixLength down to 1
        let searchLen = min(targetPrefix.count, maxPrefixLength)
        for len in stride(from: searchLen, through: 1, by: -1) {
            let sub = String(targetPrefix.prefix(len))
            if let map = prefixMapByLength[len], let rule = map[sub] {
                return CTYLookupResult(
                    entity: rule.entity,
                    matchedPattern: rule.pattern,
                    cqZone: rule.cqOverride ?? rule.entity.cqZone,
                    ituZone: rule.ituOverride ?? rule.entity.ituZone,
                    latitude: rule.latOverride ?? rule.entity.latitude,
                    longitude: rule.lonOverride ?? rule.entity.longitude,
                    isExactMatch: false
                )
            }
        }

        return nil
    }

    /// Lookup DXCC Entity information by 4-character Maidenhead locator (e.g. LM65 -> Iran, JO01 -> England)
    public func lookup(grid: String) -> CTYEntityInfo? {
        let clean = grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 4 else { return nil }
        let grid4 = String(clean.prefix(4))

        lock.lock()
        let adif = grid4Map[grid4]
        let entity = adif != nil ? entitiesByADIF[adif!] : nil
        lock.unlock()

        return entity
    }

    /// Lookup DXCC entity by ADIF code
    public func lookup(adifCode: Int) -> CTYEntityInfo? {
        lock.lock()
        defer { lock.unlock() }
        return entitiesByADIF[adifCode]
    }

    // MARK: - Online Sync

    public func updateFromWeb() async throws -> Int {
        DispatchQueue.main.async {
            self.isUpdating = true
            self.lastUpdateError = nil
        }

        defer {
            DispatchQueue.main.async {
                self.isUpdating = false
            }
        }

        guard let url = URL(string: "https://www.country-files.com/cty/cty_wt.dat") else {
            throw NSError(domain: "CTYDatabaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue("YAAM-macOS-Logbook/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "CTYDatabaseManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Country-Files server returned HTTP error"])
        }

        try data.write(to: ctyCacheFileURL, options: .atomic)
        parseCTYDAT(data)

        return entityCount
    }

    private func cleanCallsign(_ raw: String) -> String {
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
