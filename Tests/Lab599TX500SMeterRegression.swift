import Foundation

// Standalone, no radio or app needed:
//   swiftc -parse-as-library Tests/Lab599TX500SMeterRegression.swift YAAM/Lab599TX500SMeter.swift -o /tmp/tx500sm && /tmp/tx500sm
// Frame and range: Lab599 CAT protocol reference guide rev.3, page 9, command SM
// (read `SM0;`, answer `SM` + P1 `0` + P2 `0000`...`0030` + `;`).
// Expected values are written out here with integer arithmetic, not taken from the helper.
@main
struct Lab599TX500SMeterRegression {
    static func main() {
        var checks = 0, failures = 0
        func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
            checks += 1
            guard !condition else { return }
            failures += 1
            if failures <= 12 { print("FAIL: \(message())") }
        }
        func frame(_ count: Int) -> String { "SM0" + String(format: "%04d", count) }
        func units(_ reply: String) -> String {
            Lab599TX500SMeter.units(fromReply: reply).map { String(format: "%.1f", $0) } ?? "nil"
        }
        func shown(_ reply: String) -> String {
            Lab599TX500SMeter.units(fromReply: reply).map { Lab599TX500SMeter.description(forUnits: $0) } ?? "nil"
        }

        // The read command carries P1: `SM P1 ;` with P1 = 0, not a bare `SM;`.
        expect(Lab599TX500SMeter.readCommand == "SM0;", "read command is \(Lab599TX500SMeter.readCommand.debugDescription), the guide gives \"SM0;\"")

        // The upper half of the radio's range is not folded into one reading: counts 15...30 all read differently.
        let upperHalf = Set((15...30).map { shown(frame($0)) })
        expect(upperHalf.count == 16, "counts 15...30 give \(upperHalf.count) distinct readings, expected 16")

        // Anchors, as the operator sees them.
        for (count, text) in [(0, "S0"), (15, "S9"), (18, "S9+12dB"), (30, "S9+60dB")] {
            expect(shown(frame(count)) == text, "\(frame(count)) shows \(shown(frame(count))), expected \(text)")
        }

        // Every count the radio can answer, 0...30: YAAM units (0.6 per count up to 15, then 0.4) and text.
        var previous = -1.0
        for count in 0...30 {
            let value = Lab599TX500SMeter.units(fromReply: frame(count))
            let expectedUnits = count <= 15 ? Double(count * 3) / 5 : 9.0 + Double((count - 15) * 2) / 5
            expect(value.map { abs($0 - expectedUnits) < 1e-9 } ?? false,
                   "\(frame(count)): units \(units(frame(count))), expected \(String(format: "%.1f", expectedUnits))")
            expect((value ?? -1) > previous, "\(frame(count)): units must rise with every count")
            previous = value ?? previous
            let expectedText = count <= 15 ? "S\(count * 9 / 15)" : "S9+\((count - 15) * 4)dB"
            expect(shown(frame(count)) == expectedText, "\(frame(count)) shows \(shown(frame(count))), expected \(expectedText)")
        }

        // Not answers in the documented form: ignored, so the meter keeps its last value.
        let rejected = [
            "", "SM", "SM0", "SM;", "SM0005", "SM000", "SM000150",             // wrong length: no P1, three-digit P2, extra digit
            "SM00015;",                                                        // the driver removes the ";" before it parses
            "SM10015", "SM90015",                                              // P1 is always 0
            "SM00031", "SM00099",                                              // above 0030
            "SM0001A", "SM0 015", "SM+0015", "SM-0015", "SM 0015", "SM0.015",
            "SM\u{0660}\u{0660}\u{0660}\u{0661}\u{0665}",                      // Arabic-Indic digits
            "?", "E", "O", "FA00014074000", "PC005", "sm00015", " SM00015",
        ]
        for reply in rejected {
            expect(Lab599TX500SMeter.units(fromReply: reply) == nil, "\(reply.debugDescription) should be ignored, gives \(units(reply))")
        }

        print("Lab599TX500SMeterRegression: \(checks) checks, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
