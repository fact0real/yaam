import Foundation

// Behaviour test of Auto-CQ in CAT Morse mode when flrig does not take the CQ: Auto-CQ ends at the first CQ flrig
// refuses or does not answer for, and the refusal stays on screen, as a CQ refused before it is sent already ends it.
// Before, the refusal of the CQ came after Auto-CQ had looked for it, so Auto-CQ asked flrig again after every pause,
// for as long as it was left on, with the screen counting down to the next CQ. It runs the real CWKeyerService
// against the recording stand-ins of Tests/Support/, whose flrig client throws the error the test gives it.
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/AutoCQCATRefusalRegression.swift Tests/Support/TransmitGateStubs.swift \
//       Tests/Support/TransmitGateDXCCStub.swift YAAM/CWKeyerService.swift YAAM/TransmitIdentity.swift \
//       YAAM/GridLocator.swift -o autocqcat && ./autocqcat
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
struct AutoCQCATRefusalRegression {
    static let cq = "CQ {MYCALL}"

    static func main() {
        let keyer = CWKeyerService.shared
        keyer.transmissionMode = .catMorse
        keyer.sidetoneEnabled = false
        keyer.useCutNumbers = false
        keyer.wpm = 40
        keyer.autoCQIntervalSeconds = 2

        aCQFlrigDoesNotTakeEndsAutoCQ(keyer)
        controlAutoCQGoesOnWhenFlrigTakesTheCQ(keyer)

        keyer.stopAutoCQ()
        keyer.stop()
        _ = run(0.2)
        if failures > 0 {
            print("Auto-CQ CAT refusal regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Auto-CQ CAT refusal regression passed")
    }

    /// Only the flrig stand-in connected, answering at once, with no error; nothing going out.
    static func reset(_ keyer: CWKeyerService) {
        keyer.stopAutoCQ()
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
        _ = run(0.2)
    }

    // 1. flrig refuses the CQ, or does not answer: Auto-CQ ends at once, the refusal stays, and flrig is not asked again.

    static func aCQFlrigDoesNotTakeEndsAutoCQ(_ keyer: CWKeyerService) {
        for error in [StubFlrigError.fault, StubFlrigError.noAnswer] {
            let what = error == .fault ? "flrig refuses the CQ" : "flrig does not answer the CQ"
            reset(keyer)
            FLRigClient.shared.sendMorseError = error
            keyer.startAutoCQ(template: cq, myCall: "EA3JIC")
            let first = run(0.5)
            check("\(what): Auto-CQ has ended 0.5 s after the CQ", !keyer.isAutoCQActive,
                  "isAutoCQActive \(keyer.isAutoCQActive), countdown \(keyer.autoCQCountdown)")
            check("\(what): the refusal shows flrig's error", keyer.transmitRefusal == error.errorDescription,
                  keyer.transmitRefusal.debugDescription)
            // Every CQ flrig does not take leaves two stops at flrig: the one every send starts with, and the one after
            // the error. One CQ only, then nothing more after two whole pauses.
            let later = run(5.0)
            let asked = (first + later).filter { $0 == "CW STOP via flrig" }.count / 2
            check("\(what): flrig is asked for one CQ only, not again after each pause", asked == 1,
                  "\(asked) CQs: \(shown(first + later))")
            check("\(what): nothing is keyed", keyed(first + later).isEmpty, shown(first + later))
            check("\(what): the refusal is still shown after the pauses", keyer.transmitRefusal == error.errorDescription,
                  keyer.transmitRefusal.debugDescription)
            check("\(what): no countdown is left on screen", keyer.autoCQCountdown == 0, "\(keyer.autoCQCountdown)")
        }
    }

    // 2. Control: flrig takes the CQ; Auto-CQ repeats it after its pause, as it always did.

    static func controlAutoCQGoesOnWhenFlrigTakesTheCQ(_ keyer: CWKeyerService) {
        reset(keyer)
        keyer.startAutoCQ(template: cq, myCall: "EA3JIC")
        let log = run(6.0)
        check("control: flrig takes the CQ: Auto-CQ is still on", keyer.isAutoCQActive)
        check("control: the CQ went out twice (once, then again after the pause)",
              keyed(log).filter { $0 == "KEYED via flrig: CQ EA3JIC" }.count >= 2, shown(log))
        check("control: no refusal", keyer.transmitRefusal.isEmpty, keyer.transmitRefusal.debugDescription)
        keyer.stopAutoCQ()
        keyer.stop()
        _ = run(0.3)
    }
}
