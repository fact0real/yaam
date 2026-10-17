import Foundation

// Behaviour test of a CW send with no connected keyer: it is refused, the screen does not show it as going out,
// and the refusal says what is not connected. Before, the keyer showed ON AIR with the text and played the
// sidetone or its clock while nothing was keyed, and with a WinKeyer selected but not connected it stayed
// "transmitting" for ever (Auto-CQ waited for ever too). In CAT Morse mode the TX-500 and the Xiegu, which the
// keyer does send to, count as connected. It runs the real CWKeyerService and ContestESMEngine against the
// recording stand-ins of Tests/Support/; a radio is "disconnected" by setting the stand-in's isConnected.
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/CWNoKeyerRefusalRegression.swift Tests/Support/TransmitGateStubs.swift \
//       Tests/Support/TransmitGateDXCCStub.swift YAAM/CWKeyerService.swift YAAM/ContestESMEngine.swift \
//       YAAM/TransmitIdentity.swift YAAM/GridLocator.swift -o nokeyer && ./nokeyer
// Nothing opens a port or a socket, and nothing is keyed. The operator is EA3JIC. Auto-CQ runs with a 1 s pause
// so that the test takes a few seconds. The cwdaemon mode is only asked, never sent through (it would open a UDP
// socket).

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

/// Runs the main loop until the condition holds or the time is up; returns whether it held.
@MainActor private func runUntil(_ seconds: Double, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return condition()
}

private func keyed(_ log: [String]) -> [String] { log.filter { $0.hasPrefix("KEYED") } }
private func shown(_ log: [String]) -> String { log.isEmpty ? "nothing" : log.joined(separator: " | ") }

@main
struct CWNoKeyerRefusalRegression {
    static let cq = "CQ TEST {MYCALL} {MYCALL} TEST"
    static let cqText = "CQ TEST EA3JIC EA3JIC TEST"

