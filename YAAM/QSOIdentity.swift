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
