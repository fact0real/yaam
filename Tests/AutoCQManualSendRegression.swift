import Foundation

// Behaviour test of Auto-CQ and a message sent by hand: the operator's answer (a macro, typed text, a contest
// function key) ends Auto-CQ, so that no CQ follows it over the other station. Before, Auto-CQ waited for the
// answer to end and then, after its pause, sent the next CQ. A send that is refused changes nothing, and the CQs
// that Auto-CQ sends itself do not end it. It runs the real CWKeyerService and ContestESMEngine against the
// recording stand-ins of Tests/Support/, through a TX-500 (a radio that does not report the end of a message: the
// keyer's own clock decides it), with the sidetone off.
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/AutoCQManualSendRegression.swift Tests/Support/TransmitGateStubs.swift \
//       Tests/Support/TransmitGateDXCCStub.swift YAAM/CWKeyerService.swift YAAM/ContestESMEngine.swift \
//       YAAM/TransmitIdentity.swift YAAM/GridLocator.swift -o autocqhand && ./autocqhand
// Nothing opens a port or a socket, and nothing is keyed. The operator is EA3JIC; the other station is invented
// (0A1BC). 50 WPM and a 1 s pause, so that the test takes about 30 s.

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

/// Lets the keyer's background tasks run for a while, then returns what reached the (stand-in) radio.
@MainActor private func run(_ seconds: Double) -> [String] {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    return KeyLog.drain()
}

/// Runs the main loop until the condition holds or the time is up; returns whether it held. KeyLog is left as is.
@MainActor private func runUntil(_ seconds: Double, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
}

private func keyed(_ log: [String]) -> [String] { log.filter { $0.hasPrefix("KEYED") } }
private func shown(_ log: [String]) -> String { log.isEmpty ? "nothing" : log.joined(separator: " | ") }

@main
struct AutoCQManualSendRegression {
    static let cq = "CQ {MYCALL}"
    static let cqSent = "KEYED via Lab599 TX-500: CQ EA3JIC"
    static let reply = "KEYED via Lab599 TX-500: 0A1BC 5NN"

