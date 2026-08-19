//
//  OperatorModels.swift
//  YAAM
//

import Foundation

nonisolated enum AmateurBandPlan {
    private static let ranges: [(ClosedRange<Double>, String)] = [
        (0.1357...0.1378, "2190m"),
        (0.472...0.479, "630m"),
        (1.8...2.0, "160m"),
        (3.5...4.0, "80m"),
        (5.0...5.5, "60m"),
        (7.0...7.3, "40m"),
        (10.1...10.15, "30m"),
        (14.0...14.35, "20m"),
        (18.068...18.168, "17m"),
        (21.0...21.45, "15m"),
        (24.89...24.99, "12m"),
        (28.0...29.7, "10m"),
        (50.0...54.0, "6m"),
        (69.9...71.0, "4m"),
        (144.0...148.0, "2m"),
        (219.0...225.0, "1.25m"),
        (420.0...450.0, "70cm"),
        (902.0...928.0, "33cm"),
        (1_240.0...1_300.0, "23cm"),
        (2_300.0...2_450.0, "13cm"),
        (3_300.0...3_500.0, "9cm"),
        (5_650.0...5_925.0, "6cm"),
        (10_000.0...10_500.0, "3cm"),
        (24_000.0...24_250.0, "1.25cm")
    ]

    static let commonBands = [
        "2190m", "630m", "160m", "80m", "60m", "40m", "30m", "20m", "17m",
        "15m", "12m", "10m", "6m", "4m", "2m", "1.25m", "70cm", "33cm", "23cm"
    ]

    static func normalizedMHz(_ rawValue: String) -> Double? {
        let clean = rawValue
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "MHz", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "kHz", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Hz", with: "", options: .caseInsensitive)
        guard let value = Double(clean), value > 0 else { return nil }

        if value >= 1_000_000 { return value / 1_000_000 }
        if value >= 1_000 { return value / 1_000 }
        return value
    }

    static func band(forMHz frequency: Double) -> String? {
        ranges.first(where: { $0.0.contains(frequency) })?.1
    }

    static func band(for rawValue: String) -> String? {
        normalizedMHz(rawValue).flatMap(band(forMHz:))
    }

    static func formattedMHz(_ frequency: Double) -> String {
        var value = String(format: "%.6f", frequency)
        while value.last == "0" { value.removeLast() }
        if value.last == "." { value.removeLast() }
        return value
    }

    static func inferredMode(frequencyMHz: Double, comment: String = "") -> String {
        let upper = comment.uppercased()
        let knownModes = ["FT8", "FT4", "RTTY", "PSK31", "JS8", "CW", "SSB", "FM", "AM"]
        if let explicit = knownModes.first(where: { upper.contains($0) }) {
            switch explicit {
            case "FT8", "FT4", "JS8", "PSK31": return "DIGI"
            default: return explicit
            }
        }

        let fractionalKHz = (frequencyMHz * 1_000).truncatingRemainder(dividingBy: 1_000)
        if frequencyMHz >= 144, fractionalKHz >= 300 { return "FM" }
        if frequencyMHz < 30, fractionalKHz < 100 { return "CW" }
        return "SSB"
    }

    static func submode(from comment: String) -> String {
        let upper = comment.uppercased()
        return ["FT8", "FT4", "JS8", "PSK31"].first(where: { upper.contains($0) }) ?? ""
    }

    static func defaultRST(for mode: String) -> String {
        switch mode.uppercased() {
        case "CW", "RTTY": return "599"
        case "DIGI", "DATA", "MFSK": return "-10"
        default: return "59"
        }
    }
}

