import Foundation

nonisolated struct SKEDLogBandEntry: Sendable {
    let countryISO: String
    let band: String
    let confirmed: Bool
}

nonisolated enum SKEDStateLogMatch {
    static func matches(destinationISO: String, stateCode: String, stateName: String,
                        loggedISO: String, loggedState: String) -> Bool {
        let countryMatches = loggedISO.caseInsensitiveCompare(destinationISO) == .orderedSame
            || (["PR", "GU", "VI"].contains(stateCode) && loggedISO.caseInsensitiveCompare(stateCode) == .orderedSame)
        guard countryMatches else { return false }
        guard !stateCode.isEmpty else { return true }
        let state = loggedState.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.caseInsensitiveCompare(stateCode) == .orderedSame
            || state.caseInsensitiveCompare("US-\(stateCode)") == .orderedSame
            || (!stateName.isEmpty && state.caseInsensitiveCompare(stateName) == .orderedSame)
    }
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

    static func isValidDailyWindow(start: Date, end: Date, timeZone: TimeZone = .current) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let days = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? -1
        let first = calendar.dateComponents([.hour, .minute], from: start)
        let last = calendar.dateComponents([.hour, .minute], from: end)
        let startMinute = (first.hour ?? 0) * 60 + (first.minute ?? 0)
        let endMinute = (last.hour ?? 0) * 60 + (last.minute ?? 0)
        return (0...31).contains(days) && endMinute > startMinute
    }

    static func utcWindow(start: Date, end: Date, timeZone: TimeZone = .current) -> String {
        guard isValidDailyWindow(start: start, end: end, timeZone: timeZone) else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let firstDay = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        let dayCount = calendar.dateComponents([.day], from: firstDay, to: lastDay).day! + 1
        let first = calendar.dateComponents([.hour, .minute], from: start)
        let last = calendar.dateComponents([.hour, .minute], from: end)
        guard let startHour = first.hour, let startMinute = first.minute,
              let endHour = last.hour, let endMinute = last.minute else { return "" }

        let utc = TimeZone(secondsFromGMT: 0)!
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = utc
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = utc
        timeFormatter.dateFormat = "HH:mm"
        var windows: [(start: Date, end: Date)] = []
        for offset in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                  let dayStart = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: day),
                  let dayEnd = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: day) else { continue }
            windows.append((dayStart, dayEnd))
        }
        guard let initial = windows.first, let final = windows.last else { return "" }
        let allSameClock = windows.allSatisfy {
            timeFormatter.string(from: $0.start) == timeFormatter.string(from: initial.start) &&
            timeFormatter.string(from: $0.end) == timeFormatter.string(from: initial.end) &&
            dateFormatter.string(from: $0.start) == dateFormatter.string(from: $0.end)
        }
        if allSameClock {
            let dates = dateFormatter.string(from: initial.start) == dateFormatter.string(from: final.start)
                ? "on \(dateFormatter.string(from: initial.start))"
                : "on any day from \(dateFormatter.string(from: initial.start)) through \(dateFormatter.string(from: final.start))"
            return "Could we arrange a SKED \(dates)? I'm available each day from \(timeFormatter.string(from: initial.start)) to \(timeFormatter.string(from: initial.end)) UTC."
        }
        let lines = windows.map { window in
            "\(dateFormatter.string(from: window.start)) \(timeFormatter.string(from: window.start))–\(dateFormatter.string(from: window.end)) \(timeFormatter.string(from: window.end)) UTC"
        }
        return "Could we arrange a SKED during one of these daily UTC windows?\n" + lines.joined(separator: "\n")
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
        let greeting = greetingName(name, callsign: callsign)
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
            "greeting": greeting,
            "name": name ?? callsign,
            "callsign": callsign,
            "bands": bandPhrase(bands),
            "my_callsign": stationCallsign,
            "my_call": stationCallsign,
            "my_grid": stationGrid,
            "my_qth": stationQTH,
            "my_location": location,
            "my_name": stationName,
            "time_window": timeWindowUTC ?? "I'm flexible on timing, so feel free to suggest a slot that works for you."
        ]
        let pattern = try! NSRegularExpression(pattern: #"\{([A-Za-z0-9_-]+)\}"#)
        let range = NSRange(template.startIndex..<template.endIndex, in: template)
        let matches = pattern.matches(in: template, range: range)
        var output = template
        for match in matches.reversed() {
            guard let fieldRange = Range(match.range(at: 1), in: template),
                  let wholeRange = Range(match.range, in: output),
                  let replacement = replacements[template[fieldRange].lowercased()] else { continue }
            output.replaceSubrange(wholeRange, with: replacement)
        }
        return output
    }

    static func unresolvedFields(_ template: String) -> [String] {
        let known: Set<String> = ["greeting", "name", "callsign", "bands", "my_callsign", "my_call",
                                  "my_grid", "my_qth", "my_location", "my_name", "time_window"]
        let pattern = try! NSRegularExpression(pattern: #"\{([A-Za-z0-9_-]+)\}"#)
        let matches = pattern.matches(in: template, range: NSRange(template.startIndex..<template.endIndex, in: template))
        return Array(Set(matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: template) else { return nil }
            let field = String(template[range])
            return known.contains(field.lowercased()) ? nil : field
        })).sorted()
    }

    static func greetingName(_ name: String?, callsign: String = "there") -> String {
        guard let name else { return callsign }
        let titles: Set<String> = ["dr", "mr", "mrs", "ms", "prof", "rev", "fr", "hon", "ing", "eng", "sr", "sra", "sir"]
        let suffixes: Set<String> = ["jr", "ii", "iii", "iv", "inc", "llc", "ltd"]
        var words = name.split(whereSeparator: \.isWhitespace)
        var skipped = 0
        if words.count > 1, words[0].hasSuffix(",") || words[0].hasSuffix("،") {
            words.removeFirst()
            skipped = 1
        }
        let first = words.enumerated().map { item in
            (index: item.offset + skipped, word: item.element.trimmingCharacters(in: .punctuationCharacters))
        }.first { item in
            let initial = item.word.count == 1 && item.word.unicodeScalars.allSatisfy(\.isASCII)
            let lower = item.word.lowercased()
            return !item.word.isEmpty && !initial && !titles.contains(lower)
                && !(item.index > 0 && suffixes.contains(lower))
        }?.word
        return first ?? callsign
    }

    static func safeSubject(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? Unicode.Scalar(" ") : $0
        }))
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    }
}
