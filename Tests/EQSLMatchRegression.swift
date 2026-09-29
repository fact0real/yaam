import Foundation

// Standalone: swiftc -parse-as-library Tests/EQSLMatchRegression.swift YAAM/QSOIdentity.swift -o /tmp/eqm && /tmp/eqm
@main
struct EQSLMatchRegression {
    static func qso(_ call: String, _ time: String, _ band: String = "20M", _ mode: String = "SSB") -> [String: String] {
        ["CALL": call, "QSO_DATE": "20260820", "TIME_ON": time, "BAND": band, "MODE": mode]
    }

    static func match(_ incoming: [String: String], _ log: [[String: String]], claimed: Set<Int> = []) -> Int? {
        QSOIdentity.bestToleranceMatch(incoming: incoming, candidates: log, claimed: claimed,
                                       toleranceSeconds: QSOIdentity.eqslTimeToleranceSeconds)
    }

    static func main() {
        // Times a minute or more apart still match, up to eQSL's one hour
        precondition(match(qso("K1ABC", "1012"), [qso("K1ABC", "101000")]) == 0)
        precondition(match(qso("K1ABC", "1059"), [qso("K1ABC", "100000")]) == 0)
        precondition(match(qso("K1ABC", "1101"), [qso("K1ABC", "100000")]) == nil)

        // Nearest wins, and a claimed QSO takes no second confirmation
        let log = [qso("K1ABC", "101000"), qso("K1ABC", "104000")]
        var claimed = Set<Int>()
        let first = match(qso("K1ABC", "1038"), log, claimed: claimed)
        precondition(first == 1); claimed.insert(1)
        precondition(match(qso("K1ABC", "1038"), log, claimed: claimed) == 0)
        claimed.insert(0)
        precondition(match(qso("K1ABC", "1038"), log, claimed: claimed) == nil)

        // Band and mode still have to fit; DATA and FT8 are compatible
        precondition(match(qso("K1ABC", "1010", "40M"), [qso("K1ABC", "101000")]) == nil)
        precondition(match(qso("K1ABC", "1010", "20M", "CW"), [qso("K1ABC", "101000")]) == nil)
        precondition(match(qso("K1ABC", "1010", "20M", "DATA"), [qso("K1ABC", "101000", "20M", "FT8")]) == 0)

        // Without CALL or an 8-digit date nothing matches
        precondition(match(["CALL": "K1ABC", "TIME_ON": "1010"], [qso("K1ABC", "101000")]) == nil)
        precondition(match(qso("", "1010"), [qso("", "101000")]) == nil)

        print("eQSL match regression tests passed.")
    }
}