    static func main() {
        let invalidPortKeyer = CWKeyerService()
        invalidPortKeyer.transmissionMode = .cwdaemon
        for port in [-1, 0, 65_536, Int.max] {
            invalidPortKeyer.cwdaemonPort = port
            invalidPortKeyer.stop()
            check("cwdaemon STOP safely ignores invalid port \(port)", !invalidPortKeyer.isTransmitting)
        }
        let keyer = CWKeyerService.shared
        keyer.sidetoneEnabled = false
        keyer.useCutNumbers = false
        keyer.wpm = 40
        keyer.autoCQIntervalSeconds = 1

        tx500Disconnected(keyer)
        winKeyerSelectedNotConnected(keyer)
        catMorse(keyer)
        autoCQEndsWhenTheRadioGoesAway(keyer)
        controls(keyer)
        contestFunctionKey(keyer)

        if failures > 0 {
            print("CW no-keyer refusal regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("CW no-keyer refusal regression passed")
    }

    /// Every stand-in radio disconnected, no rigctld link, and the keyer in the given mode with nothing going out.
    static func reset(_ keyer: CWKeyerService, _ mode: CWTransmissionMode) {
        keyer.stop()
        WinKeyerDriver.shared.isConnected = false
        SerialKeyerDriver.shared.isConnected = false
        FX4CRDriver.shared.isConnected = false
        Lab599TX500Driver.shared.isConnected = false
        IcomUSBRadioDriver.shared.isConnected = false
        Xiegu6100Driver.shared.isConnected = false
        TCIClient.shared.isConnected = false
        FLRigClient.shared.isConnected = false
        keyer.rigControlClientRef = nil
        keyer.transmissionMode = mode
        keyer.transmitRefusal = ""
        _ = run(0.1)
    }

    // 1. TX-500 mode, the TX-500 not connected.

    static func tx500Disconnected(_ keyer: CWKeyerService) {
        reset(keyer, .lab599TX500)
        keyer.send(text: cq, myCall: "EA3JIC")
        check("TX-500 offline: the screen does not show the text as going out",
              !keyer.isTransmitting && keyer.activeBufferText.isEmpty,
              "isTransmitting \(keyer.isTransmitting), text \(keyer.activeBufferText.debugDescription)")
        check("TX-500 offline: the refusal names the TX-500", keyer.transmitRefusal.contains("TX-500"),
              keyer.transmitRefusal.debugDescription)
        check("TX-500 offline: the refusal says nothing was sent", keyer.transmitRefusal.hasPrefix("Nothing sent"),
              keyer.transmitRefusal.debugDescription)
        let log = run(0.5)
        check("TX-500 offline: nothing is keyed", keyed(log).isEmpty, shown(log))
        check("TX-500 offline: still not transmitting after 0.5 s", !keyer.isTransmitting)
        check("TX-500 offline: the refused text is not put in the recent list", !keyer.sentHistory.contains(cqText))
    }

    // 2. WinKeyer selected, not connected: before, the keyer stayed "transmitting" for ever.

    static func winKeyerSelectedNotConnected(_ keyer: CWKeyerService) {
        reset(keyer, .winkeyer)
        keyer.send(text: cq, myCall: "EA3JIC")
        let log = run(0.5)
        check("WinKeyer not connected: the send is refused", !keyer.transmitRefusal.isEmpty)
        check("WinKeyer not connected: not transmitting after 0.5 s", !keyer.isTransmitting && keyer.activeBufferText.isEmpty)
        check("WinKeyer not connected: nothing is keyed", keyed(log).isEmpty, shown(log))
        // Auto-CQ does not start either (it asks the same question).
        keyer.startAutoCQ(template: cq, myCall: "EA3JIC")
        _ = run(0.3)
        check("WinKeyer not connected: Auto-CQ does not start", !keyer.isAutoCQActive && !keyer.isTransmitting)
        keyer.stop()
    }

    // 3. CAT Morse: nothing connected is refused; the TX-500 or the Xiegu alone still goes out.

    static func catMorse(_ keyer: CWKeyerService) {
        reset(keyer, .catMorse)
        keyer.send(text: cq, myCall: "EA3JIC")
        var log = run(0.3)
        check("CAT Morse, no radio: refused as \"CAT Offline\"", keyer.transmitRefusal.contains("CAT Offline"),
              keyer.transmitRefusal.debugDescription)
        check("CAT Morse, no radio: not transmitting, nothing keyed", !keyer.isTransmitting && keyed(log).isEmpty, shown(log))

        for (name, connect, expected) in [
            ("TX-500", { Lab599TX500Driver.shared.isConnected = true }, "KEYED via Lab599 TX-500: \(cqText)"),
            ("Xiegu X6100", { Xiegu6100Driver.shared.isConnected = true }, "KEYED via Xiegu X6100: \(cqText)")
        ] as [(String, () -> Void, String)] {
            reset(keyer, .catMorse)
            connect()
            let status = keyer.hardwareStatusSummary
            check("CAT Morse, only the \(name): the status counts it as connected and names it",
                  status.isConnected && status.title.contains(name.prefix(5)), "\(status)")
            keyer.send(text: cq, myCall: "EA3JIC")
            log = run(0.3)
            check("CAT Morse, only the \(name): not refused", keyer.transmitRefusal.isEmpty, keyer.transmitRefusal.debugDescription)
            check("CAT Morse, only the \(name): the text goes to it", keyed(log) == [expected], shown(log))
            check("CAT Morse, only the \(name): transmitting", keyer.isTransmitting)
            keyer.stop()
        }
    }

    // 4. Auto-CQ: the radio goes away after the first CQ. The next CQ is refused and Auto-CQ ends.

    static func autoCQEndsWhenTheRadioGoesAway(_ keyer: CWKeyerService) {
        reset(keyer, .lab599TX500)
        Lab599TX500Driver.shared.isConnected = true
        keyer.startAutoCQ(template: "CQ {MYCALL}", myCall: "EA3JIC")
        let first = run(0.2)
        check("Auto-CQ: the first CQ goes out", keyed(first) == ["KEYED via Lab599 TX-500: CQ EA3JIC"], shown(first))
        Lab599TX500Driver.shared.isConnected = false
        let ended = runUntil(8) { !keyer.isAutoCQActive }
        let after = KeyLog.drain()
        check("Auto-CQ: it ends once the radio has gone (the next CQ is refused)", ended)
        check("Auto-CQ: the refusal names the TX-500", keyer.transmitRefusal.contains("TX-500"), keyer.transmitRefusal.debugDescription)
        check("Auto-CQ: nothing more is keyed", keyed(after).isEmpty, shown(after))
        check("Auto-CQ: not transmitting at the end", !keyer.isTransmitting)
        keyer.stop()
    }

    // 5. Controls: what must still go, and the order of the refusals.

    static func controls(_ keyer: CWKeyerService) {
        reset(keyer, .lab599TX500)
        Lab599TX500Driver.shared.isConnected = true
        keyer.transmitRefusal = "old"
        keyer.send(text: cq, myCall: "EA3JIC")
        var log = run(0.3)
        check("control: a connected TX-500 keys the text", keyed(log) == ["KEYED via Lab599 TX-500: \(cqText)"], shown(log))
        check("control: a send that goes out clears the refusal", keyer.transmitRefusal.isEmpty)
        keyer.stop()

        reset(keyer, .lab599TX500)
        keyer.send(text: cq, myCall: "")
        check("control: with no callsign and no radio, the callsign refusal comes first",
              keyer.transmitRefusal == TransmitIdentity.callsignMissingMessage, keyer.transmitRefusal.debugDescription)

        reset(keyer, .audioOnly)
        keyer.send(text: "TEST {MYCALL}", myCall: "")
        log = run(0.3)
        check("control: Audio Sidetone Only needs neither a callsign nor a radio",
              keyer.transmitRefusal.isEmpty && keyer.sentHistory.first == "TEST", keyer.transmitRefusal.debugDescription)
        check("control: Audio Sidetone Only keys nothing", keyed(log).isEmpty, shown(log))

        // cwdaemon has no connection state (UDP): it is not refused. Only asked; a send would open a socket.
        keyer.transmissionMode = .cwdaemon
        check("control: cwdaemon is not refused", keyer.refusalReason(myCall: "EA3JIC") == nil)
        keyer.transmissionMode = .lab599TX500
    }

    // 6. A contest function key with the TX-500 off: refused, and the contest screen is told why.

    static func contestFunctionKey(_ keyer: CWKeyerService) {
        reset(keyer, .lab599TX500)
        let esm = ContestESMEngine()
        esm.setStationCallsign("EA3JIC")
        let went = esm.executeMacro(esm.f1CQ, call: "", sentExch: "", rcvdExch: "")
        let log = run(0.3)
        check("contest F1, TX-500 off: executeMacro returns false", !went)
        check("contest F1, TX-500 off: its refusal names the TX-500", esm.transmitRefusal.contains("TX-500"),
              esm.transmitRefusal.debugDescription)
        check("contest F1, TX-500 off: nothing is keyed and the keyer is idle", keyed(log).isEmpty && !keyer.isTransmitting, shown(log))

        Lab599TX500Driver.shared.isConnected = true
        let wentNow = esm.executeMacro(esm.f1CQ, call: "", sentExch: "", rcvdExch: "")
        let now = run(0.3)
        check("contest F1, TX-500 back: it goes out and the refusal is cleared",
              wentNow && esm.transmitRefusal.isEmpty && keyed(now).count == 1, shown(now))
        keyer.stop()
        _ = run(0.1)
    }
}
