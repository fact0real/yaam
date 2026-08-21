//
//  ContestCalendarService.swift
//  YAAM
//

import Foundation

nonisolated struct ContestCalendarEntry: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let utcWindow: String
    let geographicFocus: String
    let participation: String
    let modes: String
    let bands: String
    let sourceURL: String

    var isMiddleEastRelevant: Bool {
        let context = "\(title) \(geographicFocus)".uppercased()
        return ["WORLDWIDE", "ASIA", "EUROPE", "MIDDLE EAST", "TURKIYE", "TURKEY", "IRAN"].contains { context.contains($0) }
    }

    var operatingSummary: String {
        [modes, bands].filter { !$0.isEmpty && $0 != "Not specified" }.joined(separator: " · ")
    }
}

nonisolated struct ContestCalendarCache: Codable, Sendable {
    let entries: [ContestCalendarEntry]
    let updatedAt: Date
}

nonisolated enum ContestCalendarService {
    static let weeklyURL = URL(string: "https://www.contestcalendar.com/weeklycont.php")!
    static let fiveWeekURL = URL(string: "https://www.contestcalendar.com/fivewkcal.php")!

    static func parse(_ html: String) -> [ContestCalendarEntry] {
        let lines = normalizedLines(from: html)
        var entries: [ContestCalendarEntry] = []
        var seen = Set<String>()

        for index in lines.indices {
            guard let event = eventLine(lines[index]) else { continue }

            let details = Array(lines.dropFirst(index + 1).prefix(14))
            let entry = ContestCalendarEntry(
                id: stableID(title: event.title, window: event.window),
                title: event.title,
                utcWindow: event.window,
                geographicFocus: value(after: "Geographic Focus:", in: details) ?? "Not specified",
                participation: value(after: "Participation:", in: details) ?? "Not specified",
                modes: value(after: "Mode:", in: details) ?? "Not specified",
                bands: value(after: "Bands:", in: details) ?? "Not specified",
                sourceURL: weeklyURL.absoluteString
            )
            guard seen.insert(entry.id).inserted else { continue }
            entries.append(entry)
        }

        return Array(entries.prefix(60))
    }

    private static func eventLine(_ line: String) -> (title: String, window: String)? {
        guard let separator = line.firstIndex(of: ":") else { return nil }
        let title = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let window = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 3, title.count <= 140,
              window.contains("Z"),
              window.range(of: #"\b\d{4}Z"#, options: .regularExpression) != nil,
              !title.hasPrefix("Geographic"),
              !title.hasPrefix("Last updated")
        else { return nil }
        return (title, window)
    }

    private static func value(after label: String, in lines: [String]) -> String? {
        lines.first { $0.hasPrefix(label) }?
            .dropFirst(label.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedLines(from html: String) -> [String] {
        var text = html
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)</?(tr|p|div|li|h[1-6])[^>]*>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        return text
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func stableID(title: String, window: String) -> String {
        "\(title)|\(window)"
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
    }
}
