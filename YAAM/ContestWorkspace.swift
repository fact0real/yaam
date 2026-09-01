//
//  ContestWorkspace.swift
//  YAAM
//
//  Advanced Amateur Radio Contest Engine, Real-Time Multiplier Scoring Matrix,
//  Super Check Partial (SCP), Rate Meter, and Official Cabrillo 3.0/2.0 Exporter.
//

import Foundation

// MARK: - Multiplier & Point Scoring Rules

public enum ContestMultiplierType: String, Codable, CaseIterable, Sendable {
    case zonesAndDXCCPerBand = "Zones & DXCC per Band"
    case prefixesTotal = "WPX Prefixes (Total)"
    case dxccPerBand = "DXCC Entities per Band"
    case statesAndDXCCPerBand = "States/Provinces & DXCC per Band"
    case ituZonesAndHQPerBand = "ITU Zones & HQ per Band"
    case oblastsAndDXCC = "Russian Oblasts & DXCC"
    case genericSerial = "Serial Numbers"
}

public enum ContestPointSystem: String, Codable, CaseIterable, Sendable {
    case cqww = "CQ WW Standard (3pt DX / 1pt Same Cont / 2pt Same Cont Diff Country)"
    case cqwpx = "CQ WPX (6pt 40/80/160 DX / 3pt High Band DX / 1pt Same Cont)"
    case arrldx = "ARRL DX (3pt per DX Contact / 0pt same country)"
    case iaru = "IARU HF (5pt Diff Zone/Cont / 3pt Same Zone Diff Cont / 1pt Same Zone/Cont)"
    case cq160 = "CQ 160m (10pt DX / 5pt Same Cont / 2pt Same Country)"
    case onePointPerQSO = "1 Point per Valid QSO"
}

// MARK: - Pre-Configured Global Contest Templates

