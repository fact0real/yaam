import Foundation
import FT8Codec
import FT8808Engine

// Behaviour test of the FT8/FT4 transmit checks. It runs the real FT8EngineService (with the ft8-808 codec and the
// real DigitalContestEngine, DXCCDatabase and WebSDRReplyPlanner) on the Lab599 TX-500 path with a recording
// stand-in for the driver (Tests/Support/), and asks which texts the engine would schedule for the radio.
// The transmission is disarmed before its slot starts, so nothing is played and nothing is keyed.
//
// It needs the ft8-808 package built (its Swift modules and objects), which the app links as a package. From the
// repository root, with <ft8-build> the directory of the package's debug build and <ft8-include> its
// Sources/CFT8/include:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM -I <ft8-build> -I <ft8-include> \
//       Tests/TransmitGatesFT8Regression.swift Tests/Support/TransmitGateStubs.swift YAAM/FT8EngineService.swift \
//       YAAM/DigitalContestEngine.swift YAAM/CountryFlagEngine.swift YAAM/DXCCDatabase.swift \
//       YAAM/WebSDRReplyPlanner.swift YAAM/CountryNameNormalizer.swift YAAM/TransmitIdentity.swift YAAM/GridLocator.swift \
//       <ft8-build>/FT8Codec.o <ft8-build>/CFT8.o <ft8-build>/FT8808Engine.o -o tgf && ./tgf
// The operators in the checks are EA3JIC and EP2AES, with four-character island locators as if on holiday
// (BL10, Hawaii; LG89, Mauritius), not their home ones. The longer locators are those of a POTA activation,
// computed from the coordinates in the official POTA park list (pota.app, 08-10-2026): EA3JIC at US-0001 Acadia
// National Park (44.31, -68.2034): FN54VH54; EP2AES at CA-0005 Banff National Park (51.4968, -115.928): DO21AL89PF.

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

private func shown(_ result: (scheduled: Bool, refusal: String?)) -> String {
    "scheduled for the radio: \(result.scheduled ? "yes" : "no"), message: \(result.refusal.map { "\"\($0)\"" } ?? "none")"
}

@MainActor private func settle(_ seconds: Double = 0.2) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// Safety: pick the TX parity whose next slot is the farthest (15 to 30 s away), so the engine never reaches the
/// point where it starts audio during this run; the gain is also set to its minimum.
@MainActor private func useFarthestSlot(_ engine: FT8EngineService) {
    let now = Date()
    let even = DigitalSlotClock.nextSlotStart(parity: .even, after: now, slotSeconds: 15)
    let odd = DigitalSlotClock.nextSlotStart(parity: .odd, after: now, slotSeconds: 15)
    engine.txParity = even > odd ? .even : .odd
    engine.txGain = 0.02
}

@MainActor private func failure(_ engine: FT8EngineService) -> String? {
    if case .failed(let message) = engine.state { return message }
    return nil
}

/// Puts `text` in the engine, asks it to schedule the transmission, and reports whether it did and why not.
@MainActor private func tryToSchedule(_ engine: FT8EngineService, _ text: String) -> (scheduled: Bool, refusal: String?) {
    engine.transmitArmed = false
    settle(0.1)
    engine.stopMonitoring()      // back to idle, so that an old failure is not read as this one
    engine.transmitArmed = true
    engine.txText = text
    useFarthestSlot(engine)
    engine.scheduleTransmission()
    settle(0.8)    // the waveform is made in the background, then the state moves to .waiting
    let scheduled = engine.isTransmitScheduled
    let why = failure(engine)
    engine.transmitArmed = false      // cancels the queued transmission before the slot starts
    settle(0.15)
    _ = KeyLog.drain()
    return (scheduled, why)
}

@main
struct TransmitGatesFT8Regression {
    static let missing = TransmitIdentity.callsignMissingMessage
    static let rejected = TransmitIdentity.callsignRejectedMessage

