//
//  QSOIdentity.swift
//  YAAM
//

import Foundation

/// One canonical, lossless identity for matching the same QSO across imports,
/// persistence, and confirmation services.
nonisolated enum QSOIdentity {
    static func exactKey(fields: [String: String]) -> String {
        let call = clean(fields["CALL"] ?? "")
        let date = normalizedDate(fields["QSO_DATE"] ?? "")
        let time = normalizedTime(fields["TIME_ON"] ?? fields["TIME_OFF"] ?? "")
        let band = resolvedBand(fields)
        let mode = effectiveMode(fields)

        guard !call.isEmpty, date.count == 8, time.count == 6 else { return "" }
        return "\(call)|\(date)|\(time)|\(band)|\(mode)"
    }

    static func relaxedKey(fields: [String: String]) -> String {
        let call = clean(fields["CALL"] ?? "")
        let date = normalizedDate(fields["QSO_DATE"] ?? "")
        guard !call.isEmpty, date.count == 8 else { return "" }
        return "\(call)|\(date)|\(resolvedBand(fields))|\(effectiveMode(fields))"
    }

    /// Key based on CALL|DATE|TIME|BAND (independent of MODE)
    static func baseKey(fields: [String: String]) -> String {
        let call = clean(fields["CALL"] ?? "")
        let date = normalizedDate(fields["QSO_DATE"] ?? "")
        let time = normalizedTime(fields["TIME_ON"] ?? fields["TIME_OFF"] ?? "")
        let band = resolvedBand(fields)
        guard !call.isEmpty, date.count == 8, time.count == 6 else { return "" }
        return "\(call)|\(date)|\(time)|\(band)"
    }

    /// Key based on CALL|DATE|BAND for grouping duplicate clusters regardless of time/mode
    static func callDateBandKey(fields: [String: String]) -> String {
        let call = clean(fields["CALL"] ?? "")
        let date = normalizedDate(fields["QSO_DATE"] ?? "")
        let band = resolvedBand(fields)
        guard !call.isEmpty, date.count == 8 else { return "" }
        return "\(call)|\(date)|\(band)"
    }

    /// Returns true if two modes are equal, or if either mode is missing/empty, or if they represent compatible digital modes.
    static func areModesCompatible(_ mode1: String, _ mode2: String) -> Bool {
        let m1 = clean(mode1)
        let m2 = clean(mode2)
        if m1.isEmpty || m2.isEmpty { return true }
        if m1 == m2 { return true }
        let digitalModes: Set<String> = ["FT8", "FT4", "JT65", "JT9", "MSK144", "Q65", "JS8", "DATA", "DIGI"]
        if digitalModes.contains(m1) && (m2 == "DATA" || m2 == "DIGI") { return true }
        if digitalModes.contains(m2) && (m1 == "DATA" || m1 == "DIGI") { return true }
        return false
    }

    /// Returns true if two records describe the same underlying QSO, accounting for missing mode or slight timestamp variations.
    static func isSameQSO(lhs: [String: String], rhs: [String: String], timeToleranceSeconds: Int = 0) -> Bool {
        let sdrId1 = lhs["APP_SDR_CONTROL_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sdrId2 = rhs["APP_SDR_CONTROL_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !sdrId1.isEmpty && !sdrId2.isEmpty && sdrId1.caseInsensitiveCompare(sdrId2) == .orderedSame {
            return true
        }

        let call1 = clean(lhs["CALL"] ?? "")
        let call2 = clean(rhs["CALL"] ?? "")
        guard !call1.isEmpty, call1 == call2 else { return false }

        let date1 = normalizedDate(lhs["QSO_DATE"] ?? "")
        let date2 = normalizedDate(rhs["QSO_DATE"] ?? "")
        guard date1 == date2, date1.count == 8 else { return false }

        let band1 = resolvedBand(lhs)
        let band2 = resolvedBand(rhs)
        guard !band1.isEmpty, band1 == band2 else { return false }

        let mode1 = effectiveMode(lhs)
        let mode2 = effectiveMode(rhs)
        guard areModesCompatible(mode1, mode2) else { return false }

        guard let sec1 = secondsFromMidnight(lhs), let sec2 = secondsFromMidnight(rhs) else {
            return false
        }
        return abs(sec1 - sec2) <= timeToleranceSeconds
    }

    static func normalizedTime(_ value: String) -> String {
        let digits = String(value.filter(\.isNumber))
        if digits.count == 4 { return digits + "00" }
        if digits.count >= 6 { return String(digits.prefix(6)) }
        return ""
    }

    static func secondsFromMidnight(_ fields: [String: String]) -> Int? {
        let time = normalizedTime(fields["TIME_ON"] ?? fields["TIME_OFF"] ?? "")
        guard time.count == 6,
              let hour = Int(time.prefix(2)),
              let minute = Int(time.dropFirst(2).prefix(2)),
              let second = Int(time.dropFirst(4).prefix(2)),
              hour < 24,
              minute < 60,
              second < 60 else {
            return nil
        }
        return hour * 3_600 + minute * 60 + second
    }

    static func resolvedBand(_ fields: [String: String]) -> String {
        let explicit = normalizedBand(fields["BAND"] ?? "")
        if !explicit.isEmpty { return explicit }
        return inferredBand(from: fields["FREQ"] ?? "") ?? ""
    }

    static func effectiveMode(_ fields: [String: String]) -> String {
        let submode = clean(fields["SUBMODE"] ?? "")
        return submode.isEmpty ? clean(fields["MODE"] ?? "") : submode
    }

    private static func normalizedDate(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(8))
    }

    private static func normalizedBand(_ value: String) -> String {
        value
            .uppercased()
            .replacingOccurrences(of: "METERS", with: "M")
            .replacingOccurrences(of: "METER", with: "M")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func inferredBand(from rawValue: String) -> String? {
        let upper = rawValue.uppercased()
        let isKilohertz = upper.contains("KHZ")
        let isHertz = !isKilohertz && upper.contains("HZ") && !upper.contains("MHZ")
        let cleanValue = rawValue
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "MHz", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "kHz", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Hz", with: "", options: .caseInsensitive)
        guard var frequency = Double(cleanValue), frequency > 0 else { return nil }
        if isHertz || (!isKilohertz && frequency >= 1_000_000) {
            frequency /= 1_000_000
        } else if isKilohertz {
            frequency /= 1_000
        }

        return frequencyBandRanges.first(where: { $0.0.contains(frequency) })?.1
    }

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
}
