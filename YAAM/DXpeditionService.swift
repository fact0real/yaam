//
//  DXpeditionService.swift
//  YAAM
//

import Foundation
import UserNotifications

nonisolated struct DXpeditionEntry: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let callsign: String
    let entity: String
    let start: String
    let end: String

    var isActive: Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy MMMdd"
        guard let startDate = formatter.date(from: start), let endDate = formatter.date(from: end) else { return false }
        let now = Date()
        return now >= startDate && now < Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: endDate)!
    }
}

nonisolated struct DXpeditionCache: Codable, Sendable {
    let entries: [DXpeditionEntry]
    let updatedAt: Date
}

nonisolated enum DXpeditionService {
    static let sourceURL = URL(string: "https://dxping.com/dxpeditions.php")!

    static func parse(_ html: String) -> [DXpeditionEntry] {
        guard let rowRegex = try? NSRegularExpression(pattern: #"(?is)<tr[^>]*>(.*?)</tr>"#) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var entries: [DXpeditionEntry] = []
        var seen = Set<String>()

        for match in rowRegex.matches(in: html, range: range) {
            guard let rowRange = Range(match.range(at: 1), in: html) else { continue }
            let row = String(html[rowRange])
            let cells = textCells(in: row)
            guard cells.count >= 4 else { continue }
            let call = cells[0].uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard call.range(of: #"^[A-Z0-9/]{2,12}$"#, options: .regularExpression) != nil,
                  cells[2].range(of: #"^\d{4}\s+[A-Za-z]{3}\d{1,2}$"#, options: .regularExpression) != nil,
                  cells[3].range(of: #"^\d{4}\s+[A-Za-z]{3}\d{1,2}$"#, options: .regularExpression) != nil
            else { continue }
            let entry = DXpeditionEntry(
                id: "\(call)|\(cells[2])|\(cells[3])",
                callsign: call,
                entity: cells[1],
                start: cells[2],
                end: cells[3]
            )
            guard seen.insert(entry.id).inserted else { continue }
            entries.append(entry)
        }
        return entries
    }

    private static func textCells(in row: String) -> [String] {
        guard let cellRegex = try? NSRegularExpression(pattern: #"(?is)<td[^>]*>(.*?)</td>"#) else { return [] }
        let range = NSRange(row.startIndex..., in: row)
        return cellRegex.matches(in: row, range: range).compactMap { match in
            guard let cellRange = Range(match.range(at: 1), in: row) else { return nil }
            return plainText(String(row[cellRange]))
        }
    }

    private static func plainText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"(?is)<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension AppState {
    private static let dxpeditionCacheKey = "dxpeditionCache.v1"

    func loadDXpeditionCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.dxpeditionCacheKey),
              let cache = try? JSONDecoder().decode(DXpeditionCache.self, from: data)
        else { return }
        dxpeditionEntries = cache.entries
        dxpeditionLastUpdated = cache.updatedAt
        dxpeditionStatus = "Showing saved DXpedition list"
    }

    func fetchDXpeditions(force: Bool = false) {
        guard !isFetchingDXpeditions else { return }
        if !force, let updated = dxpeditionLastUpdated, Date().timeIntervalSince(updated) < 60 * 60 * 3, !dxpeditionEntries.isEmpty { return }

        isFetchingDXpeditions = true
        dxpeditionStatus = "Refreshing announced DXpeditions..."
        var request = URLRequest(url: DXpeditionService.sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue("YAAM/\(currentVersion) (+https://github.com/fact0real/yaam)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let entries = data.flatMap { String(data: $0, encoding: .utf8) }.map(DXpeditionService.parse) ?? []
            let responseOK = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetchingDXpeditions = false
                guard error == nil, responseOK, !entries.isEmpty else {
                    self.dxpeditionStatus = self.dxpeditionEntries.isEmpty ? "Could not load the DXpedition source." : "Using the last saved DXpedition list."
                    return
                }
                let now = Date()
                self.dxpeditionEntries = entries
                self.dxpeditionLastUpdated = now
                self.dxpeditionStatus = "Loaded \(entries.count) announced DXpeditions from DXPing."
                self.scheduleDXpeditionOpportunityNotifications()
                if let data = try? JSONEncoder().encode(DXpeditionCache(entries: entries, updatedAt: now)) {
                    UserDefaults.standard.set(data, forKey: Self.dxpeditionCacheKey)
                }
            }
        }.resume()
    }

    func scheduleDXpeditionOpportunityNotifications() {
        guard UserDefaults.standard.bool(forKey: "dxpeditionSpotNotifications") else { return }

        let notified = Set(UserDefaults.standard.stringArray(forKey: "dxpeditionSpotNotificationIDs") ?? [])
        let opportunities = dxpeditionEntries.compactMap { entry -> (DXpeditionEntry, DXSpot)? in
            guard let spot = dxClusterClient.spots.first(where: { $0.callsign.uppercased() == entry.callsign.uppercased() }),
                  !notified.contains(entry.id)
            else { return nil }
            return (entry, spot)
        }
        guard !opportunities.isEmpty else { return }

        for (entry, spot) in opportunities.prefix(3) {
            let content = UNMutableNotificationContent()
            content.title = "DXpedition on air: \(entry.callsign)"
            let frequency = String(format: "%.3f", spot.frequencyMHz)
            content.body = "\(entry.entity) spotted on \(spot.band) at \(frequency) MHz."
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "dxpedition.\(entry.id)", content: content, trigger: nil)
            )
        }
        let rememberedIDs = Array(Array(notified.union(opportunities.map { $0.0.id })).suffix(120))
        UserDefaults.standard.set(rememberedIDs, forKey: "dxpeditionSpotNotificationIDs")
    }
}
