import Foundation

/// The TX-500's CAT S-meter reading (`SM`) and how YAAM shows it.
/// Pure Foundation, so it can be regression-tested standalone:
///   swiftc -parse-as-library Tests/Lab599TX500SMeterRegression.swift YAAM/Lab599TX500SMeter.swift -o /tmp/tx500sm && /tmp/tx500sm
///
/// Radio side, Lab599 CAT protocol reference guide rev.3, page 9, command SM:
///   Read    S M P1 ;                P1 = 0 ("Always 0")
///   Answer  S M P1 P2 P2 P2 P2 ;    P2 = 0000 ~ 0030
/// The guide gives the range of the count, not what a count means in S-units or dB.
///
/// YAAM side: `Lab599TX500Driver.sMeterValue` runs 0...15, 9 = S9, 10 dB per unit above 9
/// (15 = S9+60 dB); the rig toolbar, the FT8 HUD and the diagnostics box expect that. The count is
/// mapped onto it so that the upper half of the radio's range is not lost:
///   count 0...15  ->  S0...S9        (0.6 unit per count)
///   count 15...30 ->  S9...S9+60 dB  (4 dB per count)
/// Count 15 = S9 is an assumption (the middle of the range); no document says it. Change `s9Count`
/// if a measurement with a signal generator shows another value.
nonisolated enum Lab599TX500SMeter {
    /// Read command. P1 is part of the command: the guide's read form is `SM P1 ;`, not `SM;`.
    static let readCommand = "SM0;"

    private static let maximumCount = 30
    private static let s9Count = 15

    /// YAAM S-meter units (0...15, 9 = S9) for an answer such as `SM00015`, as the driver hands it over
    /// (the closing `;` already removed); nil if it is not in the documented form: `SM`, P1 = `0`, and
    /// P2 = four digits from `0000` to `0030`.
    static func units(fromReply reply: String) -> Double? {
        let zero = UInt8(ascii: "0"), nine = UInt8(ascii: "9")
        let bytes = Array(reply.utf8)
        guard bytes.count == 7, bytes[0] == UInt8(ascii: "S"), bytes[1] == UInt8(ascii: "M"), bytes[2] == zero,
              bytes[3...].allSatisfy({ $0 >= zero && $0 <= nine }) else { return nil }
        let count = bytes[3...].reduce(0) { $0 * 10 + Int($1 - zero) }
        guard count <= maximumCount else { return nil }
        let n = Double(count), s9 = Double(s9Count)
        if n <= s9 { return n * 9 / s9 }
        return 9 + (n - s9) * 6 / (Double(maximumCount) - s9)
    }

    /// Text for YAAM S-meter units: `S0`...`S9`, then `S9+<dB>dB`.
    static func description(forUnits units: Double) -> String {
        if units <= 9.0 { return "S\(Int(units))" }
        // Round, do not truncate: 10.2 - 9.0 is 1.1999999999999993 in binary floating point, which would show 11 dB, not 12.
        return "S9+\(Int(((units - 9.0) * 10).rounded()))dB"
    }
}
