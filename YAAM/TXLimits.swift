import Foundation

/// Application safety timers are best effort; they cannot confirm physical RF state or run while the process stalls.
nonisolated public enum TXLimits {
    public static let hardPTT: TimeInterval = 120
    public static let tx500PTT: TimeInterval = 14
    public static let fx4crPTT: TimeInterval = 14
    public static let icomUSBPTT: TimeInterval = 16
    public static let icomNetworkPTT: TimeInterval = 16
    public static let xieguPTT: TimeInterval = 15
    public static let rigctldPTT: TimeInterval = 14
    public static let flrigPTT: TimeInterval = 120

    public static func pttSafetyTimer(_ requested: TimeInterval) -> TimeInterval {
        guard requested.isFinite else { return 1 }
        return min(max(requested, 1), hardPTT)
    }

    public static func utc(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date) + " UTC"
    }

    public static func safetyTimerMessage(radio: String, keyedAt: Date, limit: TimeInterval,
                                         now: Date = Date(), elapsed: TimeInterval? = nil, extra: String = "") -> String {
        let measured = elapsed ?? now.timeIntervalSince(keyedAt)
        let seconds = measured.isFinite ? min(max(0, measured.rounded()), 1_000_000_000) : 0
        return "\(radio): PTT had been on for \(Int(seconds)) s; safety limit \(Int(pttSafetyTimer(limit))) s. At \(utc(now)) YAAM requested PTT release, but cannot confirm the radio is on receive. Check the radio and switch it to RX by hand if necessary. Audio or the radio’s own CW keyer may still be active; stop them too. \(extra.isEmpty ? "" : extra + " ")Receiving and logging remain available. Confirm receive before sending again."
    }

    public static func notConnectedMessage(radio: String, previous: String = "", now: Date = Date()) -> String {
        // Do not copy arbitrary previous network/driver output into a safety notice (it may contain private data).
        "\(radio): PTT not keyed at \(utc(now)), because the radio is not connected: YAAM did not key it. Connect it in Radio Control, then try again. Receiving and logging remain available."
    }
}