nonisolated struct QuickLogDraft: Equatable, Sendable {
    var callsign = ""
    var frequencyMHz = ""
    var band = "20m"
    var mode = "SSB"
    var submode = ""
    var startedAt = Date()
    var rstSent = "59"
    var rstReceived = "59"
    var name = ""
    var qth = ""
    var grid = ""
    var country = ""
    var dxcc = ""
    var cqZone = ""
    var ituZone = ""
    var receivedExchange = ""
    var comment = ""
    var source = "Manual"
    var portableRole = PortableOperatingRole.none
    var myPOTAReference = ""
    var contactedPOTAReference = ""
    var mySOTAReference = ""
    var contactedSOTAReference = ""
    var myIOTAReference = ""
    var contactedIOTAReference = ""
    var myVUCCGrids = ""
    var contactedVUCCGrids = ""

    var normalizedCallsign: String {
        callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    mutating func applyFrequency(_ value: String) {
        frequencyMHz = value
        if let detectedBand = AmateurBandPlan.band(for: value) {
            band = detectedBand
        }
    }

    mutating func applyMode(_ value: String) {
        mode = value.uppercased()
        rstSent = AmateurBandPlan.defaultRST(for: mode)
        rstReceived = AmateurBandPlan.defaultRST(for: mode)
    }

    mutating func resetForNextQSO(keepingOperatingContext: Bool = true) {
        let frequency = frequencyMHz
        let currentBand = band
        let currentMode = mode
        let currentSubmode = submode
        let role = portableRole
        let myPOTA = myPOTAReference
        let mySOTA = mySOTAReference
        let myIOTA = myIOTAReference
        let myVUCC = myVUCCGrids
        self = QuickLogDraft()
        if keepingOperatingContext {
            frequencyMHz = frequency
            band = currentBand
            mode = currentMode
            submode = currentSubmode
            rstSent = AmateurBandPlan.defaultRST(for: currentMode)
            rstReceived = AmateurBandPlan.defaultRST(for: currentMode)
            portableRole = role
            myPOTAReference = myPOTA
            mySOTAReference = mySOTA
            myIOTAReference = myIOTA
            myVUCCGrids = myVUCC
        }
    }
}

nonisolated struct CallsignLookupResult: Equatable, Sendable {
    var callsign: String
    var name: String = ""
    var qth: String = ""
    var grid: String = ""
    var country: String = ""
    var dxcc: String = ""
    var cqZone: String = ""
    var ituZone: String = ""
    var email: String = ""
    var latitude: String = ""
    var longitude: String = ""
    var sources: [String] = []
    var message: String = ""

    var hasUsefulData: Bool {
        !name.isEmpty || !qth.isEmpty || !grid.isEmpty || !country.isEmpty || !dxcc.isEmpty
    }

    mutating func mergeMissing(from other: CallsignLookupResult) {
        if name.isEmpty { name = other.name }
        if qth.isEmpty { qth = other.qth }
        if grid.isEmpty { grid = other.grid }
        if country.isEmpty { country = other.country }
        if dxcc.isEmpty { dxcc = other.dxcc }
        if cqZone.isEmpty { cqZone = other.cqZone }
        if ituZone.isEmpty { ituZone = other.ituZone }
        if email.isEmpty { email = other.email }
        if latitude.isEmpty { latitude = other.latitude }
        if longitude.isEmpty { longitude = other.longitude }
        sources = Array(Set(sources + other.sources)).sorted()
        if message.isEmpty { message = other.message }
    }
}

nonisolated struct CallsignLookupCredentials: Sendable {
    var qrzUsername: String
    var qrzPassword: String
    var hamqthUsername: String
    var hamqthPassword: String
    var agent: String
}

nonisolated struct QuickLogAssessment: Equatable, Sendable {
    var totalWorked = 0
    var confirmed = 0
    var sameBand = 0
    var sameBandMode = 0
    var recentDuplicateCount = 0
    var contestDuplicate = false
    var lastWorkedAt: Date?

    var hasRecentDuplicate: Bool { recentDuplicateCount > 0 }
    var isNewCallsign: Bool { totalWorked == 0 }
}

nonisolated enum QuickLogValidationError: LocalizedError, Equatable {
    case noActiveStation
    case invalidCallsign
    case invalidFrequency
    case missingBand
    case missingMode
    case exactDuplicate

    var errorDescription: String? {
        switch self {
        case .noActiveStation: return "Select an active station profile before logging a QSO."
        case .invalidCallsign: return "Enter a valid amateur-radio callsign."
        case .invalidFrequency: return "Frequency must be a positive value in MHz, kHz, or Hz."
        case .missingBand: return "Select a band or enter a frequency that maps to a band."
        case .missingMode: return "Select an operating mode."
        case .exactDuplicate: return "This exact QSO is already present in the active station log."
        }
    }
}

nonisolated enum DXSpotNeedStatus: Int, CaseIterable, Identifiable, Sendable {
    case newCallsign
    case newBand
    case worked
    case confirmed

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .newCallsign: return "New callsign"
        case .newBand: return "New band"
        case .worked: return "Worked"
        case .confirmed: return "Confirmed"
        }
    }
}

nonisolated struct CallsignWorkSummary: Equatable, Sendable {
    var total = 0
    var confirmed = 0
    var workedBands: Set<String> = []
    var confirmedBands: Set<String> = []
}

