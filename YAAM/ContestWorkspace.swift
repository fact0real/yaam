//
//  ContestWorkspace.swift
//  YAAM
//

import Foundation

nonisolated struct ContestSession: Codable, Equatable, Sendable {
    var contestID = ""
    var contestName = ""
    var sentExchange = ""
    var operatorCallsign = ""
    var categoryAssisted = "NON-ASSISTED"
    var categoryBand = "ALL"
    var categoryMode = "MIXED"
    var categoryOperator = "SINGLE-OP"
    var categoryPower = "LOW"
    var startedAt = Date()
    var endedAt: Date?
    var nextSerial = 1

    var isActive: Bool { endedAt == nil }

    var displayName: String {
        let cleanName = contestName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanName.isEmpty ? contestID : cleanName
    }

    mutating func normalize() {
        contestID = contestID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        contestName = contestName.trimmingCharacters(in: .whitespacesAndNewlines)
        sentExchange = sentExchange.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        operatorCallsign = operatorCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        nextSerial = max(nextSerial, 1)
    }
}

nonisolated struct ContestSummary: Equatable, Sendable {
    var qsoCount = 0
    var uniqueCallsigns = 0
    var uniqueDXCC = 0
    var uniqueBands = 0
    var duplicateCount = 0
    var lastQSOAt: Date?
}

