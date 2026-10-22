import Foundation

// Behaviour test (Y-001, B-018): when PTT is asked for while the TX-500, FX-4CR, Icom USB or Xiegu is not connected,
// the driver keys nothing and now says so: which radio, when (UTC), that YAAM did not key it, and what to do, keeping
// the status it had before (which usually says why the radio is not connected) at the end.
// Before this change the refusal was silent (the FT8 screen had its own message; Radio Control and the manual PTT
// had none). A release while not connected stays silent: there is nothing to release. It runs the real drivers
// against the stand-ins of Tests/Support/. Nothing is keyed and no port is opened.
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
struct DriverNotConnectedMessageRegression {
    static func main() {
        let tx500 = Lab599TX500Driver.shared, fx4cr = FX4CRDriver.shared
        let icom = IcomUSBRadioDriver.shared, xiegu = Xiegu6100Driver.shared
        let radios: [(String, (Bool) -> Void, () -> Bool, () -> String, (String) -> Void)] = [
            ("TX-500", { tx500.setPTT($0) }, { tx500.isTransmitting }, { tx500.lastMessage }, { tx500.lastMessage = $0 }),
            ("FX-4CR", { fx4cr.setPTT($0) }, { fx4cr.isTransmitting }, { fx4cr.lastMessage }, { fx4cr.lastMessage = $0 }),
            ("Icom USB", { icom.setPTT($0) }, { icom.isTransmitting }, { icom.lastMessage }, { icom.lastMessage = $0 }),
            ("Xiegu X6100", { xiegu.setPTT($0) }, { xiegu.isTransmitting }, { xiegu.lastMessage }, { xiegu.lastMessage = $0 }),
        ]
        tx500.isConnected = false; fx4cr.isConnected = false; icom.isConnected = false; xiegu.isConnected = false
        _ = SerialLog.drain()
        for (name, setPTT, transmitting, message, setMessage) in radios {
            setMessage("Failed to open the port")
            setPTT(false)
            check("\(name): a release while not connected says nothing", message() == "Failed to open the port", message())
            setPTT(true)
            let text = message()
            check("\(name): asked to transmit while not connected, nothing is keyed", !transmitting())
            check("\(name): and it says which radio, when, that YAAM did not key it and what to do",
                  text.hasPrefix("\(name): PTT not keyed at ") && text.contains(" UTC, because the radio is not connected: YAAM did not key it.")
                    && text.contains("Connect it in Radio Control"), text)
            check("\(name): previous private driver output is not copied into the notice", !text.contains("Last status:"), text)
            setPTT(true)
            check("\(name): repeated refusals stay bounded", message().count < 400 && !message().contains("Last status:"), message())
        }
        check("nothing was written to any port", SerialLog.drain().isEmpty)
        if failures > 0 {
            print("Driver not connected message regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Driver not connected message regression passed")
    }
}