nonisolated struct LogWorkIndex: Equatable, Sendable {
    private var callsigns: [String: CallsignWorkSummary]

    init(records: [[String: String]]) {
        var index: [String: CallsignWorkSummary] = [:]
        for record in records {
            let call = (record["CALL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !call.isEmpty else { continue }
            let band = (record["BAND"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let confirmed = Self.isConfirmed(record)
            var summary = index[call] ?? CallsignWorkSummary()
            summary.total += 1
            if !band.isEmpty { summary.workedBands.insert(band) }
            if confirmed {
                summary.confirmed += 1
                if !band.isEmpty { summary.confirmedBands.insert(band) }
            }
            index[call] = summary
        }
        callsigns = index
    }

    func summary(for callsign: String) -> CallsignWorkSummary {
        callsigns[callsign.uppercased()] ?? CallsignWorkSummary()
    }

    func status(for callsign: String, band: String) -> DXSpotNeedStatus {
        let summary = summary(for: callsign)
        let normalizedBand = band.lowercased()
        if summary.total == 0 { return .newCallsign }
        if !normalizedBand.isEmpty, !summary.workedBands.contains(normalizedBand) { return .newBand }
        if !normalizedBand.isEmpty, summary.confirmedBands.contains(normalizedBand) { return .confirmed }
        if summary.confirmed > 0, normalizedBand.isEmpty { return .confirmed }
        return .worked
    }

    private static func isConfirmed(_ record: [String: String]) -> Bool {
        let values = ["LOTW_QSL_RCVD", "QRZLOG_QSL_RCVD", "QSL_RCVD", "EQSL_QSL_RCVD"]
            .map { (record[$0] ?? "").uppercased() }
        return values.contains(where: { ["Y", "V", "C", "CONFIRMED"].contains($0) })
    }
}

nonisolated struct DXSpot: Identifiable, Hashable, Sendable {
    let id: String
    var callsign: String
    var spotter: String
    var frequencyKHz: Double
    var band: String
    var mode: String
    var submode: String
    var comment: String
    var grid: String
    var spottedAt: Date
    var lastSeenAt: Date
    var reportCount: Int

    var frequencyMHz: Double { frequencyKHz / 1_000 }
}

nonisolated enum DXClusterConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(String)

    var title: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .reconnecting(let attempt): return "Reconnecting (\(attempt))"
        case .failed: return "Connection failed"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

nonisolated enum DXSpotParser {
    private static let spotRegex = try! NSRegularExpression(
        pattern: #"DX\s+de\s+([^:\s]+)\s*:\s*([0-9]+(?:\.[0-9]+)?)\s+([A-Z0-9/]+)\s*(.*)"#,
        options: [.caseInsensitive]
    )
    private static let timeRegex = try! NSRegularExpression(pattern: #"\b([0-2][0-9][0-5][0-9])Z\b"#, options: [.caseInsensitive])
    private static let gridRegex = try! NSRegularExpression(pattern: #"\b([A-R]{2}[0-9]{2}(?:[A-X]{2})?)\b"#, options: [.caseInsensitive])

    static func parse(line: String, now: Date = Date()) -> DXSpot? {
        let clean = line
            .replacingOccurrences(of: "\u{0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fullRange = NSRange(clean.startIndex..<clean.endIndex, in: clean)
        guard let match = spotRegex.firstMatch(in: clean, range: fullRange),
              let spotterRange = Range(match.range(at: 1), in: clean),
              let frequencyRange = Range(match.range(at: 2), in: clean),
              let callRange = Range(match.range(at: 3), in: clean),
              let remainderRange = Range(match.range(at: 4), in: clean),
              let frequencyKHz = Double(clean[frequencyRange]) else { return nil }

        let callsign = String(clean[callRange]).uppercased()
        guard callsign.count >= 3, callsign.contains(where: \.isLetter), callsign.contains(where: \.isNumber) else { return nil }

        let spotter = String(clean[spotterRange]).uppercased()
        let remainder = String(clean[remainderRange])
        let time = firstCapture(timeRegex, in: remainder) ?? ""
        let grid = (firstCapture(gridRegex, in: remainder) ?? "").uppercased()
        var comment = remainder
            .replacingOccurrences(of: #"\b[0-2][0-9][0-5][0-9]Z\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !grid.isEmpty {
            comment = comment.replacingOccurrences(of: grid, with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        comment = comment.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        let frequencyMHz = frequencyKHz / 1_000
        let band = AmateurBandPlan.band(forMHz: frequencyMHz) ?? ""
        let mode = AmateurBandPlan.inferredMode(frequencyMHz: frequencyMHz, comment: comment)
        let submode = AmateurBandPlan.submode(from: comment)
        let spottedAt = date(forUTC: time, relativeTo: now)
        let idFrequency = Int((frequencyKHz * 10).rounded())

        return DXSpot(
            id: "\(callsign)-\(idFrequency)",
            callsign: callsign,
            spotter: spotter,
            frequencyKHz: frequencyKHz,
            band: band,
            mode: mode,
            submode: submode,
            comment: comment,
            grid: grid,
            spottedAt: spottedAt,
            lastSeenAt: now,
            reportCount: 1
        )
    }

    private static func firstCapture(_ regex: NSRegularExpression, in value: String) -> String? {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let captureRange = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[captureRange])
    }

    private static func date(forUTC time: String, relativeTo now: Date) -> Date {
        guard time.count == 4,
              let hour = Int(time.prefix(2)),
              let minute = Int(time.suffix(2)) else { return now }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard var result = calendar.date(from: components) else { return now }
        if result.timeIntervalSince(now) > 12 * 60 * 60 {
            result = calendar.date(byAdding: .day, value: -1, to: result) ?? result
        }
        return result
    }
}

nonisolated enum SyncSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case externalADIF
    case sdrControl
    case lotw
    case qrz

    var id: String { rawValue }

    var title: String {
        switch self {
        case .externalADIF: return "External ADIF"
        case .sdrControl: return "SDR-Control"
        case .lotw: return "LoTW"
        case .qrz: return "QRZ Logbook"
        }
    }

    var systemImage: String {
        switch self {
        case .externalADIF: return "doc.badge.arrow.up"
        case .sdrControl: return "wave.3.right"
        case .lotw: return "globe.americas.fill"
        case .qrz: return "q.circle.fill"
        }
    }
}

nonisolated enum SyncRunState: String, Codable, Sendable {
    case idle
    case running
    case success
    case warning
    case failure
}

nonisolated struct SyncServiceStatus: Identifiable, Codable, Equatable, Sendable {
    var source: SyncSource
    var state: SyncRunState = .idle
    var configured = false
    var lastRun: Date?
    var lastSuccess: Date?
    var detail = "Not run yet"
    var changedRecords = 0

    var id: SyncSource { source }
}

nonisolated struct SyncHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var source: SyncSource
    var startedAt: Date
    var completedAt: Date
    var state: SyncRunState
    var detail: String
    var changedRecords: Int
}

nonisolated struct MergeSummary: Equatable, Sendable {
    var added: Int
    var updated: Int
    var skipped: Int

    var changed: Int { added + updated }
}

nonisolated struct ConfirmationSyncSummary: Equatable, Sendable {
    var lotwFetched = 0
    var qrzFetched = 0
    var lotwChanged = 0
    var qrzChanged = 0
    var lotwMessage = "Not run"
    var qrzMessage = "Not run"
    var lotwFailed = false
    var qrzFailed = false

    var fetched: Int { lotwFetched + qrzFetched }
    var changed: Int { lotwChanged + qrzChanged }
}

nonisolated struct ConfirmationMatchIndex: Sendable {
    private let byCallDate: [String: [Int]]
    private let byCallDateBand: [String: [Int]]

    init(records: [[String: String]]) {
        var callDate: [String: [Int]] = [:]
        var callDateBand: [String: [Int]] = [:]
        for (index, record) in records.enumerated() {
            let call = Self.clean(record["CALL"] ?? "")
            let date = (record["QSO_DATE"] ?? "").filter(\.isNumber)
            guard !call.isEmpty, !date.isEmpty else { continue }
            let base = "\(call)|\(date)"
            callDate[base, default: []].append(index)
            let band = Self.clean(record["BAND"] ?? "")
            if !band.isEmpty {
                callDateBand["\(base)|\(band)", default: []].append(index)
            }
        }
        byCallDate = callDate
        byCallDateBand = callDateBand
    }

    func candidates(callsign: String, date: String, band: String? = nil) -> [Int] {
        let base = "\(Self.clean(callsign))|\(date.filter(\.isNumber))"
        if let band {
            let cleanBand = Self.clean(band)
            if !cleanBand.isEmpty, let exact = byCallDateBand["\(base)|\(cleanBand)"] {
                return exact
            }
        }
        return byCallDate[base] ?? []
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
