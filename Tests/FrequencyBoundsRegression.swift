import Foundation

// Regression (Y-001): a spot's frequency comes from outside (the DX cluster, WSJT-X on the network, the POTA and SOTA
// services), and YAAM turns it into whole hertz with UInt64(kHz * 1000), which stops the app on infinity, NaN, a
// negative value or one too large. FrequencyBounds says which frequencies are usable; this test checks it with such
// values, and reads the two places where spots come in (BandmapEngine.addSpot, POTASpotsClient.tuneRig; comments and
// string literals removed) for the check before anything uses the frequency, and WSJTXListener for the sum of the
// network's dial and offset, which must not overflow before addSpot. Those files need most of the app to build, so they
// are read, not run.
// Build and run from the repository root (Tests/run-cw-safety-regressions.sh does it). The operator is EA3JIC.

@main
struct FrequencyBoundsRegression {
    static var failures = 0

    static func check(_ condition: Bool, _ label: String) {
        print("\(condition ? "PASS" : "FAIL") \(label)")
        if !condition { failures += 1 }
    }

    /// The file without its comments (`//` and `/* */`) and string literals (one-line and multi-line).
    static func code(_ file: String) -> String? {
        guard var text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
        for block in [#"/\*[\s\S]*?\*/"#, #"\"\"\"[\s\S]*?\"\"\""#] {
            text = text.replacingOccurrences(of: block, with: "", options: .regularExpression)
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let noStrings = String(line).replacingOccurrences(of: #""([^"\\]|\\.)*""#, with: "\"\"",
                                                              options: .regularExpression)
            return noStrings.range(of: "//").map { String(noStrings[..<$0.lowerBound]) } ?? noStrings
        }.joined(separator: "\n")
    }

    /// The part of `text` from `start` up to `end`, or "" if either is missing.
    static func section(_ text: String, from start: String, to end: String) -> String {
        guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { return "" }
        return String(text[a.upperBound..<b.lowerBound])
    }

    static func main() {
        // Usable: what a spot can really carry, from 136 kHz to the top amateur band and the 300 GHz limit.
        for kHz in [135.7, 7030.0, 14074.0, 10_368_100.0, 248_000_000.0, 300_000_000.0] {
            check(FrequencyBounds.isUsable(kHz: kHz), "\(kHz) kHz is usable")
        }
        // Not usable: each of these stops UInt64(kHz * 1000), or is no radio frequency.
        for kHz in [Double.infinity, -Double.infinity, Double.nan, -7030.0, 0, 0.0001, 300_000_000.1, 1e17, 1e20] {
            check(!FrequencyBounds.isUsable(kHz: kHz), "\(kHz) kHz is refused")
        }
        check(FrequencyBounds.hertz(kHz: 0.001) == 1, "one hertz is the smallest whole-hertz tune")
        check(FrequencyBounds.hertz(kHz: Double.nan) == nil && FrequencyBounds.hertz(kHz: -1) == nil,
              "the final conversion refuses invalid archive/provider values without trapping")
        // Every usable value converts without stopping, at the top too.
        check(UInt64(FrequencyBounds.maximumKHz * 1000.0) == 300_000_000_000, "the top converts to 300 GHz in hertz")

        // Where spots come in, the check comes before anything uses the frequency.
        if let engine = code("YAAM/BandmapEngine.swift") {
            let addSpot = section(engine, from: "func addSpot(", to: "let resolvedBand")
            check(addSpot.contains("FrequencyBounds.isUsable(kHz: frequencyKHz)"),
                  "BandmapEngine.addSpot drops a spot whose frequency is not usable, before using it")
        } else {
            check(false, "YAAM/BandmapEngine.swift can be read (run from the repository root)")
        }
        if let pota = code("YAAM/POTASpotsClient.swift") {
            let tune = section(pota, from: "func tuneRig(", to: "let hz = UInt64(frequencyKHz * 1000.0)")
            check(tune.contains("guard FrequencyBounds.isUsable(kHz: frequencyKHz) else {") && tune.contains("return"),
                  "POTASpotsClient.tuneRig does not tune to an unusable frequency, before converting it")
        } else {
            check(false, "YAAM/POTASpotsClient.swift can be read (run from the repository root)")
        }

        if let wsjtx = code("YAAM/WSJTXListener.swift") {
            let decode = section(wsjtx, from: "let dialHz = lastStatus?.dialFrequencyHz", to: "BandmapEngine.shared.addSpot(")
            check(!decode.isEmpty && !decode.contains("dialHz + UInt64(") && decode.contains("Double(dialHz) + Double("),
                  "WSJTXListener adds the network's dial and offset as Double, so a huge dial cannot stop YAAM before addSpot")
        } else {
            check(false, "YAAM/WSJTXListener.swift can be read (run from the repository root)")
        }
        if failures > 0 { print("Frequency bounds regression FAILED (\(failures))"); exit(1) }
        print("Frequency bounds regression passed")
    }
}