public struct ContestTemplate: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let sponsor: String
    public let defaultExchangeHint: String
    public let defaultSentExchange: String
    public let defaultCategoryMode: String
    public let multiplierType: ContestMultiplierType
    public let pointSystem: ContestPointSystem

    public static let catalog: [ContestTemplate] = [
        ContestTemplate(
            id: "CQ-WW-SSB",
            name: "CQ World Wide DX Contest (SSB)",
            sponsor: "CQ Magazine",
            defaultExchangeHint: "CQ Zone (e.g. 21, 14, 05)",
            defaultSentExchange: "21",
            defaultCategoryMode: "SSB",
            multiplierType: .zonesAndDXCCPerBand,
            pointSystem: .cqww
        ),
        ContestTemplate(
            id: "CQ-WW-CW",
            name: "CQ World Wide DX Contest (CW)",
            sponsor: "CQ Magazine",
            defaultExchangeHint: "CQ Zone (e.g. 21, 14, 05)",
            defaultSentExchange: "21",
            defaultCategoryMode: "CW",
            multiplierType: .zonesAndDXCCPerBand,
            pointSystem: .cqww
        ),
        ContestTemplate(
            id: "CQ-WPX-SSB",
            name: "CQ World Wide WPX (SSB)",
            sponsor: "CQ Magazine",
            defaultExchangeHint: "Serial Number (e.g. 001)",
            defaultSentExchange: "001",
            defaultCategoryMode: "SSB",
            multiplierType: .prefixesTotal,
            pointSystem: .cqwpx
        ),
        ContestTemplate(
            id: "CQ-WPX-CW",
            name: "CQ World Wide WPX (CW)",
            sponsor: "CQ Magazine",
            defaultExchangeHint: "Serial Number (e.g. 001)",
            defaultSentExchange: "001",
            defaultCategoryMode: "CW",
            multiplierType: .prefixesTotal,
            pointSystem: .cqwpx
        ),
        ContestTemplate(
            id: "CQ-WPX-RTTY",
            name: "CQ World Wide WPX (RTTY)",
            sponsor: "CQ Magazine",
            defaultExchangeHint: "Serial Number (e.g. 001)",
            defaultSentExchange: "001",
            defaultCategoryMode: "RTTY",
            multiplierType: .prefixesTotal,
            pointSystem: .cqwpx
        ),
        ContestTemplate(
            id: "ARRL-DX-CW",
            name: "ARRL International DX (CW)",
            sponsor: "ARRL",
            defaultExchangeHint: "US/VE: State/Prov · DX: Power (e.g. 100, 1K)",
            defaultSentExchange: "100",
            defaultCategoryMode: "CW",
            multiplierType: .statesAndDXCCPerBand,
            pointSystem: .arrldx
        ),
        ContestTemplate(
            id: "ARRL-DX-SSB",
            name: "ARRL International DX (SSB)",
            sponsor: "ARRL",
            defaultExchangeHint: "US/VE: State/Prov · DX: Power (e.g. 100, 1K)",
            defaultSentExchange: "100",
            defaultCategoryMode: "SSB",
            multiplierType: .statesAndDXCCPerBand,
            pointSystem: .arrldx
        ),
        ContestTemplate(
            id: "IARU-HF",
            name: "IARU HF World Championship",
            sponsor: "IARU",
            defaultExchangeHint: "ITU Zone (e.g. 39) or HQ Station Code (e.g. IARU)",
            defaultSentExchange: "39",
            defaultCategoryMode: "MIXED",
            multiplierType: .ituZonesAndHQPerBand,
            pointSystem: .iaru
        ),
        ContestTemplate(
            id: "CQ-160-CW",
            name: "CQ World Wide 160-Meter (CW)",
            sponsor: "CQ Magazine",
            defaultExchangeHint: "US/VE: State/Prov · DX: CQ Zone (e.g. 21)",
            defaultSentExchange: "21",
            defaultCategoryMode: "CW",
            multiplierType: .statesAndDXCCPerBand,
            pointSystem: .cq160
        ),
        ContestTemplate(
            id: "CQ-160-SSB",
            name: "CQ World Wide 160-Meter (SSB)",
            sponsor: "CQ Magazine",
            defaultExchangeHint: "US/VE: State/Prov · DX: CQ Zone (e.g. 21)",
            defaultSentExchange: "21",
            defaultCategoryMode: "SSB",
            multiplierType: .statesAndDXCCPerBand,
            pointSystem: .cq160
        ),
        ContestTemplate(
            id: "RDXC",
            name: "Russian DX Contest (RDXC)",
            sponsor: "SRR",
            defaultExchangeHint: "Serial Number (e.g. 001) or Russian Oblast (e.g. MA)",
            defaultSentExchange: "001",
            defaultCategoryMode: "MIXED",
            multiplierType: .oblastsAndDXCC,
            pointSystem: .cqww
        ),
        ContestTemplate(
            id: "EUHFC",
            name: "European HF Championship (EUHFC)",
            sponsor: "SCC",
            defaultExchangeHint: "Two-digit year of first license (e.g. 88, 05)",
            defaultSentExchange: "12",
            defaultCategoryMode: "MIXED",
            multiplierType: .dxccPerBand,
            pointSystem: .cqww
        ),
        ContestTemplate(
            id: "ALL-ASIAN-DX-CW",
            name: "All Asian DX Contest (CW)",
            sponsor: "JARL",
            defaultExchangeHint: "Operator Age (e.g. 35, 00 for OM/YL)",
            defaultSentExchange: "35",
            defaultCategoryMode: "CW",
            multiplierType: .dxccPerBand,
            pointSystem: .cqww
        ),
        ContestTemplate(
            id: "ALL-ASIAN-DX-SSB",
            name: "All Asian DX Contest (SSB)",
            sponsor: "JARL",
            defaultExchangeHint: "Operator Age (e.g. 35, 00 for OM/YL)",
            defaultSentExchange: "35",
            defaultCategoryMode: "SSB",
            multiplierType: .dxccPerBand,
            pointSystem: .cqww
        ),
        ContestTemplate(
            id: "GENERAL-SERIAL",
            name: "General DX Contest (Serial Exchange)",
            sponsor: "Universal",
            defaultExchangeHint: "Serial Number (e.g. 001)",
            defaultSentExchange: "001",
            defaultCategoryMode: "MIXED",
            multiplierType: .genericSerial,
            pointSystem: .onePointPerQSO
        )
    ]

    public static func find(id: String) -> ContestTemplate? {
        catalog.first { $0.id.uppercased() == id.uppercased() }
    }
}