nonisolated enum ContestWorkspaceLogic {
    static func records(in session: ContestSession, from records: [QSORecordModel]) -> [QSORecordModel] {
        let contestID = session.contestID.uppercased()
        return records.filter { record in
            let recordContest = record["CONTEST_ID"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard recordContest == contestID else { return false }
            guard let date = qsoDate(record) else { return true }
            if date < session.startedAt { return false }
            if let endedAt = session.endedAt, date > endedAt { return false }
            return true
        }
        .sorted { (qsoDate($0) ?? .distantPast) > (qsoDate($1) ?? .distantPast) }
    }

    static func summary(in session: ContestSession, records: [QSORecordModel]) -> ContestSummary {
        let contestRecords = self.records(in: session, from: records)
        var seen: Set<String> = []
        var duplicates = 0
        for record in contestRecords {
            let key = [record["CALL"], record["BAND"], normalizedContestMode(record)].joined(separator: "|").uppercased()
            if !seen.insert(key).inserted { duplicates += 1 }
        }
        return ContestSummary(
            qsoCount: contestRecords.count,
            uniqueCallsigns: Set(contestRecords.map { $0["CALL"].uppercased() }.filter { !$0.isEmpty }).count,
            uniqueDXCC: Set(contestRecords.map { $0["DXCC"] }.filter { !$0.isEmpty }).count,
            uniqueBands: Set(contestRecords.map { $0["BAND"].lowercased() }.filter { !$0.isEmpty }).count,
            duplicateCount: duplicates,
            lastQSOAt: contestRecords.compactMap(qsoDate).max()
        )
    }

    static func isDuplicate(callsign: String, band: String, mode: String, session: ContestSession, records: [QSORecordModel]) -> Bool {
        let call = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let band = band.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mode = normalizedContestMode(mode)
        guard !call.isEmpty else { return false }
        return self.records(in: session, from: records).contains {
            $0["CALL"].uppercased() == call &&
                $0["BAND"].lowercased() == band &&
                normalizedContestMode($0) == mode
        }
    }

    static func nextSerial(in session: ContestSession, records: [QSORecordModel]) -> Int {
        let highest = self.records(in: session, from: records)
            .compactMap { Int($0["STX"].filter(\.isNumber)) }
            .max() ?? 0
        return max(session.nextSerial, highest + 1)
    }

    private static func normalizedContestMode(_ record: QSORecordModel) -> String {
        normalizedContestMode(record["SUBMODE"].isEmpty ? record["MODE"] : record["SUBMODE"])
    }

    private static func normalizedContestMode(_ rawMode: String) -> String {
        let mode = rawMode.uppercased()
        if mode == "SSB" || mode == "USB" || mode == "LSB" { return "PH" }
        if mode == "RTTY" { return "RY" }
        if ["FT8", "FT4", "DIGI", "DATA", "MFSK", "PSK31", "JT65"].contains(mode) { return "DG" }
        return mode
    }

    private static func qsoDate(_ record: QSORecordModel) -> Date? {
        ContestDateParser.date(record)
    }
}

nonisolated enum CabrilloExporter {
    static func generate(
        session: ContestSession,
        station: StationProfile?,
        records: [QSORecordModel],
        createdBy: String
    ) -> String {
        let contestRecords = ContestWorkspaceLogic.records(in: session, from: records).reversed()
        let callsign = station?.normalizedCallsign.isEmpty == false ? station!.normalizedCallsign : session.operatorCallsign
        var lines = [
            "START-OF-LOG: 3.0",
            "CREATED-BY: \(createdBy)",
            "CALLSIGN: \(callsign)",
            "CONTEST: \(session.contestID)",
            "CATEGORY-ASSISTED: \(session.categoryAssisted)",
            "CATEGORY-BAND: \(session.categoryBand)",
            "CATEGORY-MODE: \(session.categoryMode)",
            "CATEGORY-OPERATOR: \(session.categoryOperator)",
            "CATEGORY-POWER: \(session.categoryPower)",
            "CLAIMED-SCORE: 0",
            "OPERATORS: @\(session.operatorCallsign.isEmpty ? callsign : session.operatorCallsign)"
        ]

        if let station {
            if !station.name.isEmpty { lines.append("NAME: \(station.name)") }
            if !station.qth.isEmpty { lines.append("ADDRESS: \(station.qth)") }
            if !station.country.isEmpty { lines.append("ADDRESS-COUNTRY: \(station.country)") }
        }

        for record in contestRecords {
            guard let date = ContestDateParser.date(record) else { continue }
            let frequency = cabrilloFrequency(record)
            let mode = cabrilloMode(record)
            let datePart = ContestDateParser.dayFormatter.string(from: date)
            let timePart = ContestDateParser.timeFormatter.string(from: date)
            let sentExchange = combinedExchange(number: record["STX"], text: record["STX_STRING"])
            let receivedExchange = combinedExchange(number: record["SRX"], text: record["SRX_STRING"])
            let line = [
                "QSO:", pad(frequency, to: 5, rightAligned: true), pad(mode, to: 2), datePart, timePart,
                pad(callsign, to: 13), pad(record["RST_SENT"], to: 3), pad(sentExchange, to: 10),
                pad(record["CALL"], to: 13), pad(record["RST_RCVD"], to: 3), pad(receivedExchange, to: 10), "0"
            ].joined(separator: " ")
            lines.append(line)
        }
        lines.append("END-OF-LOG:")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func cabrilloFrequency(_ record: QSORecordModel) -> String {
        guard let mhz = AmateurBandPlan.normalizedMHz(record["FREQ"]) else { return "0" }
        if mhz >= 1_000 {
            let ghz = mhz / 1_000
            if ghz >= 10 { return "\(Int(ghz.rounded()))G" }
            return String(format: "%.1fG", ghz)
        }
        return String(Int((mhz * 1_000).rounded()))
    }

    private static func combinedExchange(number: String, text: String) -> String {
        let number = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if number.isEmpty { return text }
        if text.isEmpty || text == number { return number }
        return "\(number) \(text)"
    }

    private static func cabrilloMode(_ record: QSORecordModel) -> String {
        let mode = (record["SUBMODE"].isEmpty ? record["MODE"] : record["SUBMODE"]).uppercased()
        switch mode {
        case "SSB", "USB", "LSB": return "PH"
        case "RTTY": return "RY"
        case "FM": return "FM"
        case "CW": return "CW"
        default: return "DG"
        }
    }

    private static func pad(_ value: String, to length: Int, rightAligned: Bool = false) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(clean.prefix(length))
        let padding = String(repeating: " ", count: max(length - clipped.count, 0))
        return rightAligned ? padding + clipped : clipped + padding
    }
}

nonisolated private enum ContestDateParser {
    static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HHmm"
        return formatter
    }()

    static func date(_ record: QSORecordModel) -> Date? {
        let date = record["QSO_DATE"].filter(\.isNumber)
        var time = record["TIME_ON"].filter(\.isNumber)
        while time.count < 6 { time.append("0") }
        guard date.count == 8 else { return nil }
        return parser.date(from: date + String(time.prefix(6)))
    }
}