    static func main() {
        let keyer = CWKeyerService.shared
        keyer.transmissionMode = .lab599TX500
        keyer.sidetoneEnabled = false
        keyer.useCutNumbers = false
        keyer.wpm = 50
        keyer.autoCQIntervalSeconds = 1
        Lab599TX500Driver.shared.isConnected = true

        autoCQAloneRepeats(keyer)
        aReplyDuringTheCQEndsAutoCQ(keyer)
        aReplyDuringThePauseEndsAutoCQ(keyer)
        aContestKeyEndsAutoCQ(keyer)
        aRefusedSendLeavesAutoCQ(keyer)
        stopEndsBoth(keyer)

        if failures > 0 {
            print("Auto-CQ manual send regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Auto-CQ manual send regression passed")
    }

    /// Stops everything and lets the old Auto-CQ task end before the next case starts.
    static func reset(_ keyer: CWKeyerService) {
        keyer.stop()
        _ = run(0.3)
        keyer.transmitRefusal = ""
    }

    // MARK: - Control: Auto-CQ alone repeats (its own CQs do not end it)

    static func autoCQAloneRepeats(_ keyer: CWKeyerService) {
        keyer.startAutoCQ(template: cq, myCall: "EA3JIC")
        let log = run(7.0)
        check("control: Auto-CQ alone sends its CQ again after the pause (two or more CQs in 7 s)",
              keyed(log).count >= 2 && keyed(log).allSatisfy { $0 == cqSent }, shown(log))
        check("control: Auto-CQ is still running after its own CQs", keyer.isAutoCQActive)
        reset(keyer)
    }

    // MARK: - A reply sent while the CQ is going out

    static func aReplyDuringTheCQEndsAutoCQ(_ keyer: CWKeyerService) {
        keyer.startAutoCQ(template: cq, myCall: "EA3JIC")
        let first = run(0.3)
        check("during the CQ: the first CQ goes out", keyed(first) == [cqSent], shown(first))
        keyer.send(text: "{CALL} 5NN", myCall: "EA3JIC", call: "0A1BC")
        check("during the CQ: a reply sent by hand ends Auto-CQ at once", !keyer.isAutoCQActive)
        let went = run(0.3)
        check("during the CQ: the reply goes out", keyed(went) == [reply], shown(went))
        let ended = runUntil(5) { !keyer.isTransmitting }
        let after = keyed(KeyLog.drain()) + keyed(run(3.0))
        check("during the CQ: the reply ends", ended)
        check("during the CQ: no CQ follows the reply (3 s after its end)", after.isEmpty, shown(after))
        check("during the CQ: Auto-CQ is still off", !keyer.isAutoCQActive && keyer.autoCQCountdown == 0)
        reset(keyer)
    }

    // MARK: - A reply sent during the pause

    static func aReplyDuringThePauseEndsAutoCQ(_ keyer: CWKeyerService) {
        keyer.startAutoCQ(template: cq, myCall: "EA3JIC")
        let cqEnded = runUntil(6) { KeyLog.events.count > 0 && !keyer.isTransmitting }
        let first = keyed(KeyLog.drain())
        check("during the pause: the CQ went out and ended", cqEnded && first == [cqSent], shown(first))
        _ = run(0.2)
        check("during the pause: Auto-CQ is counting down", keyer.isAutoCQActive && keyer.autoCQCountdown > 0,
              "active: \(keyer.isAutoCQActive), countdown: \(keyer.autoCQCountdown)")
        keyer.send(text: "{CALL} 5NN", myCall: "EA3JIC", call: "0A1BC")
        check("during the pause: a reply sent by hand ends Auto-CQ at once, and the countdown with it",
              !keyer.isAutoCQActive && keyer.autoCQCountdown == 0)
        // The reply on screen from start to end: no CQ cuts it (the screen would show the CQ).
        var cut = false
        let ended = runUntil(5) {
            if keyer.isTransmitting && keyer.activeBufferText != "0A1BC 5NN" { cut = true }
            return !keyer.isTransmitting
        }
        let during = KeyLog.drain()
        check("during the pause: the reply goes out whole, and nothing else", ended && !cut && keyed(during) == [reply],
              shown(during))
        let after = run(3.0)
        check("during the pause: no CQ follows the reply (3 s after its end)", keyed(after).isEmpty, shown(after))
        reset(keyer)
    }

    // MARK: - Every entry point: a contest function key goes through the same send()

    static func aContestKeyEndsAutoCQ(_ keyer: CWKeyerService) {
        let esm = ContestESMEngine()
        esm.setStationCallsign("EA3JIC")
        keyer.startAutoCQ(template: cq, myCall: "EA3JIC")
        _ = run(0.3)
        let went = esm.executeMacro(esm.f2Exch, call: "0A1BC", sentExch: "", rcvdExch: "")
        check("contest F2 during Auto-CQ: it goes out and ends Auto-CQ", went && !keyer.isAutoCQActive)
        _ = runUntil(6) { !keyer.isTransmitting }
        let after = keyed(KeyLog.drain()) + keyed(run(3.0))
        check("contest F2 during Auto-CQ: the exchange goes out and no CQ follows it",
              after == ["KEYED via Lab599 TX-500: 0A1BC 599 001"], shown(after))
        reset(keyer)
    }

    // MARK: - A refused send changes nothing

    static func aRefusedSendLeavesAutoCQ(_ keyer: CWKeyerService) {
        keyer.startAutoCQ(template: cq, myCall: "EA3JIC")
        _ = run(0.3)
        _ = KeyLog.drain()
        keyer.send(text: "{CALL} 5NN", myCall: "", call: "0A1BC")
        check("refused (no callsign): the refusal is shown", !keyer.transmitRefusal.isEmpty)
        check("refused (no callsign): Auto-CQ goes on and its CQ is still going out",
              keyer.isAutoCQActive && keyer.isTransmitting && keyer.activeBufferText == "CQ EA3JIC")
        keyer.send(text: "{CALL} 5NN TNX BJØRN", myCall: "EA3JIC", call: "0A1BC")
        check("refused (no Morse for Ø): Auto-CQ goes on and its CQ is still going out",
              !keyer.transmitRefusal.isEmpty && keyer.isAutoCQActive && keyer.activeBufferText == "CQ EA3JIC")
        let next = run(6.0)
        check("refused: nothing of it is keyed, and Auto-CQ sends its next CQ",
              keyed(next).count >= 1 && keyed(next).allSatisfy { $0 == cqSent } && keyer.isAutoCQActive, shown(next))
        reset(keyer)
    }

    // MARK: - STOP ends both

    static func stopEndsBoth(_ keyer: CWKeyerService) {
        keyer.startAutoCQ(template: cq, myCall: "EA3JIC")
        _ = run(0.3)
        keyer.stop()
        check("STOP: Auto-CQ and the CQ end at once", !keyer.isAutoCQActive && !keyer.isTransmitting)
        let after = run(3.0)
        check("STOP: nothing more is keyed", keyed(after).isEmpty, shown(after))
    }
}