// MARK: - Contest Session Definition

public struct ContestSession: Codable, Equatable, Sendable {
    public var contestID = "CQ-WW-SSB"
    public var contestName = "CQ World Wide DX (SSB)"
    public var sentExchange = "21"
    public var operatorCallsign = ""
    public var categoryAssisted = "NON-ASSISTED"
    public var categoryBand = "ALL"
    public var categoryMode = "SSB"
    public var categoryOperator = "SINGLE-OP"
    public var categoryPower = "LOW"
    public var categoryTransmitter = "ONE"
    public var categoryOverlay = "NONE"
    public var categoryStation = "FIXED"
    public var club = ""
    public var soapbox = "Logged with YAAM - Yet Another ADIF Manager"
    public var startedAt = Date()
    public var endedAt: Date?
    public var nextSerial = 1

    public var isActive: Bool { endedAt == nil }

    public var displayName: String {
        let cleanName = contestName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanName.isEmpty ? contestID : cleanName
    }

    public mutating func normalize() {
        contestID = contestID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        contestName = contestName.trimmingCharacters(in: .whitespacesAndNewlines)
        sentExchange = sentExchange.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        operatorCallsign = operatorCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        nextSerial = max(nextSerial, 1)
    }

    public init(
        contestID: String = "CQ-WW-SSB",
        contestName: String = "CQ World Wide DX (SSB)",
        sentExchange: String = "21",
        operatorCallsign: String = ""
    ) {
        self.contestID = contestID
        self.contestName = contestName
        self.sentExchange = sentExchange
        self.operatorCallsign = operatorCallsign
    }
}

// MARK: - Live Band Score Breakdown Struct

public struct ContestBandScore: Identifiable, Equatable, Sendable {
    public var id: String { band }
    public let band: String
    public let qsoCount: Int
    public let dupeCount: Int
    public let points: Int
    public let multipliers: Int
    public let multDetail: String
}

// MARK: - Contest Summary & Claimed Score

public struct ContestSummary: Equatable, Sendable {
    public var qsoCount = 0
    public var uniqueCallsigns = 0
    public var uniqueDXCC = 0
    public var uniqueBands = 0
    public var duplicateCount = 0
    public var totalPoints = 0
    public var totalMultipliers = 0
    public var claimedScore = 0
    public var bandBreakdown: [ContestBandScore] = []
    public var rateLast10Min: Double = 0.0
    public var rateLast60Min: Double = 0.0
    public var lastQSOAt: Date?

    public init(
        qsoCount: Int = 0,
        uniqueCallsigns: Int = 0,
        uniqueDXCC: Int = 0,
        uniqueBands: Int = 0,
        duplicateCount: Int = 0,
        totalPoints: Int = 0,
        totalMultipliers: Int = 0,
        claimedScore: Int = 0,
        bandBreakdown: [ContestBandScore] = [],
        rateLast10Min: Double = 0.0,
        rateLast60Min: Double = 0.0,
        lastQSOAt: Date? = nil
    ) {
        self.qsoCount = qsoCount
        self.uniqueCallsigns = uniqueCallsigns
        self.uniqueDXCC = uniqueDXCC
        self.uniqueBands = uniqueBands
        self.duplicateCount = duplicateCount
        self.totalPoints = totalPoints
        self.totalMultipliers = totalMultipliers
        self.claimedScore = claimedScore
        self.bandBreakdown = bandBreakdown
        self.rateLast10Min = rateLast10Min
        self.rateLast60Min = rateLast60Min
        self.lastQSOAt = lastQSOAt
    }
}

// MARK: - Real-Time Scoring & Multiplier Engine

public enum ContestWorkspaceLogic {
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
        let template = ContestTemplate.find(id: session.contestID)
        let homeContinent = "AS" // Default station continent (Asia / Iran)

