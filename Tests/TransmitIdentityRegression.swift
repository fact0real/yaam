import Foundation

// Nothing may be transmitted without the operator's own callsign (and, for FT8/FT4, locator). TransmitIdentity
// is the one check that the FT8/FT4, CW, RTTY/PSK, Hellschreiber and Olivia transmit paths share. This test
// covers the rules and reads the sources to pin each place that asks the check. Build and run it from the
// repository root (DEVELOPER_DOCUMENTATION.md section 8.2):
//   swiftc -parse-as-library Tests/TransmitIdentityRegression.swift YAAM/TransmitIdentity.swift \
//       YAAM/GridLocator.swift -o tir && ./tir
// The engines are run, against stand-ins for the radio drivers, by Tests/TransmitGatesBehaviourRegression.swift
// (CW, contest Enter key and function keys, RTTY/PSK) and Tests/TransmitGatesFT8Regression.swift (FT8/FT4).
// A source check cannot see that a check which is still in the text has stopped working, so for each place
// it pins the whole refusal block (the condition, what is shown, and the return that stops the send) and
// that the block comes before the call that keys the transmitter. The operators in the checks are EA3JIC
// and EP2AES, with four-character island locators as if on holiday (BL10, Hawaii; LG89, Mauritius), not their
// home ones. The longer locators (6, 8 and 10 characters) are those of a POTA activation, computed from the
// coordinates in the official POTA park list (pota.app, 08-10-2026): EA3JIC at US-0001 Acadia National Park
// (44.31, -68.2034): FN54, FN54VH, FN54VH54, FN54VH54OJ; EP2AES at CA-0005 Banff National Park
// (51.4968, -115.928): DO21, DO21AL, DO21AL89, DO21AL89PF.

