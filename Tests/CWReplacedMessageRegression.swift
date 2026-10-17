import Foundation

// Behaviour test of a CW message that replaces another one still going out: the screen shows the new message as on
// the air until its own end, and STOP still ends it at once. It runs the real CWKeyerService against the recording
// stand-ins of Tests/Support/, in the modes whose end of message is the keyer's own clock (TX-500, TCI, CAT Morse
// through rigctld), with the sidetone off; and, as a control, through a WinKeyer, whose end comes from the WinKeyer.
// The stand-in serial-pin keyer reports its end at once, so the serial-pin driver is tested on its own in
// Tests/SerialKeyerReplacedMessageRegression.swift.
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/CWReplacedMessageRegression.swift Tests/Support/TransmitGateStubs.swift \
//       Tests/Support/TransmitGateDXCCStub.swift YAAM/CWKeyerService.swift YAAM/TransmitIdentity.swift \
//       YAAM/GridLocator.swift -o cwreplaced && ./cwreplaced
// Nothing opens a port or a socket, and nothing is keyed. The operator is EA3JIC; the other station is invented
// (0A1BC). 24 WPM; the test takes about half a minute, as each message runs its whole clock.

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

@MainActor private func state(_ keyer: CWKeyerService) -> String {
    "transmitting \(keyer.isTransmitting), text \(keyer.activeBufferText.debugDescription)"
}

/// Runs until the keyer is idle, at most `limit` seconds; returns the seconds it took, or nil if it never went idle.
@MainActor private func untilIdle(_ keyer: CWKeyerService, limit: Double) -> Double? {
    let start = Date()
    while keyer.isTransmitting && Date().timeIntervalSince(start) < limit {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return keyer.isTransmitting ? nil : Date().timeIntervalSince(start)
}

@main
struct CWReplacedMessageRegression {
    static let first = "CQ CQ CQ DE EA3JIC EA3JIC EA3JIC K"
    static let second = "0A1BC 5NN TT1"
    static let rig = RigControlClient()

    static func main() {
        let keyer = CWKeyerService.shared
        keyer.sidetoneEnabled = false
        keyer.useCutNumbers = false
        keyer.wpm = 24

        Lab599TX500Driver.shared.isConnected = true
        replaced(keyer, mode: .lab599TX500, label: "TX-500", radio: "Lab599 TX-500")
        Lab599TX500Driver.shared.isConnected = false

        TCIClient.shared.isConnected = true
        replaced(keyer, mode: .tci, label: "TCI", radio: "TCI")
        TCIClient.shared.isConnected = false

        rig.state.isConnected = true
        keyer.rigControlClientRef = rig
        replaced(keyer, mode: .catMorse, label: "CAT Morse (rigctld)", radio: "rigctl")
        rig.state.isConnected = false

        WinKeyerDriver.shared.isConnected = true
        winKeyerControl(keyer)
        WinKeyerDriver.shared.isConnected = false

        if failures > 0 {
            print("CW replaced message regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("CW replaced message regression passed")
    }

    // MARK: - A message replaced by another, in a mode whose end is the keyer's own clock

    static func replaced(_ keyer: CWKeyerService, mode: CWTransmissionMode, label: String, radio: String) {
        keyer.transmissionMode = mode
        _ = run(0.1)

        keyer.send(text: first, myCall: "EA3JIC")
        let a = run(0.3)
        check("\(label): the first message goes out", keyed(a) == ["KEYED via \(radio): \(first)"], shown(a))
        keyer.send(text: second, myCall: "EA3JIC")
        let b = run(0.3)
        check("\(label): the second message goes out", keyed(b) == ["KEYED via \(radio): \(second)"], shown(b))
        check("\(label): 0.3 s after it replaced the first, the second message is on the air on screen",
              keyer.isTransmitting && keyer.activeBufferText == second, state(keyer))
        _ = run(1.5)
        check("\(label): 1.8 s after it, still on the air with its own text",
              keyer.isTransmitting && keyer.activeBufferText == second, state(keyer))
        let took = untilIdle(keyer, limit: 15)
        check("\(label): when its clock ends, the screen goes idle", took != nil && keyer.activeBufferText.isEmpty,
              state(keyer))
        check("\(label): nothing else was keyed meanwhile", keyed(KeyLog.drain()).isEmpty)

        // STOP during the second message ends it at once, and nothing brings it back.
        keyer.send(text: first, myCall: "EA3JIC")
        _ = run(0.3)
        keyer.send(text: second, myCall: "EA3JIC")
        _ = run(0.3)
        keyer.stop()
        check("\(label): STOP during the second message: idle at once", !keyer.isTransmitting && keyer.activeBufferText.isEmpty,
              state(keyer))
        _ = run(1.0)
        check("\(label): STOP: still idle 1 s later", !keyer.isTransmitting && keyer.activeBufferText.isEmpty, state(keyer))

        // STOP and a new message at once (the next click after a STOP): the new message is not ended by the old one.
        keyer.send(text: first, myCall: "EA3JIC")
        _ = run(0.3)
        keyer.stop()
        keyer.send(text: second, myCall: "EA3JIC")
        _ = run(0.3)
        check("\(label): a message sent right after STOP is on the air on screen",
              keyer.isTransmitting && keyer.activeBufferText == second, state(keyer))
        keyer.stop()
        _ = run(0.3)
        _ = KeyLog.drain()
    }

    // MARK: - Control: the WinKeyer's end comes from the WinKeyer (patch 45), unchanged

    static func winKeyerControl(_ keyer: CWKeyerService) {
        keyer.transmissionMode = .winkeyer
        _ = run(0.1)
        keyer.send(text: first, myCall: "EA3JIC")
        _ = run(0.3)
        keyer.send(text: second, myCall: "EA3JIC")
        let b = run(0.3)
        check("WinKeyer (control): the second message goes out", keyed(b) == ["KEYED via WinKeyer: \(second)"], shown(b))
        check("WinKeyer (control): it is on the air on screen", keyer.isTransmitting && keyer.activeBufferText == second,
              state(keyer))
        WinKeyerDriver.shared.isTransmitting = false
        WinKeyerDriver.shared.onTransmissionComplete?()
        _ = run(0.2)
        check("WinKeyer (control): it ends when the WinKeyer reports its end", !keyer.isTransmitting, state(keyer))
    }
}