        var seenKeys: Set<String> = []
        var validRecords: [QSORecordModel] = []
        var duplicateCount = 0

        // Process in chronological order for scoring
        for record in contestRecords.reversed() {
            let key = [record["CALL"], record["BAND"], normalizedContestMode(record)].joined(separator: "|").uppercased()
            if seenKeys.insert(key).inserted {
                validRecords.append(record)
            } else {
                duplicateCount += 1
            }
        }

        // Standard Contest Bands
        let contestBands = ["160M", "80M", "40M", "20M", "15M", "10M", "6M"]
        var bandScores: [ContestBandScore] = []
        var globalUniquePrefixes: Set<String> = []
        var totalPoints = 0
        var totalMults = 0

        for bandName in contestBands {
            let bandRecords = validRecords.filter { $0["BAND"].uppercased() == bandName }
            let bandDupes = contestRecords.filter { $0["BAND"].uppercased() == bandName }.count - bandRecords.count

            if bandRecords.isEmpty && bandDupes == 0 { continue }

            var bandPoints = 0
            var bandZones: Set<String> = []
            var bandDXCC: Set<String> = []
            var bandStates: Set<String> = []

            for record in bandRecords {
                // 1. Calculate points
                let pts = calculateQSOPoints(record: record, pointSystem: template?.pointSystem ?? .cqww, homeContinent: homeContinent)
                bandPoints += pts

                // 2. Accumulate multipliers
                let cqz = record["CQZ"].trimmingCharacters(in: .whitespacesAndNewlines)
                if !cqz.isEmpty { bandZones.insert(cqz) }

                let dxcc = record["DXCC"].trimmingCharacters(in: .whitespacesAndNewlines)
                if !dxcc.isEmpty { bandDXCC.insert(dxcc) }

                let state = (record["STATE"].isEmpty ? record["SRX_STRING"] : record["STATE"]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if state.count == 2 { bandStates.insert(state) }

                let prefix = extractWPXPrefix(call: record["CALL"])
                if !prefix.isEmpty { globalUniquePrefixes.insert(prefix) }
            }

            // Multiplier tally for this band
            let bandMultCount: Int
            let multDetail: String

            switch template?.multiplierType ?? .zonesAndDXCCPerBand {
            case .zonesAndDXCCPerBand:
                bandMultCount = bandZones.count + bandDXCC.count
                multDetail = "\(bandZones.count)Z / \(bandDXCC.count)C"
            case .prefixesTotal:
                bandMultCount = 0 // Calculated globally in WPX
                multDetail = "\(bandRecords.count) QSOs"
            case .statesAndDXCCPerBand:
                bandMultCount = bandStates.count + bandDXCC.count
                multDetail = "\(bandStates.count)S / \(bandDXCC.count)C"
            case .ituZonesAndHQPerBand:
                bandMultCount = bandZones.count + bandDXCC.count
                multDetail = "\(bandZones.count)Z / \(bandDXCC.count)HQ"
            case .oblastsAndDXCC:
                bandMultCount = bandStates.count + bandDXCC.count
                multDetail = "\(bandStates.count)Obl / \(bandDXCC.count)C"
            case .dxccPerBand:
                bandMultCount = bandDXCC.count
                multDetail = "\(bandDXCC.count) DXCC"
            case .genericSerial:
                bandMultCount = bandRecords.count > 0 ? 1 : 0
                multDetail = "\(bandRecords.count) Serials"
            }

            totalPoints += bandPoints
            totalMults += bandMultCount

            bandScores.append(ContestBandScore(
                band: bandName,
                qsoCount: bandRecords.count,
                dupeCount: max(0, bandDupes),
                points: bandPoints,
                multipliers: bandMultCount,
                multDetail: multDetail
            ))
        }

        // Global Multipliers override for WPX
        if template?.multiplierType == .prefixesTotal {
            totalMults = globalUniquePrefixes.count
        }

        let claimedScore = totalPoints * max(1, totalMults)

        // Rate Calculations (Last 10 min & Last 60 min)
        let now = Date()
        let last10MinCount = contestRecords.filter {
            guard let d = qsoDate($0) else { return false }
            return now.timeIntervalSince(d) <= 600
        }.count
        let last60MinCount = contestRecords.filter {
            guard let d = qsoDate($0) else { return false }
            return now.timeIntervalSince(d) <= 3600
        }.count

        let rate10 = Double(last10MinCount) * 6.0
        let rate60 = Double(last60MinCount)

        return ContestSummary(
            qsoCount: validRecords.count,
            uniqueCallsigns: Set(validRecords.map { $0["CALL"].uppercased() }.filter { !$0.isEmpty }).count,
            uniqueDXCC: Set(validRecords.map { $0["DXCC"] }.filter { !$0.isEmpty }).count,
            uniqueBands: Set(validRecords.map { $0["BAND"].lowercased() }.filter { !$0.isEmpty }).count,
            duplicateCount: duplicateCount,
            totalPoints: totalPoints,
            totalMultipliers: totalMults,
            claimedScore: claimedScore,
            bandBreakdown: bandScores,
            rateLast10Min: rate10,
            rateLast60Min: rate60,
            lastQSOAt: contestRecords.compactMap { qsoDate($0) }.max()
        )
    }

