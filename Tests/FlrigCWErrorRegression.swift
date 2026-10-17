import Foundation

// Behaviour test of a CW text that flrig does not take (CAT Morse mode): when flrig refuses it or does not answer,
// the send ends at once and the refusal shows flrig's error. Before, the error was dropped and the keyer showed ON
// AIR with the text for the whole message while nothing was keyed. The same when no destination is connected any
// more by the time the text is handed over. It runs the real CWKeyerService against the recording stand-ins of
// Tests/Support/, whose flrig client throws the error the test gives it (as the real client throws FLRigError) and
// can take a while to answer.
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/FlrigCWErrorRegression.swift Tests/Support/TransmitGateStubs.swift \
//       Tests/Support/TransmitGateDXCCStub.swift YAAM/CWKeyerService.swift YAAM/TransmitIdentity.swift \
//       YAAM/GridLocator.swift -o flrigcwerr && ./flrigcwerr
// Nothing opens a port or a socket, and nothing is keyed. The operator is EA3JIC.

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

/// Lets the keyer's background tasks run for a while, then returns what reached the (stand-in) radios.
@MainActor private func run(_ seconds: Double) -> [String] {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    return KeyLog.drain()
}

private func keyed(_ log: [String]) -> [String] { log.filter { $0.hasPrefix("KEYED") } }
private func shown(_ log: [String]) -> String { log.isEmpty ? "nothing" : log.joined(separator: " | ") }

/// The texts of the real client's FLRigError (YAAM/FLRigClient.swift) for a fault and for no answer.
private enum StubFlrigError: LocalizedError {
    case fault, noAnswer
    var errorDescription: String? {
        switch self {
        case .fault: return "flrig refused the command: type error"
        case .noAnswer: return "flrig did not answer."
        }
    }
}

@main
struct FlrigCWErrorRegression {
    static let cq = "CQ TEST {MYCALL} {MYCALL} TEST"
    static let cqText = "CQ TEST EA3JIC EA3JIC TEST"

