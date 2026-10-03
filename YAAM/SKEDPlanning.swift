import Foundation

nonisolated struct SKEDLogBandEntry: Sendable {
    let countryISO: String
    let band: String
    let confirmed: Bool
}

nonisolated struct SKEDCountryBandActivity: Sendable {
    let worked: Set<String>
    let confirmed: Set<String>
    let qsoCount: Int

    static func make(entries: [SKEDLogBandEntry], countryISO: String) -> Self {
        let matching = entries.filter { $0.countryISO.caseInsensitiveCompare(countryISO) == .orderedSame }
        let shownBands = Set(SKEDMailTemplate.bands)
        return Self(
            worked: Set(matching.map { $0.band.lowercased() }.filter(shownBands.contains)),
            confirmed: Set(matching.filter(\.confirmed).map { $0.band.lowercased() }.filter(shownBands.contains)),
            qsoCount: matching.count
        )
    }

    static let empty = Self(worked: [], confirmed: [], qsoCount: 0)
}

nonisolated struct SKEDOperatorLogBandEntry: Sendable {
    let callsign: String
    let band: String
    let confirmed: Bool
}

nonisolated struct SKEDOperatorBandActivity: Sendable {
    let worked: Set<String>
    let confirmed: Set<String>
    let qsoCount: Int

    static func grouped(entries: [SKEDOperatorLogBandEntry]) -> [String: Self] {
        var result: [String: Self] = [:]
        for entry in entries {
            let call = entry.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !call.isEmpty else { continue }
            let band = entry.band.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let previous = result[call] ?? Self(worked: [], confirmed: [], qsoCount: 0)
            var worked = previous.worked
            var confirmed = previous.confirmed
            if !band.isEmpty {
                worked.insert(band)
                if entry.confirmed { confirmed.insert(band) }
            }
            result[call] = Self(worked: worked, confirmed: confirmed, qsoCount: previous.qsoCount + 1)
        }
        return result
    }

    var bandSummary: String {
        let order = SKEDMailTemplate.bands
        func sorted(_ bands: Set<String>) -> [String] {
            bands.sorted { left, right in
                let leftIndex = order.firstIndex(of: left) ?? Int.max
                let rightIndex = order.firstIndex(of: right) ?? Int.max
                return leftIndex == rightIndex ? left < right : leftIndex < rightIndex
            }
        }
        let confirmedText = sorted(confirmed).joined(separator: ", ")
        let unconfirmedText = sorted(worked.subtracting(confirmed)).joined(separator: ", ")
        switch (confirmedText.isEmpty, unconfirmedText.isEmpty) {
        case (false, false): return "Confirmed \(confirmedText) · Worked \(unconfirmedText)"
        case (false, true): return "Confirmed \(confirmedText)"
        case (true, false): return "Worked \(unconfirmedText)"
        case (true, true): return "Band not recorded"
        }
    }
}

nonisolated enum SKEDMailTemplate {
    static let bands = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"]

    static let defaultSubject = "A friendly SKED request from {my_callsign} to {callsign}"
    static let defaultBody = """
    Hi {greeting} ({callsign}),

    It's {my_callsign}{my_location}. I'd love to set up a SKED with you on {bands}. Those bands look promising with the current propagation, and they're a good match for my antenna's resonance.

    {time_window}

    Let me know what works for you, and we can pick a mode that suits us both. It'll be great to catch you on the air!
    """

    static func fourCharacterGrid(_ value: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return clean.count >= 4 ? String(clean.prefix(4)) : ""
    }

    static func utcWindow(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return "Could you do a SKED between \(formatter.string(from: start)) and \(formatter.string(from: end))?"
    }

    static func signature(name: String, callsign: String) -> String {
        "73,\n\(name.split(whereSeparator: \.isWhitespace).joined(separator: " "))\n\(callsign)"
    }

    static func ordered(_ selected: Set<String>) -> [String] {
        bands.filter { selected.contains($0) }
    }

    static func bandPhrase(_ selected: Set<String>) -> String {
        let values = ordered(selected)
        switch values.count {
        case 0: return ""
        case 1: return values[0]
        case 2: return values.joined(separator: " and ")
        default: return values.dropLast().joined(separator: ", ") + ", and " + values.last!
        }
    }

    static func render(_ template: String, callsign: String, name: String?,
                       bands: Set<String>, stationCallsign: String, stationGrid: String,
                       stationQTH: String, stationName: String = "",
                       timeWindowUTC: String? = nil) -> String {
        let greeting = name?.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "there"
        let location: String
        if !stationQTH.isEmpty && !stationGrid.isEmpty {
            location = " in \(stationQTH) (grid \(stationGrid))"
        } else if !stationQTH.isEmpty {
            location = " in \(stationQTH)"
        } else if !stationGrid.isEmpty {
            location = " (grid \(stationGrid))"
        } else {
            location = ""
        }
        let replacements = [
            "{greeting}": greeting,
            "{name}": name ?? callsign,
            "{callsign}": callsign,
            "{bands}": bandPhrase(bands),
            "{my_callsign}": stationCallsign,
            "{my_grid}": stationGrid,
            "{my_qth}": stationQTH,
            "{my_location}": location,
            "{my_name}": stationName,
            "{time_window}": timeWindowUTC ?? "I'm flexible on timing, so feel free to suggest a slot that works for you."
        ]
        return replacements.reduce(template) { result, pair in
            result.replacingOccurrences(of: pair.key, with: pair.value)
        }
    }

    static func safeSubject(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? Unicode.Scalar(" ") : $0
        }))
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    }
}