    static func main() {
        let engine = FT8EngineService()
        engine.audioPath = .lab599TX500
        Lab599TX500Driver.shared.isConnected = true

        identities(engine)
        clearedRefusal(engine)
        messages(engine)
        replyBuilders(engine)
        webSDRReply(engine)
        encoder()

        if failures > 0 {
            print("Transmit gates FT8 regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Transmit gates FT8 regression passed")
    }

    // MARK: - Identity: the callsign and the locator, exactly as FT8StationView.loadIdentity hands them over

    static func identities(_ engine: FT8EngineService) {
        let refused: [(String, String, String, String)] = [
            ("DEFAULT", "", missing, "no active profile (AppState gives DEFAULT)"),
            ("NOCALL", "", missing, "first run: NOCALL and no locator"),
            ("NOCALL", "JO31", missing, "first run, locator typed but callsign not"),
            ("N0CALL", "----", missing, "legacy placeholder with a locator that is not one"),
            ("0L1ABC", "", TransmitIdentity.locatorMissingMessage, "callsign set, locator empty"),
            ("0L1ABC", "----", TransmitIdentity.locatorRejectedMessage, "callsign set, locator not a locator"),
            ("0L1ABC-1", "JO31", rejected, "callsign entered but not accepted"),
            ("TEST1", "JO31", rejected, "a word that is not a callsign")
        ]
        for (call, grid, message, what) in refused {
            engine.configureStation(callsign: call, grid: grid)
            let cq = engine.generateStandardMessage(index: 6)
            check("\(what): the engine prepares no CQ", cq.isEmpty, "prepared: \(cq.debugDescription)")
            // The texts the app's builders used to hand over, and a hand-made one.
            for text in ["CQ \(call) \(grid)", "01ABC \(call) \(grid)", "CQ 0L1ABC JO31"] {
                let result = tryToSchedule(engine, text)
                check("\(what): \"\(text)\" is not scheduled, and the message is \"\(message)\"", !result.scheduled && result.refusal == message, shown(result))
            }
        }

        let allowed: [(String, String, String, String)] = [
            ("EA3JIC", "BL10", "CQ EA3JIC BL10", "callsign and locator"),
            ("EP2AES", "LG89", "CQ EP2AES LG89", "the other operator"),
            ("EA3JIC", "FN54VH54", "CQ EA3JIC FN54", "EA3JIC at US-0001 Acadia National Park, an eight-character locator, of which FT8 sends the first four"),
            ("EP2AES", "DO21AL89PF", "CQ EP2AES DO21", "EP2AES at CA-0005 Banff National Park, a ten-character locator, of which FT8 sends the first four"),
            ("ea3jic ", " fn54vh", "CQ EA3JIC FN54", "EA3JIC at US-0001 Acadia National Park, lower case with spaces")
        ]
        for (call, grid, expected, what) in allowed {
            engine.configureStation(callsign: call, grid: grid)
            let cq = engine.generateStandardMessage(index: 6)
            check("\(what): the engine prepares \"\(expected)\"", cq == expected, "prepared: \(cq.debugDescription)")
            let result = tryToSchedule(engine, cq)
            check("\(what): it is scheduled for the radio", result.scheduled && result.refusal == nil, shown(result))
        }
        // A callsign that ends in a digit follows the switch.
        engine.configureStation(callsign: "0I2012", grid: "BL10")
        let result = tryToSchedule(engine, "CQ 0I2012 BL10")
        check("0I2012: \(TransmitIdentity.acceptsCallsignsEndingInDigit ? "scheduled" : "refused with the \"not accepted\" message") (acceptsCallsignsEndingInDigit = \(TransmitIdentity.acceptsCallsignsEndingInDigit))",
              TransmitIdentity.acceptsCallsignsEndingInDigit ? result.scheduled : (!result.scheduled && result.refusal == rejected))
    }

    // MARK: - A refusal of the previous identity is cleared when the identity is loaded again

    static func clearedRefusal(_ engine: FT8EngineService) {
        engine.configureStation(callsign: "", grid: "")
        _ = tryToSchedule(engine, "CQ 0L1ABC JO31")
        check("the engine shows the refusal for an identity that is not set", failure(engine) == missing,
              "engine message: \(failure(engine).debugDescription)")
        engine.configureStation(callsign: "EA3JIC", grid: "BL10")
        check("when the identity is set the old refusal is gone", failure(engine) == nil,
              "engine message: \(failure(engine).debugDescription)")
        // A failure that has nothing to do with the identity stays.
        engine.transmitArmed = false
        settle(0.1)
        engine.stopMonitoring()
        engine.scheduleTransmission()
        let other = failure(engine)
        check("a failure that is not about the identity is given (\(other ?? "none"))", other != nil && !TransmitIdentity.isIdentityRefusal(other ?? ""))
        engine.configureStation(callsign: "EA3JIC", grid: "BL10")
        check("loading the identity again leaves that failure alone", failure(engine) == other)
        engine.stopMonitoring()
    }

    // MARK: - The text: a standard message must come from the operator; free text is not touched

    static func messages(_ engine: FT8EngineService) {
        engine.configureStation(callsign: "EA3JIC", grid: "BL10")
        let refused: [(String, String)] = [
            ("CQ 0L1ABC JO31", TransmitIdentity.notYourCallsignText),
            ("CQ EA3JIC JO31", TransmitIdentity.notYourLocatorText),
            ("01ABC 0L1ABC -10", TransmitIdentity.notYourCallsignText),
            ("01ABC <0L1ABC> -10", TransmitIdentity.notYourCallsignText),
            ("0L1ABC 01ABC -10", TransmitIdentity.notYourCallsignText),
            ("CQ DEFAULT BL10", TransmitIdentity.notYourCallsignText)
        ]
        for (text, message) in refused {
            let result = tryToSchedule(engine, text)
            check("operator EA3JIC/BL10: \"\(text)\" is not scheduled, and the message is \"\(message)\"", !result.scheduled && result.refusal == message, shown(result))
        }
        for text in ["CQ EA3JIC BL10", "01ABC EA3JIC BL10", "01ABC EA3JIC -10", "01ABC EA3JIC RR73",
                     "TNX 73 GL", "73 GL", "HELLO WORLD", "CQ"] {
            let result = tryToSchedule(engine, text)
            check("operator EA3JIC/BL10: \"\(text)\" is scheduled for the radio", result.scheduled && result.refusal == nil, shown(result))
        }
        // The hashed form of the operator's own callsign is not refused by the check. Whether the encoder can build
        // it is the encoder's business (the build used here cannot), so only the check's own messages are looked for.
        let ours = [TransmitIdentity.notYourCallsignText, TransmitIdentity.notYourLocatorText, missing, rejected,
                    TransmitIdentity.locatorMissingMessage, TransmitIdentity.locatorRejectedMessage, TransmitIdentity.noMessageText]
        for text in ["01ABC <EA3JIC> -10", "01ABC <EA3JIC> RR73"] {
            let result = tryToSchedule(engine, text)
            check("operator EA3JIC/BL10: \"\(text)\" is not refused by the check", result.refusal.map { !ours.contains($0) } ?? true)
        }
    }

