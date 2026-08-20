//
//  ADIFParser.swift
//  ADIF to Excel
//
//  Created by factoreal on 7/30/26.
//

import Foundation

// MARK: - ADIF Parsing & Processing Logic

nonisolated enum UTCMinuteKey {
    static let timeZone = TimeZone(secondsFromGMT: 0)!

    static func normalized(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateInterval(of: .minute, for: date)?.start
            ?? Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 60) * 60)
    }

    static func string(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: normalized(date)
        )
        return String(
            format: "%04d%02d%02d%02d%02d00",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }
}

nonisolated struct ADIFConversionFilter: Equatable, Sendable {
    static let allBands = "All Bands"
    static let allModes = "All Modes"

    static let defaultBands = [
        "2190m", "630m", "160m", "80m", "60m", "40m", "30m", "20m", "17m",
        "15m", "12m", "10m", "6m", "4m", "2m", "1.25m", "70cm", "33cm", "23cm",
        "13cm", "9cm", "6cm", "3cm", "1.25cm"
    ]

    static let defaultModes = [
        "CW", "SSB", "USB", "LSB", "AM", "FM", "RTTY", "FT8", "FT4", "JS8",
        "PSK31", "MFSK", "DATA", "DIGI"
    ]

    var startUTCKey: String?
    var endUTCKey: String?
    var band: String?
    var mode: String?

    private static let frequencyBandRanges: [(ClosedRange<Double>, String)] = [
        (0.1357...0.1378, "2190M"), (0.472...0.479, "630M"), (1.8...2.0, "160M"),
        (3.5...4.0, "80M"), (5.0...5.5, "60M"), (7.0...7.3, "40M"),
        (10.1...10.15, "30M"), (14.0...14.35, "20M"), (18.068...18.168, "17M"),
        (21.0...21.45, "15M"), (24.89...24.99, "12M"), (28.0...29.7, "10M"),
        (50.0...54.0, "6M"), (69.9...71.0, "4M"), (144.0...148.0, "2M"),
        (219.0...225.0, "1.25M"), (420.0...450.0, "70CM"), (902.0...928.0, "33CM"),
        (1_240.0...1_300.0, "23CM"), (2_300.0...2_450.0, "13CM"),
        (3_300.0...3_500.0, "9CM"), (5_650.0...5_925.0, "6CM"),
        (10_000.0...10_500.0, "3CM"), (24_000.0...24_250.0, "1.25CM")
    ]

    var isActive: Bool {
        startUTCKey != nil || normalizedSelection(band) != nil || normalizedSelection(mode) != nil
    }

    func matches(_ record: [String: String]) -> Bool {
        if let startUTCKey, let endUTCKey {
            guard let qsoDate = record["QSO_DATE"]?.filter(\.isNumber), qsoDate.count == 8,
                  let rawTime = record["TIME_ON"], !rawTime.isEmpty else {
                return false
            }

            let recordKey = qsoDate + normalizeTime(rawTime)
            guard recordKey >= startUTCKey, recordKey < endUTCKey else { return false }
        }

        if let selectedBand = normalizedSelection(band) {
            guard Self.resolvedBand(for: record) == Self.normalizedBand(selectedBand) else { return false }
        }

        if let selectedMode = normalizedSelection(mode) {
            let target = selectedMode.uppercased()
            let recordMode = Self.normalizedMode(record["MODE"] ?? "")
            let recordSubmode = Self.normalizedMode(record["SUBMODE"] ?? "")
            guard target == recordMode || target == recordSubmode else { return false }
        }

        return true
    }

    func apply(to records: [[String: String]]) -> [[String: String]] {
        guard isActive else { return records }
        return records.filter(matches)
    }

    static func availableBands(in records: [[String: String]]) -> [String] {
        let values = Set(records.compactMap { record -> String? in
            let band = resolvedBand(for: record)
            return band.isEmpty ? nil : displayBand(band)
        })
        return values.sorted { bandSortKey($0) < bandSortKey($1) }
    }

    static func availableModes(in records: [[String: String]]) -> [String] {
        var values = Set<String>()
        for record in records {
            let mode = normalizedMode(record["MODE"] ?? "")
            let submode = normalizedMode(record["SUBMODE"] ?? "")
            if !mode.isEmpty { values.insert(mode) }
            if !submode.isEmpty { values.insert(submode) }
        }
        return values.sorted { modeSortIndex($0) < modeSortIndex($1) }
    }

    static func resolvedBand(for record: [String: String]) -> String {
        let explicit = normalizedBand(record["BAND"] ?? "")
        if !explicit.isEmpty { return explicit }
        return inferredBand(fromFrequency: record["FREQ"] ?? "") ?? ""
    }

    private func normalizedSelection(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != Self.allBands, clean != Self.allModes else { return nil }
        return clean
    }

    private static func normalizedBand(_ value: String) -> String {
        value
            .uppercased()
            .replacingOccurrences(of: "METERS", with: "M")
            .replacingOccurrences(of: "METER", with: "M")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func displayBand(_ normalized: String) -> String {
        normalized.lowercased()
    }

    private static func normalizedMode(_ value: String) -> String {
        value.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func inferredBand(fromFrequency rawValue: String) -> String? {
        let upper = rawValue.uppercased()
        let isKilohertz = upper.contains("KHZ")
        let isHertz = !isKilohertz && upper.contains("HZ") && !upper.contains("MHZ")
        let clean = rawValue
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "MHz", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "kHz", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Hz", with: "", options: .caseInsensitive)
        guard var frequency = Double(clean), frequency > 0 else { return nil }
        if isHertz { frequency /= 1_000_000 }
        else if isKilohertz { frequency /= 1_000 }
        return frequencyBandRanges.first(where: { $0.0.contains(frequency) })?.1
    }

    private static func bandSortKey(_ band: String) -> (Int, String) {
        (defaultBands.firstIndex(where: { normalizedBand($0) == normalizedBand(band) }) ?? Int.max, band)
    }

    private static func modeSortIndex(_ mode: String) -> (Int, String) {
        (defaultModes.firstIndex(of: mode) ?? Int.max, mode)
    }
}

nonisolated func parseADIF(content: String) -> (headers: [String], records: [[String: String]]) {
    var records: [[String: String]] = []
    var allKeys = Set<String>()
    
    var body = content
    if let eohRange = content.range(of: "<EOH>", options: .caseInsensitive) {
        body = String(content[eohRange.upperBound...])
    }
    
    var index = body.startIndex
    var currentRecord = [String: String]()
    
    while index < body.endIndex {
        if body[index] == "<" {
            guard let closeBracket = body[index...].firstIndex(of: ">") else { break }
            let tagContent = String(body[body.index(after: index)..<closeBracket])
            let tagUpper = tagContent.uppercased()
            
            if tagUpper == "EOR" {
                if !currentRecord.isEmpty {
                    records.append(currentRecord)
                    currentRecord = [:]
                }
                index = body.index(after: closeBracket)
                continue
            }
            
            let parts = tagContent.split(separator: ":")
            if parts.count >= 2, let len = Int(parts[1]) {
                let fieldName = String(parts[0]).uppercased()
                let valueStart = body.index(after: closeBracket)
                
                var valueEnd = valueStart
                var charsCount = 0
                while valueEnd < body.endIndex && charsCount < len {
                    valueEnd = body.index(after: valueEnd)
                    charsCount += 1
                }
                
                let value = String(body[valueStart..<valueEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                currentRecord[fieldName] = value
                allKeys.insert(fieldName)
                
                index = valueEnd
                continue
            } else {
                index = body.index(after: closeBracket)
                continue
            }
        } else {
            index = body.index(after: index)
        }
    }
    
    if !currentRecord.isEmpty {
        records.append(currentRecord)
    }
    
    let priorityHeaders = ["QSO_DATE", "TIME_ON", "CALL", "FREQ", "BAND", "MODE", "RST_SENT", "RST_RCVD", "NAME", "QTH", "COMMENT"]
    var headers: [String] = []
    
    for item in priorityHeaders {
        if allKeys.contains(item) {
            headers.append(item)
            allKeys.remove(item)
        }
    }
    headers.append(contentsOf: Array(allKeys).sorted())
    
    return (headers, records)
}

nonisolated func generateADIF(originalContent: String, records: [[String: String]]) -> String {
    var header = "Generated by ADIF Processor (Developed by EP2AES)\r\n<EOH>\r\n"
    if let eohRange = originalContent.range(of: "<EOH>", options: .caseInsensitive) {
        header = String(originalContent[..<eohRange.upperBound]) + "\r\n"
    }
    
    var body = ""
    let priorityKeys = ["QSO_DATE", "TIME_ON", "CALL", "FREQ", "BAND", "MODE", "RST_SENT", "RST_RCVD", "NAME", "QTH", "COMMENT"]
    
    for record in records {
        var recordStr = ""
        var remainingKeys = Set(record.keys)
        
        for key in priorityKeys {
            if let val = record[key], !val.isEmpty {
                recordStr += "<\(key):\(val.count)>\(val)"
                remainingKeys.remove(key)
            }
        }
        
        for key in remainingKeys.sorted() {
            if let val = record[key], !val.isEmpty {
                recordStr += "<\(key):\(val.count)>\(val)"
            }
        }
        
        recordStr += "<EOR>\r\n"
        body += recordStr
    }
    
    return header + body
}

nonisolated func generateCSV(headers: [String], records: [[String: String]]) -> String {
    var lines: [String] = []
    
    let headerRow = headers.map { escapeCSV($0) }.joined(separator: ",")
    lines.append(headerRow)
    
    for record in records {
        let row = headers.map { header in
            let val = record[header] ?? ""
            return escapeCSV(val)
        }.joined(separator: ",")
        lines.append(row)
    }
    
    return lines.joined(separator: "\r\n")
}

nonisolated func normalizeTime(_ timeStr: String) -> String {
    let digits = timeStr.filter { $0.isNumber }
    if digits.count == 4 {
        return digits + "00"
    } else if digits.count < 6 {
        return digits.padding(toLength: 6, withPad: "0", startingAt: 0)
    }
    return String(digits.prefix(6))
}

nonisolated func escapeCSV(_ field: String) -> String {
    if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
    return field
}
