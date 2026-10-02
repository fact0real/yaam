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
        return Self(
            worked: Set(matching.map { $0.band.lowercased() }.filter { !$0.isEmpty }),
            confirmed: Set(matching.filter(\.confirmed).map { $0.band.lowercased() }.filter { !$0.isEmpty }),
            qsoCount: matching.count
        )
    }

    static let empty = Self(worked: [], confirmed: [], qsoCount: 0)
}

nonisolated enum SKEDMailTemplate {
    static let bands = [
        "2190m", "630m", "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m",
        "6m", "4m", "2m", "1.25m", "70cm", "33cm", "23cm", "13cm", "9cm", "6cm", "3cm", "1.25cm"
    ]

    static let defaultSubject = "A friendly SKED request from {my_callsign} to {callsign}"
    static let defaultBody = """
    Hi {greeting},

    I hope you're doing well! I'm {my_callsign}{my_location}, and I'd love to arrange a SKED with you on {bands}.

    Would any of these bands work for you? I'm happy to find a time and mode that suits us both. Please let me know what you think, and what time works best at your end.

    Looking forward to meeting you on the air!

    73,
    {my_callsign}
    """

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
                       stationQTH: String) -> String {
        let greeting = name?.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? callsign
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
            "{my_location}": location
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
