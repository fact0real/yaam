//
//  OliviaCallsignDetectRegression.swift
//  YAAM
//
//  The Olivia receiver puts a callsign in CALL only once its word is complete, so the whole callsign is taken.
//  Run from the repository root:
//    swiftc -parse-as-library Tests/OliviaCallsignDetectRegression.swift YAAM/OliviaMFSKEngine.swift \
//      YAAM/TransmitIdentity.swift YAAM/GridLocator.swift -o ocd && ./ocd
//  Text is fed one character at a time, as the decoder delivers it. No audio engine is started.
//  The callsigns are samples starting with 0, plus G4ABC, the callsign in the author's practice text.
//

import Foundation

@main
struct OliviaCallsignDetectRegression {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition {
            passes += 1
            print("PASS \(label)")
        } else {
            failures += 1
            let extra = detail()
            print("FAIL \(label)" + (extra.isEmpty ? "" : "   [\(extra)]"))
        }
    }

    /// Feeds the text one character at a time and returns what CALL holds afterwards.
    @MainActor
    static func received(_ text: String) -> String {
        let engine = OliviaMFSKEngine()
        for ch in text { engine.appendDecodedChar(ch) }
        return engine.targetCallsign
    }

    @MainActor
    static func main() {
        let cases: [(text: String, call: String)] = [
            ("CQ CQ DE G4ABC OLIVIA 16/500 K ", "G4ABC"),
            ("CQ CQ DE 0A1BCD 0A1BCD K ", "0A1BCD"),
            ("CQ CQ DE 0B2CD\nPSE K ", "0B2CD"),
            ("UR 599 599 BK ", ""),
            ("CQ CQ DE 0A1BCD", ""),
        ]
        for c in cases {
            let got = received(c.text)
            let shown = c.text.replacingOccurrences(of: "\n", with: "\\n")
            check("\"\(shown)\" puts \(c.call.isEmpty ? "nothing" : c.call) in CALL", got == c.call, "CALL = \(got)")
        }

        // A word that is still arriving is not taken; it is taken when the space that ends it comes
        let engine = OliviaMFSKEngine()
        for ch in "CQ CQ DE 0A1B" { engine.appendDecodedChar(ch) }
        check("while 0A1BCD is still arriving, CALL stays empty", engine.targetCallsign.isEmpty, "CALL = \(engine.targetCallsign)")
        for ch in "CD " { engine.appendDecodedChar(ch) }
        check("when the word ends, CALL is 0A1BCD", engine.targetCallsign == "0A1BCD", "CALL = \(engine.targetCallsign)")
        for ch in "DE 0B2CD K " { engine.appendDecodedChar(ch) }
        check("a later callsign does not replace the one in CALL", engine.targetCallsign == "0A1BCD")

        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