    static func isDuplicate(callsign: String, band: String, mode: String, session: ContestSession, records: [QSORecordModel]) -> Bool {
        let call = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let b = band.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let m = normalizedContestMode(mode)
        guard !call.isEmpty else { return false }
        return self.records(in: session, from: records).contains {
            $0["CALL"].uppercased() == call &&
            $0["BAND"].lowercased() == b &&
            normalizedContestMode($0) == m
        }
    }

    static func nextSerial(in session: ContestSession, records: [QSORecordModel]) -> Int {
        let highest = self.records(in: session, from: records)
            .compactMap { Int($0["STX"].filter(\.isNumber)) }
            .max() ?? 0
        return max(session.nextSerial, highest + 1)
    }

    public static func extractWPXPrefix(call: String) -> String {
        let clean = call.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return "" }

        // Strip portable suffixes/prefixes e.g. W6/EP2AES or EP2AES/P
        let parts = clean.split(separator: "/")
        let mainPart = parts.max { $0.count < $1.count }.map(String.init) ?? clean

        // Case A: Starts with a digit (e.g. 4X4DX, 3V8BB, 9A1AA, 7X2ARA)
        if let firstChar = mainPart.first, firstChar.isNumber {
            // Find the SECOND digit sequence
            var seenLetter = false
            var prefixChars: [Character] = []
            for ch in mainPart {
                if ch.isNumber {
                    prefixChars.append(ch)
                    if seenLetter {
                        // Found digit after letter
                        break
                    }
                } else if ch.isLetter {
                    seenLetter = true
                    prefixChars.append(ch)
                }
            }
            return String(prefixChars)
        }

        // Case B: Starts with letters (e.g. DL1AAA, HG2000DX, EP2AES)
        if let digitIdx = mainPart.firstIndex(where: \.isNumber) {
            var lastDigitIdx = digitIdx
            var curr = mainPart.index(after: digitIdx)
            while curr < mainPart.endIndex && mainPart[curr].isNumber {
                lastDigitIdx = curr
                curr = mainPart.index(after: curr)
            }
            return String(mainPart[...lastDigitIdx])
        }

