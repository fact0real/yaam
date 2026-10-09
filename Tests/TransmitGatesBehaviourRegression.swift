import Foundation

// Behaviour test of the transmit checks. It runs the real CWKeyerService, ContestESMEngine and
// DigitalModemEngine against recording stand-ins for the radio drivers (Tests/Support/) and looks at what
// would be handed to the radio. A check that is still in the source but no longer works (a missing return,
// a condition that is always true) fails here; Tests/TransmitIdentityRegression.swift only reads the source.
//
// Build and run from the repository root. The sources assume the app's Swift settings, so pass them:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/TransmitGatesBehaviourRegression.swift Tests/Support/TransmitGateStubs.swift \
//       Tests/Support/TransmitGateDXCCStub.swift YAAM/CWKeyerService.swift YAAM/ContestESMEngine.swift \
//       YAAM/DigitalModemEngine.swift YAAM/TransmitIdentity.swift YAAM/GridLocator.swift -o tgb && ./tgb
// Nothing opens a port or a socket. The real audio engines may ask macOS for the microphone (33-ITEM.md).
// The operators in the checks are EA3JIC and EP2AES, with four-character island locators as if on holiday
// (BL10, Hawaii; LG89, Mauritius), not their home ones. The longer locators are those of a POTA activation,
// computed from the coordinates in the official POTA park list (pota.app, 08-10-2026): EA3JIC at US-0001 Acadia
// National Park (44.31, -68.2034): FN54VH54; EP2AES at CA-0005 Banff National Park (51.4968, -115.928): DO21AL89PF.
// Cases that must be refused or corrected use an invented station (0L1ABC).

private var failures = 0

private func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok {
        print("PASS \(name)")
    } else {
        let more = detail()
        print("FAIL \(name)\(more.isEmpty ? "" : "   [\(more)]")")
        failures += 1
    }
}

/// What reached the (stand-in) radio, as text for a failure message.
private func shown(_ handed: [String]) -> String {
    handed.isEmpty ? "nothing handed to the radio" : handed.joined(separator: " | ")
}

/// Lets the keyer's background task run, then returns what it handed to the (stand-in) radio.
@MainActor private func handedToRadio(_ seconds: Double = 0.25) -> [String] {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    return KeyLog.drain()
}

/// Presses a function key of the contest ribbon and returns what reached the (stand-in) radio.
@MainActor private func pressFunctionKey(_ esm: ContestESMEngine, _ template: String, call: String = "") -> [String] {
    esm.executeMacro(template, call: call, sentExch: "", rcvdExch: "")
    return handedToRadio()
}

@MainActor private func quiet(_ keyer: CWKeyerService) {
    keyer.stop()
    _ = handedToRadio(0.1)
}

@main
struct TransmitGatesBehaviourRegression {
    static let missing = TransmitIdentity.callsignMissingMessage
    static let rejected = TransmitIdentity.callsignRejectedMessage
    /// A callsign that ends in a digit follows the switch in TransmitIdentity, whatever its value is.
    static let digitEndingAccepted = TransmitIdentity.acceptsCallsignsEndingInDigit

