import Foundation

// Behaviour test of STOP in CAT Morse mode: it goes to the destination that took the text, even when the
// connection states have changed since the send (flrig's last poll missed, or another radio appeared), and the
// stop of a destination other than flrig is written at once, inside stop(). It runs the real CWKeyerService against
// the recording stand-ins of Tests/Support/, whose flrig and rigctld clients record each stop they are asked for
// ("CW STOP via flrig", "CW STOP via rigctl"). A connection is "lost" by setting the stand-in's isConnected.
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/CATStopDestinationRegression.swift Tests/Support/TransmitGateStubs.swift \
//       Tests/Support/TransmitGateDXCCStub.swift YAAM/CWKeyerService.swift YAAM/TransmitIdentity.swift \
//       YAAM/GridLocator.swift -o catstop && ./catstop
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

private func stops(_ log: [String]) -> [String] { log.filter { $0.hasPrefix("CW STOP") } }
private func shown(_ log: [String]) -> String { log.isEmpty ? "nothing" : log.joined(separator: " | ") }

@main
struct CATStopDestinationRegression {
    static let cq = "CQ TEST {MYCALL} {MYCALL} TEST"
    static let cqText = "CQ TEST EA3JIC EA3JIC TEST"

    static func main() {
        stopAfterAMissedFlrigPoll()
        stopGoesToRigctlNotToAFlrigThatAppeared()
        stopWithNothingSentGoesToWhatIsConnected()
        aNewSendStopsTheDestinationOfTheLastText()

        if failures > 0 {
            print("CAT STOP destination regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("CAT STOP destination regression passed")
    }

    /// A keyer in CAT Morse mode, with every stand-in radio disconnected.
    static func freshKeyer() -> CWKeyerService {
        FX4CRDriver.shared.isConnected = false
        Lab599TX500Driver.shared.isConnected = false
        IcomUSBRadioDriver.shared.isConnected = false
        Xiegu6100Driver.shared.isConnected = false
        FLRigClient.shared.isConnected = false
        let keyer = CWKeyerService()
        keyer.transmissionMode = .catMorse
        keyer.sidetoneEnabled = false
        keyer.useCutNumbers = false
        _ = run(0.05)
        return keyer
    }

    static func finish(_ keyer: CWKeyerService) {
        keyer.stop()
        _ = run(0.2)
    }

    // 1. flrig took the text; its next poll missed (isConnected false). STOP still goes to flrig.

    static func stopAfterAMissedFlrigPoll() {
        let keyer = freshKeyer()
        FLRigClient.shared.isConnected = true
        keyer.send(text: cq, myCall: "EA3JIC")
        let sent = run(0.3)
        check("flrig: the text goes to flrig", sent.contains("KEYED via flrig: \(cqText)"), shown(sent))
        FLRigClient.shared.isConnected = false          // flrig's last poll missed
        keyer.stop()
        let stopped = run(0.3)
        check("flrig: after a missed poll, STOP still goes to flrig", stops(stopped) == ["CW STOP via flrig"], shown(stopped))
        check("flrig: STOP ends the send on screen", !keyer.isTransmitting && keyer.activeBufferText.isEmpty)
        finish(keyer)
    }

    // 2. rigctld took the text; then its link dropped and flrig reports a radio. STOP goes to rigctld, not flrig.

    static func stopGoesToRigctlNotToAFlrigThatAppeared() {
        let keyer = freshKeyer()
        let rig = RigControlClient()
        rig.state.isConnected = true
        keyer.rigControlClientRef = rig
        keyer.send(text: cq, myCall: "EA3JIC")
        let sent = run(0.3)
        check("rigctl: the text goes to rigctld", sent.contains("KEYED via rigctl: \(cqText)"), shown(sent))
        rig.state.isConnected = false
        FLRigClient.shared.isConnected = true
        keyer.stop()
        let atOnce = KeyLog.events
        let stopped = run(0.3)
        check("rigctl: STOP goes to rigctld, which took the text", stopped.contains("CW STOP via rigctl"), shown(stopped))
        check("rigctl: STOP does not go to flrig, which never had the text", !stopped.contains("CW STOP via flrig"), shown(stopped))
        check("rigctl: the stop is written inside stop(), not in a later task", atOnce.contains("CW STOP via rigctl"), shown(atOnce))
        keyer.stop()
        let second = run(0.3)
        check("rigctl: a second STOP goes to the same place", stops(second) == ["CW STOP via rigctl"], shown(second))
        finish(keyer)
        withExtendedLifetime(rig) {}
    }

    // 3. Nothing was ever sent: STOP goes to what is connected now, as before.

    static func stopWithNothingSentGoesToWhatIsConnected() {
        let keyer = freshKeyer()
        FLRigClient.shared.isConnected = true
        keyer.stop()
        let stopped = run(0.3)
        check("nothing sent yet: STOP goes to the connected flrig, as before", stops(stopped) == ["CW STOP via flrig"], shown(stopped))
        finish(keyer)
    }

    // 4. A new send stops the previous one first (stopTransmitOnly): that stop goes to the previous destination too.

    static func aNewSendStopsTheDestinationOfTheLastText() {
        let keyer = freshKeyer()
        let rig = RigControlClient()
        rig.state.isConnected = true
        keyer.rigControlClientRef = rig
        keyer.send(text: cq, myCall: "EA3JIC")
        _ = run(0.3)
        rig.state.isConnected = false
        FLRigClient.shared.isConnected = true
        keyer.send(text: "{MYCALL} K", myCall: "EA3JIC")
        let log = run(0.3)
        let stop = log.firstIndex(of: "CW STOP via rigctl")
        let keyed = log.firstIndex(of: "KEYED via flrig: EA3JIC K")
        check("new send: the second text goes to flrig, now the connected destination", keyed != nil, shown(log))
        check("new send: the first text is stopped at rigctld before the second goes out",
              stop != nil && keyed != nil && stop! < keyed!, shown(log))
        check("new send: flrig is not stopped for a text it never had", !log.contains("CW STOP via flrig"), shown(log))
        finish(keyer)
        withExtendedLifetime(rig) {}
    }
}
