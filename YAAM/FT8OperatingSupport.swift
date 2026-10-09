import Foundation

/// Pure receive-side helpers; none of these routines keys or tunes a radio.
nonisolated enum FT8MessageIdentity {
    static func callsign(_ token: String) -> String? {
        let value = token.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        guard (3...16).contains(value.count), value.contains(where: \.isNumber),
              value.contains(where: \.isLetter),
              value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "/") }),
              value != "RR73", value != "73" else { return nil }
        // Four/six-character locators are not transmitting callsigns.
        if value.range(of: "^[A-R]{2}[0-9]{2}([A-X]{2})?$", options: .regularExpression) != nil { return nil }
        return value
    }

    static func sender(in message: String) -> String? {
        let words = message.uppercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2 else { return nil }
        if words[0] == "CQ" || words[0] == "QRZ" {
            return callsign(words[1]) ?? (words.count > 2 ? callsign(words[2]) : nil)
        }
        // A hash such as <...> cannot identify the sender. Never substitute
        // the first token: that is the receiving station in a directed message.
        return callsign(words[1])
    }
}

nonisolated struct FT8SWRTripGuard {
    private var lastSample: Date?
    private var highReadings = 0

    mutating func shouldStop(enabled: Bool, startedAt: Date?, power: Double,
                             swr: Double, sampledAt: Date?, now: Date) -> Bool {
        guard enabled, let startedAt, let sampledAt, sampledAt >= startedAt,
              now.timeIntervalSince(sampledAt) >= 0, now.timeIntervalSince(sampledAt) <= 2,
              power.isFinite, power > 1, swr.isFinite else {
            highReadings = 0
            lastSample = nil
            return false
        }
        guard sampledAt != lastSample else { return false }
        lastSample = sampledAt
        highReadings = swr > 2.5 ? highReadings + 1 : 0
        return highReadings >= 2
    }
}

nonisolated enum FT8QuietFrequencyAdvisor {
    static func suggest(rows: [[Float]], minimumHz: Float, binHz: Float,
                        bandwidthHz: Float, occupied: [Float]) -> Int? {
        guard rows.count >= 12, let width = rows.first?.count, width > 20,
              binHz.isFinite, binHz > 0, rows.allSatisfy({ $0.count == width }) else { return nil }
        var envelope = [Float](repeating: 0, count: width)
        for row in rows {
            for i in row.indices {
                guard row[i].isFinite else { return nil }
                envelope[i] = max(envelope[i], row[i])
            }
        }
        guard let peak = envelope.max(), peak > 0.02 else { return nil }
        var best: (hz: Int, score: Float)?
        for hz in stride(from: 350, through: 2700, by: 25) {
            let base = Float(hz)
            guard !occupied.contains(where: { abs($0 - base) < bandwidthHz + 35 }) else { continue }
            let lower = Int(((base - 25 - minimumHz) / binHz).rounded(.down))
            let upper = Int(((base + bandwidthHz + 25 - minimumHz) / binHz).rounded(.up))
            guard lower >= 0, upper < width, lower < upper else { continue }
            let window = envelope[lower...upper]
            let maxEnergy = window.max() ?? 1
            guard maxEnergy < 0.70 else { continue }
            let score = window.reduce(0, +) / Float(window.count) + maxEnergy * 0.5
            if best == nil || score < best!.score { best = (hz, score) }
        }
        return best?.hz
    }
}
