import Foundation

@main
struct TXLimitsRegression {
    static func main() {
        for value in [Double.nan, .infinity, -.infinity, -4, 0, 0.5, 1, 14, 120, 1e30] {
            let limit = TXLimits.pttSafetyTimer(value)
            precondition(limit.isFinite && (1...120).contains(limit))
        }
        let date = Date(timeIntervalSince1970: 1_000_000_000)
        let text = TXLimits.safetyTimerMessage(radio: "TX-500", keyedAt: date, limit: 14,
                                              now: date.addingTimeInterval(10_000), elapsed: 14.4)
        precondition(text.contains("on for 14 s") && text.contains("safety limit 14 s"))
        precondition(text.contains("2001-09-09") && text.contains("UTC") && text.contains("cannot confirm"))
        precondition(!text.contains("Sound still playing is not transmitted"), "VOX or failed release can still transmit audio")
        let backwards = TXLimits.safetyTimerMessage(radio: "rigctld", keyedAt: date, limit: 14, now: date.addingTimeInterval(-10), elapsed: 15)
        precondition(backwards.contains("on for 15 s"), "Elapsed time must not use a stepped wall clock")
        let refusal = TXLimits.notConnectedMessage(radio: "Icom USB", previous: "secret-token")
        precondition(!refusal.contains("secret-token") && refusal.contains("logging remain available"))
        print("PASS finite PTT limits, UTC date, monotonic duration, honest release uncertainty and private-output exclusion")
    }
}