        // Default prefix fallback
        return String(mainPart.prefix(3))
    }

    private static func calculateQSOPoints(record: QSORecordModel, pointSystem: ContestPointSystem, homeContinent: String) -> Int {
        let contactCont = record["CONT"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isSameContinent = contactCont.isEmpty ? false : (contactCont == homeContinent)
        let band = record["BAND"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        switch pointSystem {
        case .cqww:
            if isSameContinent { return 1 }
            return 3 // Different continent

        case .cqwpx:
            if band == "160M" || band == "80M" || band == "40M" {
                return isSameContinent ? 2 : 6
            }
            return isSameContinent ? 1 : 3

        case .arrldx:
            return 3

        case .iaru:
            if isSameContinent { return 1 }
            return 5

        case .cq160:
            if isSameContinent { return 5 }
            return 10

        case .onePointPerQSO:
            return 1
        }
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

    nonisolated private static func qsoDate(_ record: QSORecordModel) -> Date? {
        ContestDateParser.date(record)
    }
}

// MARK: - Super Check Partial (SCP) Callsign Search

public enum SuperCheckPartial {
    private static let knownContestPrefixes = [
        "EP2", "DL1", "DL2", "DL3", "DL4", "DL5", "DL6", "DL7", "DL8", "DL9", "DK1", "DK2", "DK3",
        "JA1", "JA2", "JA3", "JA7", "JH1", "JR1", "JE1", "JM1", "JN1", "K1", "K2", "K3", "N1", "N2",
        "W1", "W2", "W3", "W4", "W5", "W6", "VE3", "VE7", "G3", "G4", "M0", "F5", "F6", "I2", "IK2",
        "EA1", "EA2", "EA3", "EA4", "EA5", "EA7", "SP1", "SP2", "SP5", "SP9", "UA1", "UA3", "UA9",
        "R3", "RA3", "RK3", "RN3", "RV3", "RW3", "RZ3", "LZ1", "LZ2", "YO3", "YO4", "SV1", "SV2",
        "OH1", "OH2", "SM5", "SM6", "OE1", "OE3", "HB9", "OK1", "OK2", "OM3", "OM5", "HA5", "HA8",
        "ZS1", "ZS6", "PY2", "PY5", "LU1", "LU7", "VK2", "VK3", "VK4", "ZL1", "ZL2", "BY1", "BA4"
    ]

    static func match(query: String, recentContestRecords: [QSORecordModel]) -> [String] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 2 else { return [] }

        var results: [String] = []

        // 1. Check active contest log callsigns
        for r in recentContestRecords {
            let call = r["CALL"].uppercased()
            if call.contains(clean) && !results.contains(call) {
                results.append(call)
            }
        }

        // 2. Check known prefixes
        for pfx in knownContestPrefixes {
            if pfx.starts(with: clean) || clean.starts(with: pfx) {
                let candidate = pfx + "DX"
                if !results.contains(candidate) {
                    results.append(candidate)
                }
            }
        }

        return Array(results.prefix(8))
    }
}

// MARK: - Pre-Flight Robot Validation & Cabrillo Exporter

public struct CabrilloValidationIssue: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public let severity: Severity
    public let message: String
    public let qsoCall: String?

    public enum Severity: String, Sendable {
        case error = "Error (Robot Rejection Risk)"
        case warning = "Warning (Informational)"
    }
}

public enum CabrilloPreFlightValidator {
    static func validate(session: ContestSession, station: StationProfile?, records: [QSORecordModel]) -> [CabrilloValidationIssue] {
        var issues: [CabrilloValidationIssue] = []
        let contestRecords = ContestWorkspaceLogic.records(in: session, from: records)

        // 1. Header validations
        if session.contestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(CabrilloValidationIssue(severity: .error, message: "CONTEST ID tag is missing.", qsoCall: nil))
        }

        let call = station?.normalizedCallsign.isEmpty == false ? station!.normalizedCallsign : session.operatorCallsign
        if call.isEmpty {
            issues.append(CabrilloValidationIssue(severity: .error, message: "CALLSIGN tag is missing.", qsoCall: nil))
        }

        if contestRecords.isEmpty {
            issues.append(CabrilloValidationIssue(severity: .warning, message: "No contest QSO records found for this session.", qsoCall: nil))
        }

        // 2. QSO record validations
        for record in contestRecords {
            let contactCall = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines)
            if contactCall.isEmpty {
                issues.append(CabrilloValidationIssue(severity: .error, message: "Empty callsign in contest log.", qsoCall: contactCall))
            }

            let rcvd = record["SRX_STRING"].isEmpty ? record["SRX"] : record["SRX_STRING"]
            if rcvd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(CabrilloValidationIssue(severity: .error, message: "Missing Received Exchange (Zone/Serial/State) for \(contactCall).", qsoCall: contactCall))
            }

            if record["FREQ"].isEmpty || record["FREQ"] == "0" {
                issues.append(CabrilloValidationIssue(severity: .warning, message: "Frequency is zero for contact \(contactCall). Band default will be used.", qsoCall: contactCall))
            }
        }

        return issues
    }
}