    // MARK: - The builder that Wait and Pounce and the roster use

    static func replyBuilders(_ engine: FT8EngineService) {
        engine.configureStation(callsign: "EA3JIC", grid: "FN54VH54")
        let built = engine.directedGridMessage(to: "01abc")
        check("directedGridMessage builds the reply from the engine's own values (EA3JIC at US-0001 Acadia National Park)", built == "01ABC EA3JIC FN54",
              "built: \(built.debugDescription)")
        for (call, grid) in [("", ""), ("NOCALL", "JO31"), ("0L1ABC", ""), ("0L1ABC", "----"), ("DEFAULT", "")] {
            engine.configureStation(callsign: call, grid: grid)
            engine.stopMonitoring()
            let reply = engine.directedGridMessage(to: "01ABC")
            check("directedGridMessage for \(call.debugDescription)/\(grid.debugDescription) builds nothing and the engine says why",
                  reply == nil && failure(engine) != nil, "built: \(reply.debugDescription), engine message: \(failure(engine).debugDescription)")
        }
    }

    // MARK: - WebSDR reply, in the order HamTrackerWorkspaceView.queueWebSDRReply calls it

    static func webSDRReply(_ engine: FT8EngineService) {
        let radio = IcomNetworkRadio()
        radio.state.isConnected = true
        for (own, grid, expected) in [("NOCALL", "JO31", missing), ("N0CALL", "----", missing),
                                      ("0L1ABC", "", TransmitIdentity.locatorMissingMessage), ("0L1ABC-1", "JO31", rejected)] {
            engine.transmitArmed = false
            settle(0.1)
            engine.stopMonitoring()
            let prepared = engine.prepareWebSDRReply("01ABC \(own) -10", stationCallsign: own, grid: grid, dialHz: 14_074_000,
                                                     radio: radio, usbOutputUID: nil)
            engine.transmitArmed = true
            useFarthestSlot(engine)
            engine.scheduleTransmission()
            settle(0.8)
            check("WebSDR reply, own callsign \(own.debugDescription), locator \(grid.debugDescription): not scheduled, \"\(expected)\"",
                  prepared == nil && !engine.isTransmitScheduled && failure(engine) == expected)
            engine.transmitArmed = false
            settle(0.15)
            _ = KeyLog.drain()
        }
        engine.transmitArmed = false
        settle(0.1)
        let prepared = engine.prepareWebSDRReply("01ABC EA3JIC -10", stationCallsign: "EA3JIC", grid: "BL10", dialHz: 14_074_000,
                                                 radio: radio, usbOutputUID: nil)
        engine.transmitArmed = true
        useFarthestSlot(engine)
        engine.scheduleTransmission()
        settle(0.8)
        check("WebSDR reply with EA3JIC/BL10 is scheduled", prepared == nil && engine.isTransmitScheduled)
        engine.transmitArmed = false
        settle(0.15)
        _ = KeyLog.drain()
    }

    // MARK: - The encoder is not a safety net

    static func encoder() {
        // The ft8-808 encoder encodes any text, including placeholders; only messages that pass the check may reach it.
        let encodableButRefused = ["CQ DEFAULT ----", "CQ NOCALL JO31", "CQ  JO31", "CQ 0L1ABC JO31"]
        for text in encodableButRefused {
            let tones = try? FT8Codec.encode(text, protocol: .ft8)
            check("encoder: \"\(text)\" would encode, and the check refuses it for EA3JIC/BL10",
                  tones?.count == 79 && TransmitIdentity.ft8MessageRefusal(text, callsign: "EA3JIC", grid: "BL10") != nil)
        }
        for text in ["CQ EA3JIC BL10", "01ABC EA3JIC -10", "TNX 73 GL"] {
            let tones = try? FT8Codec.encode(text, protocol: .ft8)
            check("encoder: \"\(text)\" encodes, and the check allows it", tones?.count == 79
                  && TransmitIdentity.ft8MessageRefusal(text, callsign: "EA3JIC", grid: "BL10") == nil)
        }
    }
}
