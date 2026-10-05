//
//  LoTWActivityDatabase.swift
//  YAAM
//
//  Manages ARRL LoTW user activity database for DX cluster and log intelligence.
//

import Foundation
import Combine

public final class LoTWActivityDatabase: ObservableObject {
    public static let shared = LoTWActivityDatabase()

    @Published public private(set) var isLoaded: Bool = false
    @Published public private(set) var userCount: Int = 0
    @Published public private(set) var lastDatabaseUpdate: Date?
    @Published public private(set) var isUpdating: Bool = false
    @Published public private(set) var lastErrorMessage: String?

    private var activityMap: [String: Date] = [:]
    private let queue = DispatchQueue(label: "app.yaam.lotw-activity", qos: .userInitiated)
    private let lock = NSLock()
    private let remoteURL = URL(string: "https://lotw.arrl.org/lotw-user-activity.csv")!

    private var cacheFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let yaamDir = appSupport.appendingPathComponent("YAAM", isDirectory: true)
        try? FileManager.default.createDirectory(at: yaamDir, withIntermediateDirectories: true)
        return yaamDir.appendingPathComponent("lotw-user-activity.csv")
    }

    public init() {
        loadFromCacheAsync()
    }

    // MARK: - Public Queries

    /// Returns true if the callsign is an active LoTW user (uploaded within the given days, default 365 days)
    public func isUserActive(_ callsign: String, withinDays days: Int = 365) -> Bool {
        guard let uploadDate = lastUploadDate(for: callsign) else { return false }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400.0)
        return uploadDate >= cutoff
    }

    /// Returns the exact last upload date if present in the database
    public func lastUploadDate(for callsign: String) -> Date? {
        let clean = cleanCallsign(callsign)
        lock.lock()
        defer { lock.unlock() }
        return activityMap[clean]
    }

    /// Returns a human-friendly string for UI tooltips
    public func lastUploadDescription(for callsign: String) -> String {
        guard let date = lastUploadDate(for: callsign) else {
            return "No LoTW upload on record"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let isRecent = isUserActive(callsign, withinDays: 365)
        let formattedDate = formatter.string(from: date)
        if isRecent {
            return "LoTW Active: Last uploaded \(formattedDate)"
        } else {
            return "LoTW Inactive: Last uploaded \(formattedDate) (>1 year ago)"
        }
    }

    // MARK: - Cache & Web Sync

    public func loadFromCacheAsync() {
        queue.async { [weak self] in
            guard let self else { return }
            let fileURL = self.cacheFileURL
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                if let bundleURL = Bundle.main.url(forResource: "lotw-user-activity", withExtension: "csv") {
                    try? FileManager.default.copyItem(at: bundleURL, to: fileURL)
                } else {
                    let devURL = URL(fileURLWithPath: "YAAM/Resources/lotw-user-activity.csv")
                    if FileManager.default.fileExists(atPath: devURL.path) {
                        try? FileManager.default.copyItem(at: devURL, to: fileURL)
                    }
                }
            }

            guard let data = try? Data(contentsOf: fileURL) else { return }
            self.parseCSVData(data)
        }
    }

    public func updateFromWeb() async throws -> Int {
        DispatchQueue.main.async {
            self.isUpdating = true
            self.lastErrorMessage = nil
        }

        defer {
            DispatchQueue.main.async {
                self.isUpdating = false
            }
        }

        do {
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 60
            request.setValue("YAAM-macOS-Logbook/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            guard let statusCode, (200...299).contains(statusCode) else {
                let detail = statusCode.map { "HTTP \($0)" } ?? "no HTTP response"
                throw NSError(domain: "LoTWActivityDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to download from ARRL (\(detail))"])
            }

            // A 2xx reply that is not the LoTW list (captive portal, maintenance page) must not replace the
            // cache file or the map in memory: parse first and keep the previous data unless rows were found.
            guard let newMap = Self.parseMap(data), !newMap.isEmpty else {
                throw NSError(domain: "LoTWActivityDatabase", code: 2, userInfo: [NSLocalizedDescriptionKey: "ARRL returned a file that is not the LoTW activity list; keeping the previous data."])
            }
            let previousCount = lock.withLock { activityMap.count }
            // A truncated but syntactically valid CSV must not replace a full cache.
            if previousCount >= 10_000 && newMap.count < previousCount / 2 {
                throw NSError(domain: "LoTWActivityDatabase", code: 3, userInfo: [NSLocalizedDescriptionKey: "ARRL returned an incomplete LoTW activity list; keeping the previous data."])
            }

            try data.write(to: cacheFileURL, options: .atomic)
            let count = install(newMap)

            DispatchQueue.main.async {
                self.lastDatabaseUpdate = Date()
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lotwDatabaseLastUpdated")
            }

            return count
        } catch {
            DispatchQueue.main.async {
                self.lastErrorMessage = error.localizedDescription
            }
            throw error
        }
    }

    // MARK: - Parsing

    @discardableResult
    public func parseCSVData(_ data: Data) -> Int {
        guard let map = Self.parseMap(data) else { return 0 }
        return install(map)
    }

    private func install(_ map: [String: Date]) -> Int {
        let total = map.count
        lock.lock()
        self.activityMap = map
        lock.unlock()

        DispatchQueue.main.async {
            self.userCount = total
            self.isLoaded = true
        }

        return total
    }

    private static func parseMap(_ data: Data) -> [String: Date]? {
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        var map: [String: Date] = [:]
        map.reserveCapacity(200_000)

        // Custom fast ISO parser for YYYY-MM-DD
        let calendar = Calendar(identifier: .gregorian)
        var dateComponents = DateComponents()
        dateComponents.timeZone = TimeZone(secondsFromGMT: 0)

        var dateCache: [String: Date] = [:]
        dateCache.reserveCapacity(5_000)

        content.enumerateLines { line, _ in
            let parts = line.split(separator: ",", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { return }
            let call = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !call.isEmpty else { return }

            let dateString = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let cachedDate = dateCache[dateString] {
                map[call] = cachedDate
            } else if let parsedDate = Self.parseFastDate(dateString, calendar: calendar, components: &dateComponents) {
                dateCache[dateString] = parsedDate
                map[call] = parsedDate
            }
        }

        return map
    }

    private static func parseFastDate(_ str: String, calendar: Calendar, components: inout DateComponents) -> Date? {
        let parts = str.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    private func cleanCallsign(_ raw: String) -> String {
        let call = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        lock.lock()
        defer { lock.unlock() }
        if activityMap[call] != nil {
            return call
        }
        if let slashIndex = call.firstIndex(of: "/") {
            let base = String(call[..<slashIndex])
            if activityMap[base] != nil {
                return base
            }
        }
        return call
    }
}