    static func main() {
        let keyer = CWKeyerService.shared
        keyer.transmissionMode = .catMorse
        keyer.sidetoneEnabled = false
        keyer.useCutNumbers = false

        flrigErrorsEndTheSend(keyer)
        aGoodSendAfterAnError(keyer)
        stopOrANewSendWhileFlrigIsAsked(keyer)
        nothingConnectedWhenTheTextIsHandedOver(keyer)

        if failures > 0 {
            print("flrig CW error regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("flrig CW error regression passed")
    }

    /// Only the flrig stand-in connected, answering at once, with no error; nothing going out.
    static func reset(_ keyer: CWKeyerService) {
        keyer.stop()
        FX4CRDriver.shared.isConnected = false
        Lab599TX500Driver.shared.isConnected = false
        IcomUSBRadioDriver.shared.isConnected = false
        Xiegu6100Driver.shared.isConnected = false
        keyer.rigControlClientRef = nil
        FLRigClient.shared.isConnected = true
        FLRigClient.shared.sendMorseError = nil
        FLRigClient.shared.sendMorseDelay = 0
        keyer.transmitRefusal = ""
        _ = run(0.1)
    }

    // 1. flrig refuses the text, or does not answer: the send ends at once and the screen says why.

    static func flrigErrorsEndTheSend(_ keyer: CWKeyerService) {
        for error in [StubFlrigError.fault, StubFlrigError.noAnswer] {
            let what = error == .fault ? "flrig refuses the text" : "flrig does not answer"
            reset(keyer)
            FLRigClient.shared.sendMorseError = error
            keyer.send(text: cq, myCall: "EA3JIC")
            let log = run(0.3)
            check("\(what): the send has ended after 0.3 s", !keyer.isTransmitting && keyer.activeBufferText.isEmpty,
                  "isTransmitting \(keyer.isTransmitting), text \(keyer.activeBufferText.debugDescription)")
            check("\(what): the refusal shows flrig's error", keyer.transmitRefusal == error.errorDescription,
                  keyer.transmitRefusal.debugDescription)
            check("\(what): nothing is keyed", keyed(log).isEmpty, shown(log))
            check("\(what): the text is also stopped at flrig, which may still take it late",
                  log.filter { $0 == "CW STOP via flrig" }.count == 2, shown(log))   // the one every send starts with, and this one
            keyer.stop()
            let stopped = run(0.3)
            check("\(what): STOP afterwards is harmless (it goes to flrig, the screen stays idle)",
                  !keyer.isTransmitting && stopped == ["CW STOP via flrig"], shown(stopped))
        }
    }

    // 2. Controls: flrig takes the text; a good send after an error clears the refusal.

    static func aGoodSendAfterAnError(_ keyer: CWKeyerService) {
        reset(keyer)
        keyer.send(text: cq, myCall: "EA3JIC")
        var log = run(0.3)
        check("control: flrig takes the text: it is keyed", keyed(log) == ["KEYED via flrig: \(cqText)"], shown(log))
        check("control: a text flrig took is on air (the clock runs)", keyer.isTransmitting && keyer.activeBufferText == cqText)
        check("control: no refusal", keyer.transmitRefusal.isEmpty, keyer.transmitRefusal.debugDescription)

        reset(keyer)
        FLRigClient.shared.sendMorseError = StubFlrigError.fault
        keyer.send(text: cq, myCall: "EA3JIC")
        _ = run(0.3)
        FLRigClient.shared.sendMorseError = nil
        keyer.send(text: "TEST {MYCALL}", myCall: "EA3JIC")
        log = run(0.3)
        check("after an error, a good send is keyed", keyed(log) == ["KEYED via flrig: TEST EA3JIC"], shown(log))
        check("after an error, a good send clears the refusal", keyer.transmitRefusal.isEmpty,
              keyer.transmitRefusal.debugDescription)
        keyer.stop()
        _ = run(0.2)
    }

    // 3. STOP, or a newer send, while flrig is still being asked: a late error of the old text is not shown.

    static func stopOrANewSendWhileFlrigIsAsked(_ keyer: CWKeyerService) {
        reset(keyer)
        FLRigClient.shared.sendMorseError = StubFlrigError.noAnswer
        FLRigClient.shared.sendMorseDelay = 0.5
        keyer.send(text: cq, myCall: "EA3JIC")
        var log = run(0.1)
        check("while flrig is asked, the send shows as going out", keyer.isTransmitting)
        keyer.stop()
        log += run(0.8)
        check("STOP while flrig is asked: no stop is added to the send's own and STOP's",
              log.filter { $0 == "CW STOP via flrig" }.count == 2, shown(log))
        check("STOP while flrig is asked: its late error is not shown", keyer.transmitRefusal.isEmpty,
              keyer.transmitRefusal.debugDescription)
        check("STOP while flrig is asked: the screen is idle", !keyer.isTransmitting)

        reset(keyer)
        FLRigClient.shared.sendMorseError = StubFlrigError.noAnswer
        FLRigClient.shared.sendMorseDelay = 0.5
        keyer.send(text: cq, myCall: "EA3JIC")
        _ = run(0.1)
        FLRigClient.shared.sendMorseError = nil
        FLRigClient.shared.sendMorseDelay = 0
        keyer.send(text: "TEST {MYCALL}", myCall: "EA3JIC")
        log = run(0.8)
        check("a newer send while flrig is asked: it is keyed", keyed(log) == ["KEYED via flrig: TEST EA3JIC"], shown(log))
        check("a newer send while flrig is asked: no stop follows it (the old text's late error stops nothing)",
              log.last == "KEYED via flrig: TEST EA3JIC", shown(log))
        check("a newer send while flrig is asked: the old text's late error is not shown", keyer.transmitRefusal.isEmpty,
              keyer.transmitRefusal.debugDescription)
        keyer.stop()
        _ = run(0.2)
    }

    // 4. flrig was connected at the send, and is not when the text is handed over (its poll missed in between).

    static func nothingConnectedWhenTheTextIsHandedOver(_ keyer: CWKeyerService) {
        reset(keyer)
        keyer.send(text: cq, myCall: "EA3JIC")
        FLRigClient.shared.isConnected = false        // before the transmit task has run
        let log = run(0.3)
        check("nothing connected at the hand-over: the send has ended", !keyer.isTransmitting && keyer.activeBufferText.isEmpty)
        check("nothing connected at the hand-over: the refusal says CAT is offline", keyer.transmitRefusal.contains("CAT Offline"),
              keyer.transmitRefusal.debugDescription)
        check("nothing connected at the hand-over: nothing is keyed", keyed(log).isEmpty, shown(log))
        keyer.stop()
        _ = run(0.1)
    }
}