// MARK: - Official Cabrillo 3.0 / 2.0 Exporter

public enum CabrilloExporter {
    static func generate(
        session: ContestSession,
        station: StationProfile?,
        records: [QSORecordModel],
        createdBy: String
    ) -> String {
        let contestRecords = ContestWorkspaceLogic.records(in: session, from: records).reversed()
        let summary = ContestWorkspaceLogic.summary(in: session, records: records)
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
            "CATEGORY-STATION: \(session.categoryStation)",
            "CATEGORY-TRANSMITTER: \(session.categoryTransmitter)",
            "CATEGORY-OVERLAY: \(session.categoryOverlay)",
            "CLAIMED-SCORE: \(summary.claimedScore)",
            "OPERATORS: \(session.operatorCallsign.isEmpty ? callsign : session.operatorCallsign)"
        ]

        if !session.club.isEmpty {
            lines.append("CLUB: \(session.club)")
        }

        if let station {
            if !station.name.isEmpty { lines.append("NAME: \(station.name)") }
            if !station.qth.isEmpty { lines.append("ADDRESS: \(station.qth)") }
            if !station.country.isEmpty { lines.append("ADDRESS-COUNTRY: \(station.country)") }
        }

        if !session.soapbox.isEmpty {
            lines.append("SOAPBOX: \(session.soapbox)")
        }

        for record in contestRecords {
            guard let date = ContestDateParser.date(record) else { continue }
            let frequency = cabrilloFrequency(record)
            let mode = cabrilloMode(record)
            let datePart = ContestDateParser.dayFormatter.string(from: date)
            let timePart = ContestDateParser.timeFormatter.string(from: date)
            let sentRST = record["RST_SENT"].isEmpty ? "59" : record["RST_SENT"]
            let rcvdRST = record["RST_RCVD"].isEmpty ? "59" : record["RST_RCVD"]
            let sentExchange = combinedExchange(number: record["STX"], text: record["STX_STRING"], fallback: session.sentExchange)
            let receivedExchange = combinedExchange(number: record["SRX"], text: record["SRX_STRING"], fallback: "")

            let line = [
                "QSO:", pad(frequency, to: 5, rightAligned: true), pad(mode, to: 2), datePart, timePart,
                pad(callsign, to: 13), pad(sentRST, to: 3), pad(sentExchange, to: 10),
                pad(record["CALL"], to: 13), pad(rcvdRST, to: 3), pad(receivedExchange, to: 10), "0"
            ].joined(separator: " ")
            lines.append(line)
        }

        lines.append("END-OF-LOG:")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func cabrilloFrequency(_ record: QSORecordModel) -> String {
        guard let mhz = AmateurBandPlan.normalizedMHz(record["FREQ"]) else {
            // Fallback frequency by band
            let band = record["BAND"].uppercased()
            switch band {
            case "160M": return "1850"
            case "80M": return "3550"
            case "40M": return "7050"
            case "20M": return "14050"
            case "15M": return "21050"
            case "10M": return "28050"
            case "6M": return "50050"
            default: return "14000"
            }
        }
        if mhz >= 1_000 {
            let ghz = mhz / 1_000
            if ghz >= 10 { return "\(Int(ghz.rounded()))G" }
            return String(format: "%.1fG", ghz)
        }
        return String(Int((mhz * 1_000).rounded()))
    }

    private static func combinedExchange(number: String, text: String, fallback: String) -> String {
        let number = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !number.isEmpty && !text.isEmpty && number != text {
            return "\(number) \(text)"
        }
        if !number.isEmpty { return number }
        if !text.isEmpty { return text }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cabrilloMode(_ record: QSORecordModel) -> String {
        let mode = (record["SUBMODE"].isEmpty ? record["MODE"] : record["SUBMODE"]).uppercased()
        switch mode {
        case "SSB", "USB", "LSB", "PHONE": return "PH"
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

// MARK: - Contest Date Parser

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