@main
struct TransmitIdentityRegression {
    nonisolated(unsafe) static var failures = 0
    static func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL") \(name)")
        if !ok { failures += 1 }
    }

    static func main() {
        callsignRules()
        callsignShapeSwitch()
        locatorRules()
        ft8Identity()
        ft8Messages()
        savedValues()
        stationsScreenNote()
        check("the rules can be called off the main actor", offMainActor())
        check("TransmitIdentity is declared nonisolated, as the app's default isolation is the main actor",
              sourceText("YAAM/TransmitIdentity.swift")?.contains("nonisolated enum TransmitIdentity") == true)
        check("the callsign shape switch is declared once, as a constant",
              sourceText("YAAM/TransmitIdentity.swift")?.components(separatedBy: "static let acceptsCallsignsEndingInDigit =").count == 2)

        sidetoneAndKeyer()
        contestAndEsm()
        digitalModes()
        ft8Gates()
        testButtonsAndChat()
        refusalsAreShown()
        knownKeyingSites()

        if failures > 0 {
            print("Transmit identity regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Transmit identity regression passed")
    }

    // MARK: - Callsign

    static let missing = TransmitIdentity.callsignMissingMessage
    static let rejected = TransmitIdentity.callsignRejectedMessage

    static func callsignRules() {
        // The operator is EA3JIC in one run and EP2AES in the other; both get the same checks.
        for own in ["EA3JIC", "EP2AES"] {
            check("\(own) is a usable callsign", TransmitIdentity.isValidCallsign(own))
            check("\(own): case and surrounding spaces are ignored",
                  TransmitIdentity.usableCallsign(" \(own.lowercased())\n") == own)
            check("\(own): a portable suffix or a country prefix is accepted",
                  TransmitIdentity.isValidCallsign("\(own)/P") && TransmitIdentity.isValidCallsign("DL/\(own)"))
        }
        // Unusual but real shapes must not be refused: a station that cannot transmit because its call looks odd
        // is worse than one that sends with a call that only looks plausible.
        for sample in ["01ABC", "01AW", "0D2RR", "0X4DK", "0A1A", "0A61Q", "0E3EJ", "0A60URE", "0P2YAAM",
                       "0B100RSGB", "0E100X", "0DA0RS", "0K9X/03XYZ", "OH0/EA3JIC/P", "EA3JIC/QRP", "03XYZ/MM"] {
            check("sample callsign \(sample) is accepted", TransmitIdentity.isValidCallsign(sample))
        }
        let notSet: [String?] = [nil, "", "   ", "DEFAULT", "default", " NoCall ", "N0CALL", "CALLSIGN", "MYCALL", "YOURCALL", "YOURCALLSIGN"]
        for value in notSet {
            check("\(value.map { "\"\($0)\"" } ?? "nil") is not set: not usable, and the message says to set it",
                  !TransmitIdentity.isValidCallsign(value) && TransmitIdentity.usableCallsign(value) == nil
                  && TransmitIdentity.callsignRefusal(value) == missing
                  && TransmitIdentity.isPlaceholderCallsign(value) && TransmitIdentity.enteredCallsign(value).isEmpty)
        }
        let notAccepted: [String] = ["TEST", "123", "ABC", "TEST1", "MYCALL1", "NOCALL1", "CALL123",
                                     "0L1ABC 0L2ABC", "DL1-ABC", "0L1ABC-1", "0L1ABC/", "/P", "0L1ABC//P"]
        for value in notAccepted {
            check("\"\(value)\" is entered but not accepted: the message says so, not \"set your callsign\"",
                  !TransmitIdentity.isValidCallsign(value) && TransmitIdentity.callsignRefusal(value) == rejected
                  && !TransmitIdentity.isPlaceholderCallsign(value) && TransmitIdentity.enteredCallsign(value) == value.uppercased())
        }
        check("the texts of the identity refusals are recognised, other texts are not",
              [missing, rejected, TransmitIdentity.locatorMissingMessage, TransmitIdentity.locatorRejectedMessage,
               TransmitIdentity.notYourCallsignText, TransmitIdentity.notYourLocatorText].allSatisfy { TransmitIdentity.isIdentityRefusal($0) }
              && ["", "Arm TX before scheduling a transmission.", TransmitIdentity.noMessageText, "The Icom LAN radio is not connected."]
                  .allSatisfy { !TransmitIdentity.isIdentityRefusal($0) })
        check("the two callsign messages differ, and both point to Settings > Stations",
              missing != rejected && missing.contains("Settings > Stations") && rejected.contains("Settings > Stations"))
        check("a usable callsign has no refusal", TransmitIdentity.callsignRefusal("EA3JIC") == nil && TransmitIdentity.callsignRefusal("EP2AES") == nil)
    }

    /// The owner decides whether a callsign that ends in a digit is accepted: one constant. Both values are run.
    static func callsignShapeSwitch() {
        let endingInDigit = ["0I2012", "0M100", "0D100", "0R100", "0L2024"]
        for call in ["EA3", "AB1", "ABC1"] {
            check("\(call) ends in a digit and is refused while the digit ending is not accepted",
                  !TransmitIdentity.isValidCallsign(call, acceptsCallsignsEndingInDigit: false))
        }
        for call in endingInDigit {
            check("\(call) is refused while the digit ending is not accepted",
                  !TransmitIdentity.isValidCallsign(call, acceptsCallsignsEndingInDigit: false)
                  && TransmitIdentity.callsignRefusal(call, acceptsCallsignsEndingInDigit: false) == rejected)
            check("\(call) is accepted when the digit ending is accepted",
                  TransmitIdentity.isValidCallsign(call, acceptsCallsignsEndingInDigit: true)
                  && TransmitIdentity.usableCallsign(call, acceptsCallsignsEndingInDigit: true) == call
                  && TransmitIdentity.callsignRefusal(call, acceptsCallsignsEndingInDigit: true) == nil)
            check("\(call) follows the constant when no parameter is given",
                  TransmitIdentity.isValidCallsign(call) == TransmitIdentity.acceptsCallsignsEndingInDigit)
        }
        // Whatever the value, ordinary callsigns, placeholders and non-callsigns are decided the same way.
        for value in [false, true] {
            for call in ["EA3JIC", "EP2AES", "01ABC", "0A1A", "DL/EA3JIC/P", "0B100RSGB"] {
                check("\(call) is accepted (digit ending accepted = \(value))",
                      TransmitIdentity.isValidCallsign(call, acceptsCallsignsEndingInDigit: value))
            }
            for call in ["", "NOCALL", "N0CALL", "DEFAULT", "CALLSIGN", "TEST", "123", "0L1ABC-1", "TEST1", "MYCALL1", "0L1ABC//P", "/P", "DL/123"] {
                check("\(call.debugDescription) is not accepted (digit ending accepted = \(value))",
                      !TransmitIdentity.isValidCallsign(call, acceptsCallsignsEndingInDigit: value))
            }
        }
    }

    // MARK: - Locator

    static func locatorRules() {
        // Accepted exactly when the Stations screen accepts it: the first four characters are a valid square.
        let samples = ["BL10", "LG89", "bl10", "FN54vh", " LG89\n", "FN54VH54", "FN54VH54OJ", "FN54VH5", "FN54ZZ", "FN54 vh", "FN54v",
                       "DO21al", "DO21AL89", "DO21AL89PF",
                       "", "----", "XX99", "SS00", "1234", "JN1", "JN 11", "AA00", "RR99", "RS00"]
        for value in samples {
            check("\(value.debugDescription): accepted as a locator exactly when the Stations screen accepts it",
                  TransmitIdentity.isValidLocator(value) == (GridLocator.fourCharacterGrid(from: value) != nil))
        }
        check("FT8 sends the first four characters (EA3JIC at US-0001 Acadia National Park, EP2AES on holiday and at CA-0005 Banff National Park)",
              TransmitIdentity.ft8Locator("FN54VH54") == "FN54" && TransmitIdentity.ft8Locator("fn54vh") == "FN54"
              && TransmitIdentity.ft8Locator("DO21AL89PF") == "DO21"
              && TransmitIdentity.ft8Locator("LG89") == "LG89" && TransmitIdentity.ft8Locator(" lg89\n") == "LG89")
        let wellFormed: [(String, String?)] = [
            ("BL10", "BL10"), ("FN54VH", "FN54VH"), ("fn54vh54", "FN54VH54"), ("FN54VH54OJ", "FN54VH54OJ"),
            ("FN54VH5", "FN54VH"), ("FN54VH54O", "FN54VH54"), ("FN54ZZ", "FN54"), ("FN54VH5Z", "FN54VH"),
            ("FN54 vh", "FN54"), ("DO21al", "DO21AL"), ("DO21AL89", "DO21AL89"), ("do21al89pf", "DO21AL89PF"),
            ("DO21YY", "DO21"), ("----", nil), ("", nil), ("JN1", nil)
        ]
        for (input, expected) in wellFormed {
            check("\(input.debugDescription) is sent as \(expected.map { "\"\($0)\"" } ?? "no locator") when more than four characters go out",
                  TransmitIdentity.locator(input) == expected)
        }
        check("a locator with digits of another script is refused, though the Stations screen accepts it",
              GridLocator.fourCharacterGrid(from: "JN\u{06F1}\u{06F1}") != nil
              && TransmitIdentity.ft8Locator("JN\u{06F1}\u{06F1}") == nil && TransmitIdentity.locator("JN\u{06F1}\u{06F1}") == nil)
        check("an empty locator is \"not set\" and the message says to set it",
              TransmitIdentity.locatorRefusal("") == TransmitIdentity.locatorMissingMessage
              && TransmitIdentity.locatorRefusal(nil) == TransmitIdentity.locatorMissingMessage
              && TransmitIdentity.locatorRefusal("  ") == TransmitIdentity.locatorMissingMessage)
        for value in ["----", "XX99", "JN1", "1234", "JN 11"] {
            check("\"\(value)\" is entered but not accepted: the message says so, not \"set your locator\"",
                  TransmitIdentity.locatorRefusal(value) == TransmitIdentity.locatorRejectedMessage)
        }
        check("a good locator has no refusal, whatever follows its square",
              TransmitIdentity.locatorRefusal("BL10") == nil && TransmitIdentity.locatorRefusal("FN54VH54") == nil
              && TransmitIdentity.locatorRefusal("DO21AL89PF") == nil && TransmitIdentity.locatorRefusal("LG89") == nil)
        check("the two locator messages differ and point to Settings > Stations",
              TransmitIdentity.locatorMissingMessage != TransmitIdentity.locatorRejectedMessage
              && TransmitIdentity.locatorMissingMessage.contains("Settings > Stations")
              && TransmitIdentity.locatorRejectedMessage.contains("Settings > Stations"))
    }

    // MARK: - FT8 / FT4 identity

    static func ft8Identity() {
        check("empty callsign and empty locator: refused, and the callsign comes first",
              TransmitIdentity.refusal(callsign: "", grid: "") == missing)
        check("first-run profile NOCALL with no locator: \"set your callsign\"",
              TransmitIdentity.refusal(callsign: "NOCALL", grid: "") == missing)
        check("a callsign without a locator: the message asks for the locator",
              TransmitIdentity.refusal(callsign: "0L1ABC", grid: "") == TransmitIdentity.locatorMissingMessage)
        check("a callsign with a locator that is not one: the message says it is not accepted",
              TransmitIdentity.refusal(callsign: "0L1ABC", grid: "----") == TransmitIdentity.locatorRejectedMessage)
        check("a locator without a callsign: the message asks for the callsign",
              TransmitIdentity.refusal(callsign: "", grid: "JO31") == missing)
        check("a callsign that is not accepted, with a locator: the message says it is not accepted",
              TransmitIdentity.refusal(callsign: "0L1ABC-1", grid: "JO31") == rejected)
        check("no default is substituted: a missing locator is not completed with another one",
              TransmitIdentity.refusal(callsign: "0L1ABC", grid: nil) != nil && TransmitIdentity.refusal(callsign: "0L1ABC", grid: "") != nil)
        check("a callsign and a locator: allowed, also with a longer locator",
              TransmitIdentity.refusal(callsign: "EA3JIC", grid: "BL10") == nil && TransmitIdentity.refusal(callsign: "EP2AES", grid: "LG89") == nil
              && TransmitIdentity.refusal(callsign: "EA3JIC", grid: "FN54VH54") == nil
              && TransmitIdentity.refusal(callsign: "EP2AES", grid: "DO21AL89PF") == nil)

        // The message builder shared by Wait and Pounce and the roster: only the operator's own values appear in it.
        check("a grid message is built from the operator's callsign and four-character locator",
              TransmitIdentity.gridMessage(to: "01abc", callsign: "ea3jic", grid: "bl10") == "01ABC EA3JIC BL10"
              && TransmitIdentity.gridMessage(to: " 01AW ", callsign: "EP2AES", grid: "LG89") == "01AW EP2AES LG89"
              && TransmitIdentity.gridMessage(to: "01ABC", callsign: "ea3jic", grid: "fn54vh") == "01ABC EA3JIC FN54"
              && TransmitIdentity.gridMessage(to: "01ABC", callsign: "EP2AES", grid: "DO21AL89PF") == "01ABC EP2AES DO21")
        let unusable: [(String?, String?)] = [(nil, "JO31"), ("", "JO31"), ("DEFAULT", "JO31"), ("NOCALL", "JO31"), ("N0CALL", "JO31"),
                                              ("0L1ABC-1", "JO31"), ("0L1ABC", nil), ("0L1ABC", ""), ("0L1ABC", "----"), ("0L1ABC", "JO3"), ("0L1ABC", "XX99")]
        for (call, grid) in unusable {
            check("no grid message for callsign \(call.map { "\"\($0)\"" } ?? "nil") and locator \(grid.map { "\"\($0)\"" } ?? "nil")",
                  TransmitIdentity.gridMessage(to: "01ABC", callsign: call, grid: grid) == nil)
        }
        check("no grid message without a station to address", TransmitIdentity.gridMessage(to: "  ", callsign: "0L1ABC", grid: "JO31") == nil)
    }

    // MARK: - FT8 / FT4 text about to be keyed

    static func ft8Messages() {
        // Each operator has a locator of its own; the callsign and the locator of another station (0L1ABC at JO31) are refused.
        let operators: [(call: String, grid: String, other: String, otherGrid: String)] = [
            ("EA3JIC", "BL10", "0L1ABC", "JO31"),
            ("EP2AES", "LG89", "0L1ABC", "JO31")
        ]
        for op in operators {
            func refusal(_ text: String) -> String? { TransmitIdentity.ft8MessageRefusal(text, callsign: op.call, grid: op.grid) }
            let allowed = [
                // standard messages from the operator
                "CQ \(op.call) \(op.grid)", "CQ DX \(op.call) \(op.grid)", "CQ TEST \(op.call) \(op.grid)", "CQ POTA \(op.call) \(op.grid)",
                "CQ 123 \(op.call) \(op.grid)", "CQ \(op.call)", "QRZ \(op.call) \(op.grid)",
                "01ABC \(op.call) \(op.grid)", "01ABC \(op.call)", "01ABC \(op.call) -10", "01ABC \(op.call) +05",
                "01ABC \(op.call) R-10", "01ABC \(op.call) RR73", "01ABC \(op.call) RRR", "01ABC \(op.call) 73",
                "01ABC \(op.call) R \(op.grid)", "01ABC \(op.call) 001", "01abc \(op.call.lowercased()) rr73",
                "  01ABC   \(op.call)  \(op.grid)  ", "<01ABC> \(op.call) -10", "01ABC <\(op.call)> -10", "01ABC <\(op.call)> RR73",
                // free text carries no sender: the station identity is set, so it goes out
                "TNX 73 GL", "73 GL", "GL DX 73", "HELLO WORLD", "TEST", "CQ", "TNX FOR QSO", "01ABC 73", "CQ GL"
            ]
            for text in allowed {
                check("\(op.call): \"\(text)\" is allowed", refusal(text) == nil)
            }
            let refused: [(String, String, String)] = [
                ("CQ \(op.other) \(op.otherGrid)", "another callsign as sender", TransmitIdentity.notYourCallsignText),
                ("CQ \(op.other) \(op.grid)", "another callsign with the operator's locator", TransmitIdentity.notYourCallsignText),
                ("01ABC \(op.other) -10", "another callsign in a report", TransmitIdentity.notYourCallsignText),
                ("\(op.call) 01ABC -10", "the operator as addressee, not as sender", TransmitIdentity.notYourCallsignText),
                ("CQ DX \(op.other) \(op.otherGrid)", "another callsign after a CQ modifier", TransmitIdentity.notYourCallsignText),
                ("01ABC <\(op.other)> -10", "another callsign in the hashed form", TransmitIdentity.notYourCallsignText),
                ("01ABC <...> -10", "an unresolved hashed sender", TransmitIdentity.notYourCallsignText),
                ("CQ DEFAULT \(op.grid)", "the DEFAULT placeholder", TransmitIdentity.notYourCallsignText),
                ("CQ NOCALL \(op.grid)", "the NOCALL placeholder", TransmitIdentity.notYourCallsignText),
                ("N0CALL TEST", "a placeholder in free text", TransmitIdentity.notYourCallsignText),
                ("TNX DEFAULT 73", "a placeholder inside free text", TransmitIdentity.notYourCallsignText),
                ("CQ  \(op.grid)", "a locator where the callsign should be", TransmitIdentity.notYourCallsignText),
                ("CQ \(op.call) \(op.otherGrid)", "another station's locator", TransmitIdentity.notYourLocatorText),
                ("01ABC \(op.call) \(op.otherGrid)", "another station's locator in a reply", TransmitIdentity.notYourLocatorText),
                ("01ABC \(op.call) R \(op.otherGrid)", "another station's locator in a contest reply", TransmitIdentity.notYourLocatorText),
                ("", "an empty message", TransmitIdentity.noMessageText),
                ("   ", "a blank message", TransmitIdentity.noMessageText)
            ]
            for (text, why, message) in refused {
                check("\(op.call): \"\(text)\" is refused (\(why)) with the matching message", refusal(text) == message)
            }
        }
        check("a message is refused while the callsign or the locator is not set or not accepted, free text too",
              TransmitIdentity.ft8MessageRefusal("CQ 0L1ABC JO31", callsign: "", grid: "JO31") == missing
              && TransmitIdentity.ft8MessageRefusal("CQ 0L1ABC JO31", callsign: "0L1ABC", grid: "") == TransmitIdentity.locatorMissingMessage
              && TransmitIdentity.ft8MessageRefusal("CQ 0L1ABC JO31", callsign: "NOCALL", grid: "JO31") == missing
              && TransmitIdentity.ft8MessageRefusal("TNX 73 GL", callsign: "", grid: "JO31") == missing
              && TransmitIdentity.ft8MessageRefusal("TNX 73 GL", callsign: "0L1ABC-1", grid: "JO31") == rejected
              && TransmitIdentity.ft8MessageRefusal("TNX 73 GL", callsign: "0L1ABC", grid: "----") == TransmitIdentity.locatorRejectedMessage)
        check("a longer locator in the profile is matched on its first four characters",
              TransmitIdentity.ft8MessageRefusal("CQ EA3JIC FN54", callsign: "EA3JIC", grid: "FN54VH54") == nil
              && TransmitIdentity.ft8MessageRefusal("CQ EA3JIC FN54VH", callsign: "EA3JIC", grid: "FN54VH54") == nil
              && TransmitIdentity.ft8MessageRefusal("CQ EP2AES DO21", callsign: "EP2AES", grid: "DO21AL89PF") == nil)
    }

    nonisolated private static func offMainActor() -> Bool {
        TransmitIdentity.isValidCallsign("EA3JIC")
            && TransmitIdentity.refusal(callsign: "EP2AES", grid: "LG89") == nil
            && TransmitIdentity.callsignRefusal("") != nil
            && TransmitIdentity.ft8MessageRefusal("CQ EP2AES LG89", callsign: "EP2AES", grid: "LG89") == nil
    }

    // MARK: - The saved callsign, for screens that do not hold the app state

    static func savedValues() {
        let suite = "TransmitIdentityRegression.\(ProcessInfo.processInfo.processIdentifier)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            check("a UserDefaults suite could be opened", false)
            return
        }
        defaults.removePersistentDomain(forName: suite)
        check("nothing saved: no callsign, no locator, and the saved callsign is \"not set\"",
              TransmitIdentity.savedOperatorCallsign(defaults: defaults) == nil && TransmitIdentity.savedOperatorLocator(defaults: defaults) == nil
              && TransmitIdentity.savedEnteredCallsign(defaults: defaults).isEmpty
              && TransmitIdentity.savedCallsignRefusal(defaults: defaults) == missing)
        defaults.set("NOCALL", forKey: "operatorCallsign")
        defaults.set("NOCALL", forKey: "stationCallsign")
        check("the first-run value NOCALL is not a callsign", TransmitIdentity.savedOperatorCallsign(defaults: defaults) == nil
              && TransmitIdentity.savedCallsignRefusal(defaults: defaults) == missing)
        defaults.set("ea3jic ", forKey: "operatorCallsign")
        defaults.set("fn54vh", forKey: "stationGrid")
        check("a saved callsign and locator are normalised",
              TransmitIdentity.savedOperatorCallsign(defaults: defaults) == "EA3JIC" && TransmitIdentity.savedOperatorLocator(defaults: defaults) == "FN54VH"
              && TransmitIdentity.savedCallsignRefusal(defaults: defaults) == nil)
        defaults.set("DEFAULT", forKey: "operatorCallsign")
        defaults.set("EP2AES", forKey: "stationCallsign")
        check("the second saved key is used when the first one is a placeholder", TransmitIdentity.savedOperatorCallsign(defaults: defaults) == "EP2AES")
        defaults.set("0L1ABC-1", forKey: "operatorCallsign")
        check("a saved callsign that is not accepted is kept as entered, so the message says it is not accepted",
              TransmitIdentity.savedOperatorCallsign(defaults: defaults) == nil
              && TransmitIdentity.savedEnteredCallsign(defaults: defaults) == "0L1ABC-1"
              && TransmitIdentity.savedCallsignRefusal(defaults: defaults) == rejected)
        defaults.set("----", forKey: "stationGrid")
        check("a saved locator that is not a locator is ignored", TransmitIdentity.savedOperatorLocator(defaults: defaults) == nil)
        defaults.set("DO21AL89", forKey: "stationGrid")
        check("a saved locator of eight characters is kept whole", TransmitIdentity.savedOperatorLocator(defaults: defaults) == "DO21AL89")
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: - The note on the Stations screen after a save

    static func stationsScreenNote() {
        check("a profile that will transmit has no note",
              TransmitIdentity.stationNote(callsign: "EA3JIC", grid: "BL10") == nil && TransmitIdentity.stationNote(callsign: "EP2AES", grid: "DO21AL") == nil)
        check("a profile for logging only (no locator, first-run callsign) has no note",
              TransmitIdentity.stationNote(callsign: "NOCALL", grid: "") == nil && TransmitIdentity.stationNote(callsign: "EA3JIC", grid: "") == nil)
        check("a callsign that is entered but not accepted is reported",
              TransmitIdentity.stationNote(callsign: "0L1ABC-1", grid: "JO31") == rejected)
        check("a locator that is entered but not accepted is reported",
              TransmitIdentity.stationNote(callsign: "0L1ABC", grid: "----") == TransmitIdentity.locatorRejectedMessage)
        check("both are reported together",
              TransmitIdentity.stationNote(callsign: "0L1ABC-1", grid: "----") == rejected + " " + TransmitIdentity.locatorRejectedMessage)
        // The line under the form, after "Save" and after "Save and activate".
        let saved = "Saved securely."
        let activated = "Saved and activated. The Master Log now shows this station."
        check("a profile that will transmit: the line is the plain text, shown in green",
              TransmitIdentity.stationStatus(saved, callsign: "EA3JIC", grid: "BL10") == saved
              && TransmitIdentity.stationStatus(activated, callsign: "EP2AES", grid: "LG89") == activated
              && TransmitIdentity.isPlainSavedStatus(saved) && TransmitIdentity.isPlainSavedStatus(activated))
        check("after Save, a callsign that is not accepted is added to the line, which is then not shown in green",
              TransmitIdentity.stationStatus(saved, callsign: "0L1ABC-1", grid: "JO31") == saved + " " + rejected
              && !TransmitIdentity.isPlainSavedStatus(TransmitIdentity.stationStatus(saved, callsign: "0L1ABC-1", grid: "JO31")))
        check("after Save and activate, the same note is added after \"Saved and activated\", and the line is not shown in green",
              TransmitIdentity.stationStatus(activated, callsign: "0L1ABC-1", grid: "----") == activated + " " + rejected + " " + TransmitIdentity.locatorRejectedMessage
              && !TransmitIdentity.isPlainSavedStatus(TransmitIdentity.stationStatus(activated, callsign: "0L1ABC-1", grid: "----")))
        check("an error or a hint is never shown in green",
              !TransmitIdentity.isPlainSavedStatus("Enter a unique name and the operating callsign, then save.")
              && !TransmitIdentity.isPlainSavedStatus(""))
        let view = sourceText("YAAM/StationProfilesSettingsView.swift") ?? ""
        check("the Stations screen builds the line of Save and of Save and activate with stationStatus, and still saves",
              view.contains("TransmitIdentity.stationStatus(\"Saved securely.\", callsign: draft.callsign, grid: draft.grid)")
              && view.contains("TransmitIdentity.stationStatus(\"Saved and activated. The Master Log now shows this station.\",")
              && view.contains("callsign: profile.callsign, grid: profile.grid)"))
        check("the Stations screen colours the line with isPlainSavedStatus, not with the first word, and has room for three lines of it",
              view.components(separatedBy: "TransmitIdentity.isPlainSavedStatus(statusMessage)").count - 1 == 2 && !view.contains("statusMessage.hasPrefix(\"Saved\")")
              && view.contains("Text(statusMessage)\n                        .lineLimit(3)"))
        check("saving a profile is not blocked by the transmit rules",
              !(sourceText("YAAM/StationProfile.swift") ?? "").contains("TransmitIdentity"))
    }

    // MARK: - Where the checks are (source text, pinned)

    static func sidetoneAndKeyer() {
        let keyer = "YAAM/CWKeyerService.swift"
        check("every way into the keyer asks one function, which exempts only Audio Sidetone Only",
              statements(functionBody("public func refusalReason(", in: keyer)) == [
                "if transmissionMode == .audioOnly { return nil }", "return TransmitIdentity.callsignRefusal(myCall)"])
        let issue = "if let issue = refusalReason(myCall: myCall) {"
        check("CWKeyerService.send: refuses with the reason and returns, before it stops or starts anything",
              refusalBlock(issue, equals: ["transmitRefusal = issue", "return"], before: "stopTransmitOnly()",
                           in: functionBody("public func send(", in: keyer)))
        check("CWKeyerService.send: a send that goes out clears the refusal",
              functionBody("public func send(", in: keyer)?.contains("transmitRefusal = \"\"\n\n        stopTransmitOnly()") == true)
        check("Auto-CQ: refuses with the reason and returns, before it starts its loop",
              refusalBlock(issue, equals: ["transmitRefusal = issue", "return"], before: "isAutoCQActive = true",
                           in: functionBody("public func startAutoCQ(", in: keyer)))
        let sendCalls = (sourceText(keyer) ?? "").components(separatedBy: "self.send(").count - 1
        check("Auto-CQ sends through the same send function (\(sendCalls) call)", sendCalls == 1)
        check("the decoder's reply passes the profile's callsign, or nothing",
              sourceText("YAAM/CWDecoderView.swift")?.contains("sendSuggestedReply(myCall: appState.activeStationProfile?.normalizedCallsign ?? \"\")") == true)
        let view = sourceText("YAAM/CWKeyerView.swift") ?? ""
        check("the CW keyer screen passes the profile's callsign or nothing, and the quick-log callsign as the station worked",
              view.contains("appState.activeStationProfile?.normalizedCallsign ?? \"\"") && !view.contains("?? \"EP2AES\"")
              && view.contains("call: appState.quickLogDraft.callsign,"))
    }

    static func contestAndEsm() {
        let esm = "YAAM/ContestESMEngine.swift"
        check("ContestESMEngine.executeMacro: asks the keyer, refuses with the reason and returns false, before it sends",
              refusalBlock("if let issue = CWKeyerService.shared.refusalReason(myCall: myCall) {",
                           equals: ["transmitRefusal = issue", "statusMessage = issue", "return false"],
                           before: "CWKeyerService.shared.send(", in: functionBody("public func executeMacro(", in: esm)))
        check("ContestESMEngine.executeMacro: sends with the callsign it checked",
              functionBody("public func executeMacro(", in: esm)?.contains("CWKeyerService.shared.send(text: text, myCall: myCall)") == true
              && functionBody("public func executeMacro(", in: esm)?.contains("let myCall = TransmitIdentity.normalized(myCallsign)") == true)
        let enter = functionBody("public func handleEnterPressed(", in: esm) ?? ""
        let macroCalls = enter.components(separatedBy: "executeMacro(").count - 1
        let guarded = enter.components(separatedBy: "guard executeMacro(").count - 1
        let stopped = enter.components(separatedBy: ") else { return }").count - 1
        check("Enter: each of the six branches that key sits behind a guard that returns (\(guarded) of \(macroCalls))",
              macroCalls == 6 && guarded == 6 && stopped == 6)
        check("Enter: with ESM off it only logs, before any check; \"Ready to log\" has no guard",
              before("guard isESMEnabled else {", "evaluateState(", in: enter) && enter.contains("_ = onLogQSO()\n            return")
              && (enter.components(separatedBy: "case .spLogReady:").last.map { $0.contains("onLogQSO()") && !$0.contains("executeMacro") } == true))
        check("Enter: a branch is stopped before it changes the state or logs",
              enter.contains("guard executeMacro(f3TU, call: callsign, sentExch: sentExchange, rcvdExch: rcvdExchange) else { return }\n            let logged = onLogQSO()")
              && enter.contains("guard executeMacro(f5HisCallTU, call: callsign, sentExch: sentExchange, rcvdExch: rcvdExchange) else { return }\n            let logged = onLogQSO()")
              && enter.contains("else { return }\n            currentState = .spLogReady"))
        check("the function keys reach the same function (executeMacro), whose result the buttons may ignore",
              sourceText("YAAM/ContestESMControlView.swift")?.contains("esm.executeMacro(macro, call: inputCall, sentExch: inputSentExchange, rcvdExch: inputRcvdExchange)") == true
              && sourceText(esm)?.contains("@discardableResult\n    public func executeMacro(") == true)
        check("the engine has no built-in callsign and takes the profile's through setStationCallsign",
              sourceText(esm)?.contains("@Published public var myCallsign: String = \"\"") == true
              && statements(functionBody("public func setStationCallsign(", in: esm)) == [
                "myCallsign = TransmitIdentity.enteredCallsign(callsign)", "transmitRefusal = \"\""])

        let panel = sourceText("YAAM/RadioContestViews.swift") ?? ""
        check("the contest screen gives the engine the profile's callsign when it appears and when the profile changes, and on every Enter",
              panel.contains("hydrateDraft()\n            syncESMStation()")
              && panel.contains(".onChange(of: appState.activeStationProfile) { _, _ in\n            syncESMStation()")
              && statements(functionBody("private func triggerESM(", in: "YAAM/RadioContestViews.swift")).first == "syncESMStation()"
              && statements(functionBody("private func syncESMStation(", in: "YAAM/RadioContestViews.swift")) == [
                "ContestESMEngine.shared.setStationCallsign(appState.activeStationProfile?.normalizedCallsign)"])

        let cwesm = "YAAM/CWESMEngine.swift"
        let action = functionBody("func executeAction(", in: cwesm) ?? ""
        check("the quick-log ESM actions pass the profile's callsign, or nothing",
              action.contains("let myCall = appState.activeStationProfile?.normalizedCallsign ?? \"\""))
        check("mayKey asks the keyer, shows the reason on the quick-log screen and says no",
              statements(functionBody("func mayKey(", in: cwesm)) == [
                "guard let issue = keyer.refusalReason(myCall: myCall) else { return true }",
                "lastExecutedActionDescription = issue", "appState.quickLogStatus = issue", "return false"])
        var keyingCases = 0
        for name in [".sendCQ(let template):", ".sendExchange(let call, let template):", ".sendTUAndLog(let template):",
                     ".sendMyCall(let template):", ".sendMyExchangeAndLog(let template):"] {
            if action.contains("case \(name)\n            guard mayKey() else { return }\n            transmit(template)\n") { keyingCases += 1 }
        }
        check("the quick-log ESM actions: each of the five that key asks mayKey before it sends (\(keyingCases) of 5)", keyingCases == 5)
        check("the quick-log ESM actions: prompting for a callsign keys nothing and has no check",
              action.contains("case .promptCallsign:\n            appState.quickLogStatus = \"Type Callsign first for S&P\"")
              && action.components(separatedBy: "guard mayKey() else { return }").count - 1 == 5)
        check("the quick-log screen shows quickLogStatus",
              sourceText("YAAM/OperatorDeskView.swift")?.contains("Text(appState.quickLogStatus)") == true)
    }

    static func digitalModes() {
        let dm = "YAAM/DigitalModemEngine.swift"
        let issue = "if let issue = TransmitIdentity.callsignRefusal(myCallsign) {"
        check("RTTY/PSK queue: refuses with the reason and returns, before it buffers the text or starts",
              refusalBlock(issue, equals: ["txRefusal = issue", "return"], before: "txBufferText += text",
                           in: functionBody("public func queueTextForTransmission(", in: dm)))
        check("RTTY/PSK start: refuses with the reason and returns, before it keys the PTT",
              refusalBlock(issue, equals: ["txRefusal = issue", "return"], before: "RigControlEngine.shared.setPTT(true)",
                           in: functionBody("public func startTransmission(", in: dm)))
        check("RTTY/PSK start: the refusal comes before the transmission state is set",
              before(issue, "isTransmitting = true", in: functionBody("public func startTransmission(", in: dm)))
        check("RTTY/PSK macros take the callsign and the locator from the engine, with no built-in value",
              functionBody("public func expandMacroTemplate(", in: dm).map {
                  $0.contains("with: TransmitIdentity.usableCallsign(myCallsign) ?? \"\")") && $0.contains("with: TransmitIdentity.locator(myGrid) ?? \"\")")
                  && !$0.contains("EP2YAAM") && !$0.contains("LL35")
              } == true)
        let station = sourceText("YAAM/DigitalModemStationView.swift") ?? ""
        check("the RTTY/PSK screen copies the profile's callsign and locator, and clears the refusal, when it appears and when the profile changes",
              statements(functionBody("private func syncStationInfo(", in: "YAAM/DigitalModemStationView.swift")) == [
                "engine.myCallsign = TransmitIdentity.enteredCallsign(appState.activeStationProfile?.callsign)",
                "engine.myGrid = TransmitIdentity.locator(appState.activeStationProfile?.grid) ?? \"\"",
                "engine.txRefusal = \"\""]
              && station.contains(".onChange(of: appState.activeStationProfile) { _, _ in\n            syncStationInfo()") && station.contains("Text(engine.txRefusal)"))
        for (file, view) in [("YAAM/HellschreiberEngine.swift", "YAAM/HellschreiberView.swift"), ("YAAM/OliviaMFSKEngine.swift", "YAAM/OliviaMFSKView.swift")] {
            check("\(file): the callsign is the saved one, with no built-in value",
                  sourceText(file)?.contains("public var myCallsign: String { TransmitIdentity.savedEnteredCallsign() }") == true)
            check("\(file): the queue refuses with the reason and returns, before it buffers the text",
                  refusalBlock(issue, equals: ["txRefusal = issue", "return"], before: "txBufferText += text",
                               in: functionBody("public func queueTextForTransmission(", in: file)))
            check("\(file): the start refuses with the reason and returns, before it sets the transmission state",
                  refusalBlock(issue, equals: ["txRefusal = issue", "return"], before: "isTransmitting = true",
                               in: functionBody("public func startTransmission(", in: file)))
            check("\(view): shows the refusal and clears it when the profile changes",
                  sourceText(view)?.contains("Text(engine.txRefusal)") == true
                  && sourceText(view)?.contains("publisher(for: TransmitIdentity.identityChanged)) { _ in") == true
                  && sourceText(view)?.contains("engine.txRefusal = \"\"") == true)
        }
        check("the Hellschreiber macros read the callsign when they are pressed, not when the screen is drawn",
              sourceText("YAAM/HellschreiberView.swift")?.contains("text: @autoclosure @escaping () -> String") == true)
    }

    static func ft8Gates() {
        let ft8 = "YAAM/FT8EngineService.swift"
        let schedule = functionBody("func scheduleTransmission(", in: ft8)
        check("FT8 scheduleTransmission: the identity check returns before any audio is made or the PTT is keyed",
              schedule?.contains("guard validateIdentity() else { return }") == true
              && before("guard validateIdentity() else { return }", "FT8Codec.transmitAudio(", in: schedule)
              && before("guard validateIdentity() else { return }", "setPTT(true", in: schedule))
        check("FT8 scheduleTransmission: a message from another callsign or locator is refused and returns, before any audio",
              refusalBlock("if let issue = TransmitIdentity.ft8MessageRefusal(message, callsign: myCall, grid: myGrid) {",
                           equals: ["fail(issue)", "return"], before: "FT8Codec.transmitAudio(", in: schedule)
              && before("TransmitIdentity.ft8MessageRefusal(", "setPTT(true", in: schedule))
        check("FT8 validateIdentity: the whole check is the shared one",
              statements(functionBody("private func validateIdentity(", in: ft8)) == [
                "if let issue = TransmitIdentity.refusal(callsign: myCall, grid: myGrid) {", "fail(issue)", "return false", "}", "return true"])
        check("FT8 generateStandardMessage: prepares nothing without an identity, and has no placeholder locator",
              functionBody("func generateStandardMessage(", in: ft8).map {
                  $0.contains("guard TransmitIdentity.refusal(callsign: myCall, grid: myGrid) == nil else { return \"\" }") && !$0.contains("\"----\"")
              } == true)
        check("FT8 configureStation keeps only the callsign as entered and the valid square",
              functionBody("func configureStation(", in: ft8).map {
                  $0.contains("let enteredCall = TransmitIdentity.enteredCallsign(callsign)")
                  && $0.contains("myCall = enteredCall")
                  && $0.contains("myGrid = TransmitIdentity.ft8Locator(grid) ?? String(TransmitIdentity.normalized(grid).prefix(4))")
              } == true)
        check("FT8 configureStation: an identity refusal of the previous identity is cleared, any other failure is kept",
              functionBody("func configureStation(", in: ft8).map {
                  $0.contains("if case .failed(let message) = state, TransmitIdentity.isIdentityRefusal(message) {")
                  && $0.contains("state = decodeTask == nil ? .idle : .monitoring")
              } == true)
        check("the FT8 screen loads the identity again when the active profile is edited, not only when another is chosen",
              sourceText("YAAM/FT8StationView.swift")?.contains(".onChange(of: appState.activeStationProfile) { _, _ in loadIdentity() }") == true)
        check("FT8 directedGridMessage: the builder for replies refuses and builds from the shared builder",
              statements(functionBody("func directedGridMessage(", in: ft8)) == [
                "if let issue = TransmitIdentity.refusal(callsign: myCall, grid: myGrid) {", "fail(issue)", "return nil", "}",
                "return TransmitIdentity.gridMessage(to: dx, callsign: myCall, grid: myGrid)"])
        let pounce = sourceText("YAAM/AppStateRadioContestFeatures.swift") ?? ""
        let roster = sourceText("YAAM/DigitalCallRosterView.swift") ?? ""
        check("the roster configures the engine from the profile, and shows why a reply was not prepared, until the profile changes",
              roster.contains("appState.ft8Engine.configureStation(\n                        callsign: appState.currentStationCallsign,")
              && roster.contains("replyNotice = TransmitIdentity.refusal(callsign: appState.ft8Engine.myCall, grid: appState.ft8Engine.myGrid)")
              && roster.contains("Text(replyNotice)")
              && roster.contains("publisher(for: TransmitIdentity.identityChanged)) { _ in\n            // A refusal shown for the previous profile no longer applies.\n            replyNotice = \"\""))
        check("Wait and Pounce builds its message from the engine's own callsign and locator",
              pounce.contains("let text = self.ft8Engine.directedGridMessage(to: call)")
              && !pounce.contains("\\(self.currentStationCallsign) \\(self.activeStationProfile?.grid"))
        check("the roster builds its message from the engine's own callsign and locator",
              roster.contains("let text = appState.ft8Engine.directedGridMessage(to: entry.callsign)")
              && !roster.contains("\\(appState.currentStationCallsign) \\(appState.activeStationProfile?.grid"))
    }

    static func testButtonsAndChat() {
        let sheet = sourceText("YAAM/CWHardwareSetupSheet.swift") ?? ""
        check("the four hardware test texts go through sendIdentifiedTest",
              sheet.components(separatedBy: "sendIdentifiedTest {").count - 1 == 4 && !sheet.contains("TEST YAAM DE") && !sheet.contains("\"EP2AES\""))
        check("sendIdentifiedTest: refuses with the reason and returns, before it sends",
              refusalBlock("guard let call = TransmitIdentity.savedOperatorCallsign() else {",
                           equals: ["testNotice = TransmitIdentity.savedCallsignRefusal() ?? TransmitIdentity.callsignMissingMessage", "return"],
                           before: "transmit(\"TEST DE \\(call)\")", in: functionBody("private func sendIdentifiedTest(", in: "YAAM/CWHardwareSetupSheet.swift")))
        check("TX-500 test: refuses with the reason and returns, before it sends",
              refusalBlock("guard let call = TransmitIdentity.savedOperatorCallsign() else {",
                           equals: ["testCWNotice = TransmitIdentity.savedCallsignRefusal() ?? TransmitIdentity.callsignMissingMessage", "return"],
                           before: "tx500.sendMorse(", in: functionBody("private func testCWSend(", in: "YAAM/Lab599TX500SetupView.swift")))
        check("X6100 test: refuses with the reason and returns, before it sends",
              refusalBlock("guard let call = TransmitIdentity.savedOperatorCallsign() else {",
                           equals: ["testCWNotice = TransmitIdentity.savedCallsignRefusal() ?? TransmitIdentity.callsignMissingMessage", "return"],
                           before: "xiegu.sendMorse(", in: functionBody("// CW Test", in: "YAAM/Xiegu6100SetupView.swift")))
        check("WinKeyer test: refuses with the reason and returns, before it sends; the field starts empty",
              refusalBlock("if let issue = TransmitIdentity.savedCallsignRefusal() {", equals: ["testNotice = issue", "return"],
                           before: "wk.sendMorseText(", in: functionBody("private func sendTest(", in: "YAAM/WinKeyerView.swift"))
              && sourceText("YAAM/WinKeyerView.swift")?.contains("var testInput: String = \"\"") == true)
        for file in ["YAAM/CWHardwareSetupSheet.swift", "YAAM/Lab599TX500SetupView.swift", "YAAM/Xiegu6100SetupView.swift", "YAAM/WinKeyerView.swift"] {
            check("\(file) clears its test refusal when the profile changes",
                  sourceText(file)?.contains("publisher(for: TransmitIdentity.identityChanged)) { _ in") == true)
        }
        let kst = "YAAM/ON4KSTClient.swift"
        check("ON4KST login: a placeholder is refused with the reason and returns; the callsign that logged in is remembered",
              refusalBlock("guard !TransmitIdentity.isPlaceholderCallsign(cleanCall) else {",
                           equals: ["self.statusMessage = TransmitIdentity.callsignMissingMessage", "return"],
                           before: "self.myCallsign = cleanCall", in: functionBody("public func connect(", in: kst)))
        check("ON4KST CQ: refuses with the reason and returns before it builds the post; the locator is added only when valid",
              refusalBlock("guard !TransmitIdentity.isPlaceholderCallsign(myCallsign) else {",
                           equals: ["statusMessage = TransmitIdentity.callsignMissingMessage", "return"],
                           before: "var text = ", in: functionBody("public func sendCQ(", in: kst))
              && functionBody("public func sendCQ(", in: kst)?.contains("if let grid = TransmitIdentity.locator(myGrid) { text += \" in \\(grid)\" }") == true
              && sourceText(kst)?.contains("var myCallsign: String = \"\"") == true && sourceText(kst)?.contains("var myGrid: String = \"\"") == true)
    }

    static func refusalsAreShown() {
        check("the refusal of the CW keyer is shown on the keyer screen and next to the decoder's reply button",
              sourceText("YAAM/CWKeyerView.swift")?.contains("Text(keyer.transmitRefusal)") == true
              && sourceText("YAAM/CWDecoderView.swift")?.contains("Text(keyer.transmitRefusal)") == true)
        check("the refusal of the contest keys is shown in the ESM ribbon of the contest screen",
              sourceText("YAAM/ContestESMControlView.swift")?.contains("Text(esm.transmitRefusal)") == true)
        check("the CW keyer screen clears its refusal when the profile changes",
              sourceText("YAAM/CWKeyerView.swift")?.contains("keyer.transmitRefusal = \"\"") == true
              && sourceText("YAAM/CWKeyerView.swift")?.contains(".onChange(of: appState.activeStationProfile) { _, _ in") == true)
        check("saving or switching the active profile tells the screens",
              sourceText("YAAM/AppStatePersistence.swift")?.contains("NotificationCenter.default.post(name: TransmitIdentity.identityChanged, object: nil)") == true)
        check("saving or switching the active profile takes a refusal off the quick-log status line, and nothing else",
              sourceText("YAAM/AppStatePersistence.swift")?.contains("if TransmitIdentity.isIdentityRefusal(quickLogStatus) { quickLogStatus = \"Ready\" }\n        NotificationCenter.default.post(name: TransmitIdentity.identityChanged") == true)
    }

    /// Every place that keys a transmitter or sends Morse is known. A new one has to be gated and added here.
    static func knownKeyingSites() {
        let ptt = filesMatching("setPTT\\((true|!)")
        let pttGated = ["DigitalModemEngine.swift", "FT8EngineService.swift"]
        let pttCarrierOnly = ["Lab599TX500SetupView.swift", "TCIControlView.swift", "Xiegu6100SetupView.swift"]
        check("PTT is keyed only in the known files \(ptt)", ptt == (pttGated + pttCarrierOnly).sorted())
        let morse = filesMatching("\\.(sendMorse|sendMorseText|sendCW)\\(")
        let morseGated = ["CWHardwareSetupSheet.swift", "CWKeyerService.swift", "Lab599TX500SetupView.swift",
                          "WinKeyerView.swift", "Xiegu6100SetupView.swift"]
        check("Morse is sent only from the known files \(morse)", morse == morseGated.sorted())
    }

    // MARK: - Source-text helpers (same approach as WebSDRReplyGuardRegression.swift)

    /// A source file of the checkout, found from this file's location or the working directory.
    nonisolated private static func sourceText(_ path: String) -> String? {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let roots = [here, URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
        let text = roots.lazy.compactMap { try? String(contentsOf: $0.appendingPathComponent(path), encoding: .utf8) }.first
        if text == nil { print("cannot read \(path); run from the repository root") }
        return text
    }

    /// Every Swift source of the app, by file name.
    nonisolated private static func allSources() -> [String: String] {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let roots = [here, URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
        for root in roots {
            let dir = root.appendingPathComponent("YAAM")
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            var all: [String: String] = [:]
            for name in names where name.hasSuffix(".swift") {
                all[name] = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            }
            if !all.isEmpty { return all.compactMapValues { $0 } }
        }
        print("cannot list YAAM/; run from the repository root")
        return [:]
    }

    /// The names of the app's source files (not drivers or clients that define the call) with a line that matches.
    nonisolated private static func filesMatching(_ pattern: String) -> [String] {
        allSources().filter { name, text in
            guard !name.hasSuffix("Driver.swift"), !name.hasSuffix("Client.swift"), !name.hasPrefix("RigControl"),
                  !name.hasPrefix("IcomNetwork") else { return false }
            return text.split(separator: "\n").contains { line in
                var code = String(line)
                if let comment = code.range(of: "//") { code = String(code[..<comment.lowerBound]) }
                return code.range(of: pattern, options: .regularExpression) != nil
            }
        }.keys.sorted()
    }

    /// The text between the braces of the block that follows `marker` in a source file: a function
    /// body, a closure, or a button action. nil when the file or the marker is missing.
    /// Strings and // comments are skipped so their braces do not count.
    nonisolated private static func functionBody(_ marker: String, in path: String) -> String? {
        guard let text = sourceText(path), let start = text.range(of: marker) else { return nil }
        return braceBody(of: text, from: start.upperBound,
                         parens: marker.filter { $0 == "(" }.count - marker.filter { $0 == ")" }.count)
    }

    /// The text inside the first top-level braces at or after `from`, once the open parentheses are closed.
    nonisolated private static func braceBody(of text: String, from: String.Index, parens startParens: Int = 0) -> String? {
        var parens = startParens
        var braces = 0
        var bodyStart: String.Index?
        var index = from
        while index < text.endIndex {
            let ch = text[index]
            if ch == "\"" {
                index = text.index(after: index)
                while index < text.endIndex, text[index] != "\"" {
                    if text[index] == "\\" { index = text.index(after: index) }
                    if index < text.endIndex { index = text.index(after: index) }
                }
            } else if ch == "/", text[text.index(after: index)...].hasPrefix("/") {
                while index < text.endIndex, text[index] != "\n" { index = text.index(after: index) }
                continue
            } else if bodyStart == nil {
                if ch == "(" { parens += 1 }
                if ch == ")" { parens -= 1 }
                if ch == "{" && parens <= 0 {
                    bodyStart = text.index(after: index)
                    braces = 1
                }
            } else if ch == "{" {
                braces += 1
            } else if ch == "}" {
                braces -= 1
                if braces == 0, let first = bodyStart { return String(text[first..<index]) }
            }
            if index < text.endIndex { index = text.index(after: index) }
        }
        return nil
    }

    /// The statements of a block, one per line: trimmed, without blank lines and // comments.
    nonisolated private static func statements(_ block: String?) -> [String] {
        (block ?? "<missing>").split(separator: "\n").compactMap { line -> String? in
            var code = String(line)
            if let comment = code.range(of: "//") { code = String(code[..<comment.lowerBound]) }
            code = code.trimmingCharacters(in: .whitespaces)
            return code.isEmpty ? nil : code
        }
    }

    /// True when the refusal block that opens with `header` is in `body` exactly once, holds exactly the
    /// statements `expected` (the last one is the return that stops the send), and comes before the text
    /// `keying`, which is the call that keys the transmitter or the state that starts it.
    nonisolated private static func refusalBlock(_ header: String, equals expected: [String], before keying: String, in body: String?) -> Bool {
        guard let body, body.components(separatedBy: header).count == 2, let open = body.range(of: header),
              let block = braceBody(of: body, from: body.index(before: open.upperBound)),
              statements(block) == expected, expected.last?.hasPrefix("return") == true,
              let keyingAt = body.range(of: keying) else { return false }
        return open.lowerBound < keyingAt.lowerBound
    }

    /// True when both strings are in `body` and `first` comes before `second`.
    nonisolated private static func before(_ first: String, _ second: String, in body: String?) -> Bool {
        guard let body, let a = body.range(of: first), let b = body.range(of: second) else { return false }
        return a.lowerBound < b.lowerBound
    }
}
