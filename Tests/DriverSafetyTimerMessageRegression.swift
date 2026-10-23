import Foundation

// Behaviour test of the drivers' PTT safety timers (Y-001, B-018): when the timer releases PTT, the TX-500, FX-4CR,
// Icom USB and Xiegu drivers say which radio, how long PTT was really on (from the first key-down), the limit, when
// (UTC), that the release was sent but cannot be confirmed, and what to do,
// instead of "PTT released by … safety timer" or "watchdog tripped after N s". It runs the real drivers against the
// stand-ins of Tests/Support/ (a serial port that opens nothing and records every write), keys each one with the
// shortest safety timer (1 s) and lets it run out. The Icom network driver and the rigctld client use the same text;
// Tests/TXLimitsRegression.swift checks their source. The message is also kept as a notice (TransmitNotices) that
// the next status does not replace. Nothing is keyed and no port is opened.
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

@MainActor private func runUntil(_ seconds: Double, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return condition()
}

@main
struct DriverSafetyTimerMessageRegression {
    static func main() {
        let tx500 = Lab599TX500Driver.shared, fx4cr = FX4CRDriver.shared
        let icom = IcomUSBRadioDriver.shared, xiegu = Xiegu6100Driver.shared
        let radios: [(String, () -> Void, () -> Bool, () -> String)] = [
            ("TX-500", { tx500.isConnected = true; tx500.setPTT(true, maximumDuration: 1) }, { tx500.isTransmitting }, { tx500.lastMessage }),
            ("FX-4CR", { fx4cr.isConnected = true; fx4cr.setPTT(true, maximumDuration: 1) }, { fx4cr.isTransmitting }, { fx4cr.lastMessage }),
            ("Icom USB", { icom.isConnected = true; icom.setPTT(true, maximumDuration: 1) }, { icom.isTransmitting }, { icom.lastMessage }),
            ("Xiegu X6100", { xiegu.isConnected = true; xiegu.setPTT(true, maximumDuration: 1) }, { xiegu.isTransmitting }, { xiegu.lastMessage }),
        ]
        for (name, key, transmitting, message) in radios {
            key()
            check("\(name): keyed", transmitting())
            check("\(name): the safety timer releases PTT", runUntil(3) { !transmitting() })
            let text = message()
            check("\(name): the message names the radio, time on, limit, UTC time and what to do",
                  text.hasPrefix("\(name): PTT had been on for 1 s; safety limit 1 s. At ")
                    && text.contains(" UTC YAAM requested PTT release, but cannot confirm") && text.contains("before sending again"), text)
        }

        // The message is also kept as a notice (TransmitNotices) that the next status does not replace: it stays until
        // the operator dismisses it, including when a separate RX readback warning is posted.
        let notices = TransmitNotices.shared
        check("each radio left a notice", Set(["TX-500", "FX-4CR", "Icom USB", "Xiegu X6100"]).isSubset(of: Set(notices.notices.map(\.source.name))),
              notices.notices.map(\.source.name).joined(separator: ", "))
        tx500.lastMessage = "TX-500 Receive (PTT Released)"           // the next status, as FT8 sets when its slot ends
        check("the next status does not remove the notice",
              notices.notices.first { $0.source.name == "TX-500" }?.text.hasPrefix("TX-500: PTT had been on for") == true)
        // A key-down refused because the radio is not connected sends nothing, so it leaves the notice in place.
        xiegu.isConnected = false
        xiegu.setPTT(true, maximumDuration: 16)
        check("a refused key-down (radio not connected) leaves its notice",
              notices.notices.contains { $0.source.name == "Xiegu X6100" })
        let fx = notices.notices.first { $0.source.name == "FX-4CR" }
        if let fx { notices.dismiss(fx.id) }
        check("the operator can dismiss a notice", fx != nil && !notices.notices.contains { $0.source.name == "FX-4CR" })
        icom.isConnected = true
        icom.setPTT(true, maximumDuration: 16)
        check("keying that radio again retains all unacknowledged notices",
              notices.notices.contains { $0.source.name == "Icom USB" } && notices.notices.contains { $0.source.name == "Xiegu X6100" })
        icom.setPTT(false)

        // Keying again while PTT is on does not restart the count: the message says how long it was really on.
        tx500.isConnected = true
        tx500.setPTT(true, maximumDuration: 1)
        _ = runUntil(0.6) { false }
        tx500.setPTT(true, maximumDuration: 1)     // the original deadline must not move
        check("TX-500 keyed twice: the safety timer releases PTT", runUntil(3) { !tx500.isTransmitting })
        check("TX-500 keyed twice: the original one-second deadline still applies",
              tx500.lastMessage.hasPrefix("TX-500: PTT had been on for 1 s"), tx500.lastMessage)
        tx500.isConnected = false; fx4cr.isConnected = false; icom.isConnected = false; xiegu.isConnected = false
        if failures > 0 {
            print("Driver safety timer message regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Driver safety timer message regression passed")
    }
}