    static func main() {
        let keyer = CWKeyerService.shared
        keyer.transmissionMode = .lab599TX500
        keyer.sidetoneEnabled = false
        keyer.useCutNumbers = false
        Lab599TX500Driver.shared.isConnected = true

        cwKeyer(keyer)
        autoCQ(keyer)
        sidetoneOnly(keyer)
        contestFunctionKeys(keyer)
        contestEnterKey(keyer)
        digitalModem()

        if failures > 0 {
            print("Transmit gates behaviour regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Transmit gates behaviour regression passed")
    }

    // MARK: - CW keyer: the point every macro, live text, Enter key and reply reaches

    static func cwKeyer(_ keyer: CWKeyerService) {
        let cq = "CQ TEST {MYCALL} {MYCALL} TEST"
        let refused: [(String, String, String)] = [
            ("", missing, "an empty callsign"),
            ("   ", missing, "a blank callsign"),
            ("NOCALL", missing, "the first-run value NOCALL"),
            ("N0CALL", missing, "the placeholder N0CALL"),
            ("DEFAULT", missing, "the value AppState gives when nothing is set"),
            ("CALLSIGN", missing, "the preview token"),
            ("0L1ABC-1", rejected, "a callsign with a hyphen (entered, but not accepted)"),
            ("TEST1", rejected, "a word that is not a callsign")
        ]
        for (call, message, what) in refused {
            keyer.send(text: cq, myCall: call)
            let handed = handedToRadio()
            check("CW \(what): nothing is handed to the radio", handed.isEmpty, shown(handed))
            check("CW \(what): the keyer is not transmitting and has no text", !keyer.isTransmitting && keyer.activeBufferText.isEmpty,
                  "transmitting: \(keyer.isTransmitting), text: \(keyer.activeBufferText.debugDescription)")
            check("CW \(what): the operator is told \"\(message)\"", keyer.transmitRefusal == message,
                  "refusal text: \(keyer.transmitRefusal.debugDescription)")
            quiet(keyer)
        }
        for call in ["EA3JIC", "EP2AES", "DL/EA3JIC/P"] {
            keyer.send(text: cq, myCall: call)
            let handed = handedToRadio()
            check("CW \(call): the text goes to the radio with the operator's callsign",
                  handed == ["KEYED via Lab599 TX-500: CQ TEST \(call) \(call) TEST"], shown(handed))
            check("CW \(call): the refusal text is empty", keyer.transmitRefusal.isEmpty, keyer.transmitRefusal)
            quiet(keyer)
        }
        // A refusal text stays until a send goes out, and is replaced by the right one.
        keyer.send(text: cq, myCall: "")
        keyer.send(text: cq, myCall: "0L1ABC-1")
        check("CW: the refusal text is the latest one", keyer.transmitRefusal == rejected)
        keyer.send(text: cq, myCall: "EA3JIC")
        check("CW: a send that goes out clears the refusal", keyer.transmitRefusal.isEmpty)
        quiet(keyer)

        // A refused send does not stop a send that is under way.
        keyer.send(text: "CQ DE EA3JIC", myCall: "EA3JIC")
        let before = keyer.activeBufferText
        keyer.send(text: cq, myCall: "")
        check("CW: a refused send leaves the one under way alone", keyer.isTransmitting && keyer.activeBufferText == before)
        quiet(keyer)

        // Callsigns that end in a digit follow the switch.
        for call in ["0I2012", "0M100", "0R100"] {
            keyer.send(text: cq, myCall: call)
            let handed = handedToRadio()
            check("CW \(call): \(digitEndingAccepted ? "accepted" : "refused") (acceptsCallsignsEndingInDigit = \(digitEndingAccepted))",
                  digitEndingAccepted ? handed == ["KEYED via Lab599 TX-500: CQ TEST \(call) \(call) TEST"]
                                      : (handed.isEmpty && keyer.transmitRefusal == rejected))
            quiet(keyer)
        }
    }

    // MARK: - Auto-CQ

    static func autoCQ(_ keyer: CWKeyerService) {
        let cq = "CQ TEST {MYCALL} {MYCALL} TEST"
        for call in ["", "NOCALL", "0L1ABC-1"] {
            keyer.startAutoCQ(template: cq, myCall: call)
            let handed = handedToRadio()
            check("Auto-CQ with \(call.debugDescription): it does not start and nothing is handed to the radio",
                  !keyer.isAutoCQActive && handed.isEmpty, shown(handed))
            check("Auto-CQ with \(call.debugDescription): the operator is told why",
                  keyer.transmitRefusal == (call == "0L1ABC-1" ? rejected : missing), "refusal text: \(keyer.transmitRefusal.debugDescription)")
            keyer.stopAutoCQ()
            quiet(keyer)
        }
        keyer.startAutoCQ(template: cq, myCall: "EP2AES")
        let handed = handedToRadio()
        check("Auto-CQ with a callsign of the operator starts and keys it", keyer.isAutoCQActive
              && handed.first == "KEYED via Lab599 TX-500: CQ TEST EP2AES EP2AES TEST")
        keyer.stopAutoCQ()
        quiet(keyer)
    }

    // MARK: - Audio Sidetone Only radiates nothing, so it needs no callsign

    static func sidetoneOnly(_ keyer: CWKeyerService) {
        let mode = keyer.transmissionMode
        keyer.transmissionMode = .audioOnly
        keyer.sentHistory = []
        keyer.send(text: "CQ TEST {MYCALL} TEST", myCall: "")
        // The send is accepted when it reaches the history, which happens before its background task starts.
        check("Audio Sidetone Only: a send without a callsign is not refused",
              keyer.transmitRefusal.isEmpty && keyer.sentHistory.count == 1)
        check("Audio Sidetone Only: nothing is handed to a radio", handedToRadio(0.05).isEmpty)
        keyer.stop()
        keyer.startAutoCQ(template: "CQ TEST {MYCALL}", myCall: "")
        check("Audio Sidetone Only: Auto-CQ without a callsign starts", keyer.isAutoCQActive)
        keyer.stopAutoCQ()
        keyer.stop()
        keyer.transmissionMode = mode
        _ = handedToRadio(0.1)
        keyer.send(text: "CQ TEST {MYCALL} TEST", myCall: "")
        check("back on a radio mode the same send is refused again", keyer.transmitRefusal == missing && handedToRadio().isEmpty)
        quiet(keyer)
    }

    // MARK: - Contest function keys F1-F8 (ContestESMControlView calls executeMacro directly)

    static func contestFunctionKeys(_ keyer: CWKeyerService) {
        // A fresh engine, as at the start of the program: Enter has never been pressed.
        let fresh = ContestESMEngine()
        let handed = pressFunctionKey(fresh, fresh.f1CQ)
        check("F1 on a fresh engine without a callsign: nothing is sent", handed.isEmpty, shown(handed))
        check("F1 without a callsign: the contest screen is told why (transmitRefusal)", fresh.transmitRefusal == missing,
              "refusal text: \(fresh.transmitRefusal.debugDescription)")

        // The contest screen gives the engine the profile's callsign when it appears, before any key is pressed.
        fresh.setStationCallsign("EA3JIC")
        check("setting the profile callsign clears the refusal", fresh.transmitRefusal.isEmpty)
        for (name, template, expected) in [("F1", fresh.f1CQ, "CQ TEST EA3JIC EA3JIC K"),
                                           ("F3", fresh.f3TU, "TU EA3JIC CQ"),
                                           ("F4", fresh.f4MyCall, "EA3JIC")] {
            check("\(name) with the profile callsign set, Enter never pressed: keyed as \"\(expected)\"",
                  pressFunctionKey(fresh, template, call: "01ABC") == ["KEYED via Lab599 TX-500: \(expected)"])
            quiet(keyer)
        }
        for placeholder in ["NOCALL", "DEFAULT", ""] {
            fresh.setStationCallsign(placeholder)
            check("F1 after the profile callsign becomes \(placeholder.debugDescription): nothing is sent",
                  pressFunctionKey(fresh, fresh.f1CQ).isEmpty && fresh.transmitRefusal == missing)
        }
        fresh.setStationCallsign("0L1ABC-1")
        _ = pressFunctionKey(fresh, fresh.f1CQ)
        check("F1 with a callsign that is entered but not accepted: the refusal says so", fresh.transmitRefusal == rejected)
        fresh.setStationCallsign("EP2AES")
        check("a change of profile clears the old refusal", fresh.transmitRefusal.isEmpty)
        _ = handedToRadio(0.05)
    }

    // MARK: - Contest Enter key: branches that key are refused, branches that only log are not

    static func contestEnterKey(_ keyer: CWKeyerService) {
        // (role, call, received exchange, what the key would do)
        struct Case { let role: ContestOperatorRole; let call: String; let exch: String; let name: String }
        let keying: [Case] = [
            Case(role: .run, call: "", exch: "", name: "RUN, CQ"),
            Case(role: .run, call: "01ABC", exch: "", name: "RUN, his call and my exchange"),
            Case(role: .run, call: "01ABC", exch: "5A", name: "RUN, TU and log"),
            Case(role: .searchAndPounce, call: "01ABC", exch: "", name: "S&P, my callsign"),
            Case(role: .searchAndPounce, call: "01ABC", exch: "5A", name: "S&P, my exchange")
        ]
        for c in keying {
            let engine = ContestESMEngine()
            engine.role = c.role
            var call = c.call, exch = c.exch
            var logged = 0
            engine.handleEnterPressed(callsign: &call, sentExchange: "21", rcvdExchange: &exch) { logged += 1; return true }
            let sentBefore = handedToRadio()
            check("Enter, \(c.name), no callsign set: nothing is sent", sentBefore.isEmpty, shown(sentBefore))
            check("Enter, \(c.name), no callsign set: nothing is logged and the refusal is shown", logged == 0 && engine.transmitRefusal == missing,
                  "logged: \(logged), refusal text: \(engine.transmitRefusal.debugDescription)")
            check("Enter, \(c.name), no callsign set: the status line shows the refusal, not a message that something was sent",
                  engine.statusMessage == missing && engine.currentState != .spLogReady,
                  "status line: \(engine.statusMessage.debugDescription), state: \(engine.currentState)")
            quiet(keyer)

            engine.setStationCallsign("EA3JIC")
            call = c.call; exch = c.exch
            engine.handleEnterPressed(callsign: &call, sentExchange: "21", rcvdExchange: &exch) { logged += 1; return true }
            check("Enter, \(c.name), callsign set: the text goes to the radio", handedToRadio().first?.contains("KEYED via Lab599 TX-500") == true)
            check("Enter, \(c.name), callsign set: no refusal", engine.transmitRefusal.isEmpty)
            quiet(keyer)
        }
        // The corrected call is a state that is reached only after a first press.
        let corrected = ContestESMEngine()
        var call = "01ABC", exch = ""
        corrected.handleEnterPressed(callsign: &call, sentExchange: "21", rcvdExchange: &exch) { true }
        call = "01ABD"; exch = "5A"
        var logged = 0
        corrected.handleEnterPressed(callsign: &call, sentExchange: "21", rcvdExchange: &exch) { logged += 1; return true }
        check("Enter, RUN, corrected call, no callsign set: nothing is sent and nothing is logged",
              corrected.currentState == .callCorrected && handedToRadio().isEmpty && logged == 0)

        // With ESM off the Enter key only logs: it does not ask for a callsign.
        quiet(keyer)
        let logOnly = ContestESMEngine()
        logOnly.isESMEnabled = false
        var logOnlyCall = "01ABC", logOnlyExch = "5A"
        var logOnlyLogged = 0
        logOnly.handleEnterPressed(callsign: &logOnlyCall, sentExchange: "21", rcvdExchange: &logOnlyExch) { logOnlyLogged += 1; return true }
        let logOnlySent = handedToRadio()
        check("Enter with ESM off and no callsign: the QSO is logged and nothing is sent", logOnlyLogged == 1 && logOnlySent.isEmpty, shown(logOnlySent))
    }

    // MARK: - RTTY / PSK

    static func digitalModem() {
        let dm = DigitalModemEngine.shared
        dm.isTransmitting = false
        for (call, message, what) in [("", missing, "no callsign"), ("NOCALL", missing, "NOCALL"), ("DEFAULT", missing, "DEFAULT"),
                                      ("0L1ABC-1", rejected, "a callsign that is not accepted")] {
            dm.myCallsign = call
            dm.txBufferText = ""
            dm.txRemainingText = ""
            dm.queueTextForTransmission("CQ CQ")
            let queued = KeyLog.drain()
            check("RTTY/PSK queue, \(what): nothing is buffered and nothing keyed", dm.txBufferText.isEmpty && !dm.isTransmitting && queued.isEmpty,
                  "buffered: \(dm.txBufferText.debugDescription), transmitting: \(dm.isTransmitting), \(shown(queued))")
            check("RTTY/PSK queue, \(what): the operator is told why", dm.txRefusal == message, "refusal text: \(dm.txRefusal.debugDescription)")
            dm.stopTransmission()
            _ = handedToRadio(0.05)

            dm.txRefusal = ""
            dm.txRemainingText = "CQ"
            dm.startTransmission()
            let keyed = handedToRadio(0.1)
            let wasTransmitting = dm.isTransmitting
            dm.stopTransmission()
            check("RTTY/PSK start, \(what): the PTT is not keyed", !wasTransmitting && keyed.isEmpty,
                  "transmitting: \(wasTransmitting), \(shown(keyed))")
            check("RTTY/PSK start, \(what): the operator is told why", dm.txRefusal == message, "refusal text: \(dm.txRefusal.debugDescription)")
            _ = handedToRadio(0.05)
        }
        // Positive control without starting any audio: a transmission is "under way", so the text is only buffered.
        dm.myCallsign = "EP2AES"
        dm.txBufferText = ""
        dm.txRefusal = "old"
        dm.isTransmitting = true
        dm.queueTextForTransmission("CQ")
        check("RTTY/PSK queue with a callsign of the operator: the text is buffered and the refusal cleared",
              dm.txBufferText == "CQ" && dm.txRefusal.isEmpty)
        dm.isTransmitting = false
        dm.txBufferText = ""
        dm.txRemainingText = ""

        // Macros: no built-in callsign or locator, the valid part of the locator.
        let macro = "{MYCALL} {MYGRID}"
        let expansions: [(String, String, String)] = [
            ("", "", ""), ("NOCALL", "", ""), ("EA3JIC", "", "EA3JIC"), ("EA3JIC", "BL10", "EA3JIC BL10"),
            ("EP2AES", "lg89", "EP2AES LG89"), ("EA3JIC", "FN54VH54", "EA3JIC FN54VH54"), ("EP2AES", "DO21AL89PF", "EP2AES DO21AL89PF"),
            ("0L1ABC", "JO31ZZ", "0L1ABC JO31"),
            ("EA3JIC", "----", "EA3JIC")
        ]
        let away = ["FN54VH54": " (EA3JIC at US-0001 Acadia National Park)", "DO21AL89PF": " (EP2AES at CA-0005 Banff National Park)"]
        for (call, grid, expected) in expansions {
            dm.myCallsign = call
            dm.myGrid = grid
            let expanded = dm.expandMacroTemplate(macro).trimmingCharacters(in: .whitespacesAndNewlines)
            check("RTTY/PSK macro with callsign \(call.debugDescription) and locator \(grid.debugDescription)\(away[grid] ?? "") reads \"\(expected)\"",
                  expanded == expected, "reads \(expanded.debugDescription)")
        }
        dm.myCallsign = ""
        dm.myGrid = ""
        let standard = DigitalMacro.standardPresets.map { dm.expandMacroTemplate($0.template) }.joined(separator: "\n")
        check("no standard RTTY/PSK macro carries a built-in callsign or locator when none is set",
              !standard.contains("EP2YAAM") && !standard.contains("LL35"),
              standard.replacingOccurrences(of: "\r\n", with: " / ").replacingOccurrences(of: "\n", with: " / "))
    }
}
