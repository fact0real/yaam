import AppKit
import Foundation

// Behaviour test of quitting the app while CW goes out: the keyer stops what it is sending, and Auto-CQ, when the
// app posts NSApplication.willTerminateNotification, before the notification returns (after it, the app exits and
// nothing else runs). It runs the real CWKeyerService against the recording stand-ins of Tests/Support/: a WinKeyer
// (whose clear is recorded as "WinKeyer buffer cleared") and, in CAT Morse mode, a rigctld client (whose stop is
// recorded as "CW STOP via rigctl"). Posting the notification needs no NSApplication object.
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/CWStopOnQuitRegression.swift Tests/Support/TransmitGateStubs.swift \
//       Tests/Support/TransmitGateDXCCStub.swift YAAM/CWKeyerService.swift YAAM/TransmitIdentity.swift \
//       YAAM/GridLocator.swift -o cwquit && ./cwquit
// Nothing opens a port or a socket, and nothing is keyed. The operator is EA3JIC. Auto-CQ runs with a 1 s pause.

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

/// What the app does when it quits. Whatever the keyer does about it must be done when this returns.
@MainActor private func quit() -> [String] {
    NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
    return KeyLog.drain()
}

@main
struct CWStopOnQuitRegression {
    static let cq = "CQ TEST {MYCALL} {MYCALL} TEST"
    static let cqSent = "KEYED via WinKeyer: CQ TEST EA3JIC EA3JIC TEST"

    static func main() {
        let keyer = CWKeyerService.shared
        keyer.transmissionMode = .winkeyer
        keyer.sidetoneEnabled = false
        keyer.useCutNumbers = false
        keyer.autoCQIntervalSeconds = 1
        WinKeyerDriver.shared.isConnected = true

        quitStopsTheWinKeyer(keyer)
        quitStopsAutoCQ(keyer)
        quitStopsCATMorseAtOnce(keyer)

        if failures > 0 {
            print("CW stop on quit regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("CW stop on quit regression passed")
    }

    // MARK: - A message going out through the WinKeyer

    static func quitStopsTheWinKeyer(_ keyer: CWKeyerService) {
        keyer.send(text: cq, myCall: "EA3JIC")
        let sent = run(0.3)
        check("WinKeyer: the CQ goes out", keyed(sent) == [cqSent], shown(sent))
        check("WinKeyer: the keyer is transmitting", keyer.isTransmitting)
        let atQuit = quit()
        check("WinKeyer: at quit the WinKeyer's buffer is cleared before the notification returns",
              atQuit.contains("WinKeyer buffer cleared"), shown(atQuit))
        check("WinKeyer: at quit the keyer is no longer transmitting and has no text",
              !keyer.isTransmitting && keyer.activeBufferText.isEmpty,
              "transmitting: \(keyer.isTransmitting), text: \(keyer.activeBufferText.debugDescription)")
        _ = run(0.2)
    }

    // MARK: - Auto-CQ

    static func quitStopsAutoCQ(_ keyer: CWKeyerService) {
        keyer.startAutoCQ(template: cq, myCall: "EA3JIC")
        let first = run(0.3)
        check("Auto-CQ: the first CQ goes out", keyed(first) == [cqSent], shown(first))
        let atQuit = quit()
        check("Auto-CQ: at quit Auto-CQ is stopped and the CQ going out is cleared",
              !keyer.isAutoCQActive && !keyer.isTransmitting && atQuit.contains("WinKeyer buffer cleared"),
              "Auto-CQ active: \(keyer.isAutoCQActive), transmitting: \(keyer.isTransmitting), \(shown(atQuit))")
        let later = run(2.0)
        check("Auto-CQ: no further CQ in the 2 s after quit (1 s pause)", keyed(later).isEmpty, shown(later))
        keyer.stop()
        _ = run(0.2)
    }

    // MARK: - CAT Morse through rigctld: the stop is written before the notification returns

    static func quitStopsCATMorseAtOnce(_ keyer: CWKeyerService) {
        WinKeyerDriver.shared.isConnected = false
        keyer.transmissionMode = .catMorse
        let rig = RigControlClient()
        rig.state.isConnected = true
        keyer.rigControlClientRef = rig
        keyer.send(text: cq, myCall: "EA3JIC")
        let sent = run(0.3)
        check("CAT Morse: the CQ goes to rigctld", keyed(sent) == ["KEYED via rigctl: CQ TEST EA3JIC EA3JIC TEST"], shown(sent))
        let atQuit = quit()
        check("CAT Morse: at quit rigctld is told to stop before the notification returns",
              atQuit.contains("CW STOP via rigctl"), shown(atQuit))
        check("CAT Morse: at quit the keyer is no longer transmitting", !keyer.isTransmitting)
        _ = run(0.2)
        withExtendedLifetime(rig) {}
    }
}
