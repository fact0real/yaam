import Foundation

// Behaviour test of the digital modes with Radio Control (Y-001, B-018): when Radio Control is set to a radio that is
// not connected, RTTY/PSK refuse to start, say why on their own screen (txRefusal) and keep the text, instead of
// playing the transmission with no PTT (or, with VOX, keyed unseen). Before this change startTransmission played the
// audio and only the driver's status (not shown on that screen) said PTT was not keyed. With Radio Control set to
// "Disabled" (VOX or an external PTT) nothing changes. It runs the real DigitalModemEngine against the recording
// stand-ins of Tests/Support/; no audio engine runs, so a start that passes this check stops at "Audio transmitter
// is unavailable". Nothing is keyed. The operator is EP2AES.
// Build and run from the repository root (Tests/run-cw-safety-regressions.sh does it).

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

@main
struct DigitalModemRadioControlRegression {
    static func start(_ dm: DigitalModemEngine, _ rig: RigDriverType, connected: Bool) -> (String, [String]) {
        RigControlEngine.shared.driverType = rig
        RigControlEngine.shared.isConnected = connected
        dm.txBufferText = ""
        dm.txRemainingText = ""
        dm.txRefusal = ""
        dm.txBufferText = "CQ CQ DE EP2AES"
        _ = KeyLog.drain()
        dm.startTransmission()
        return (dm.txRefusal, KeyLog.drain())
    }

    static func main() {
        let dm = DigitalModemEngine.shared
        dm.myCallsign = "EP2AES"
        dm.operatingMode = .psk31

        let (refusal, keyed) = start(dm, .tx500, connected: false)
        check("Radio Control on a TX-500 that is not connected: nothing starts and nothing is keyed",
              !dm.isTransmitting && keyed.isEmpty, keyed.joined(separator: " | "))
        check("the digital screen says why and what to do",
              refusal.hasPrefix("BPSK31: nothing sent. Radio Control is set to Lab599 TX-500 (USB-C Serial), which is not connected")
                && refusal.contains("Connect it in Radio Control, or set Radio Control to Disabled"), refusal)
        check("the text is kept", dm.txRemainingText == "CQ CQ DE EP2AES" && refusal.hasSuffix("The text in the TX box is kept."),
              dm.txRemainingText.debugDescription)

        // A macro while the radio cannot be keyed is not added (pressing it again would queue it twice).
        dm.txBufferText = ""
        dm.txRemainingText = ""
        dm.txRefusal = ""
        dm.queueTextForTransmission("CQ CQ ")
        dm.queueTextForTransmission("CQ CQ ")
        check("a macro is not added while the radio cannot be keyed, and says so",
              dm.txBufferText.isEmpty && dm.txRefusal.hasSuffix("The text was not added."), dm.txBufferText.debugDescription)

        // A TX-500 or X6100 connected from its own panel is keyed directly: the transmission goes on.
        Lab599TX500Driver.shared.isConnected = true
        let (panel, _) = start(dm, .flrig, connected: false)
        check("Radio Control on flrig not connected, TX-500 connected from its panel: it goes on",
              panel.hasPrefix("Audio transmitter is unavailable"), panel)
        Lab599TX500Driver.shared.isConnected = false

        let (connected, _) = start(dm, .tx500, connected: true)
        check("with the radio connected it goes on (here it stops at the missing audio engine)",
              connected.hasPrefix("Audio transmitter is unavailable"), connected)

        let (disabled, _) = start(dm, .disabled, connected: false)
        check("with Radio Control Disabled (VOX, external PTT) nothing changes",
              disabled.hasPrefix("Audio transmitter is unavailable"), disabled)

        // Routing acquires one transport even when several panels are connected, and releases that same route.
        let rig = RigControlEngine.shared
        rig.driverType = .flrig; rig.isConnected = true
        Lab599TX500Driver.shared.isConnected = true
        Xiegu6100Driver.shared.isConnected = true
        _ = KeyLog.drain()
        dm.acquireTransmitPTT()
        check("selected Radio Control keys one radio only", KeyLog.drain() == ["PTT true via RigControlEngine"])
        dm.stopTransmission()
        check("release returns to that same radio only", KeyLog.drain() == ["PTT false via RigControlEngine"])
        rig.isConnected = false
        check("two direct fallback radios are ambiguous and refused", dm.radioControlRefusal(textKept: true) != nil)
        Xiegu6100Driver.shared.isConnected = false
        dm.acquireTransmitPTT()
        check("one direct fallback acquires only that driver", KeyLog.drain() == ["PTT true via Lab599 TX-500"])
        dm.stopTransmission()
        let releases = KeyLog.drain()
        check("fallback release goes to its acquired driver", releases == ["PTT false via Lab599 TX-500"], releases.joined(separator: " | "))
        Lab599TX500Driver.shared.isConnected = false
        RigControlEngine.shared.driverType = .disabled
        dm.txBufferText = ""
        dm.txRemainingText = ""
        if failures > 0 {
            print("Digital modem Radio Control regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Digital modem Radio Control regression passed")
    }
}
