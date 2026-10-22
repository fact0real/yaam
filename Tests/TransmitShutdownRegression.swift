import Foundation

// Behaviour test of TransmitShutdown (Y-001): every path that can key a radio registers itself when it is created, and
// one releaseAll() releases every path that is transmitting. It runs the real TX-500, FX-4CR, Icom USB and Xiegu
// drivers, RigControlEngine and TCIClient against the stand-ins of Tests/Support/ (a serial port that opens nothing
// and records every write). The engine starts with auto-connect off and Radio Control "Disabled", set in this test
// program's own preferences before it is created; the test removes them at the end. Nothing is keyed and no radio,
// port or socket is involved. (The digital modes are checked in Tests/TransmitShutdownDigitalRegression.swift, with
// their own stand-ins.)
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
struct TransmitShutdownRegression {
    static let keys = ["rigAutoConnect", "rigDriverType"]

    static func main() {
        UserDefaults.standard.set(false, forKey: "rigAutoConnect")
        UserDefaults.standard.set(RigDriverType.disabled.rawValue, forKey: "rigDriverType")
        let tx500 = Lab599TX500Driver.shared, fx4cr = FX4CRDriver.shared, icom = IcomUSBRadioDriver.shared
        let xiegu = Xiegu6100Driver.shared, rig = RigControlEngine.shared, tci = TCIClient.shared
        check("nothing is transmitting at first", TransmitShutdown.transmitting.isEmpty, TransmitShutdown.transmitting.joined(separator: ", "))

        tx500.isConnected = true; fx4cr.isConnected = true; icom.isConnected = true; xiegu.isConnected = true
        tx500.setPTT(true); fx4cr.setPTT(true); icom.setPTT(true); xiegu.setPTT(true)
        rig.isPTT = true
        tci.isPTTActive = true
        let keyed = Set(TransmitShutdown.transmitting)
        check("every path keyed is reported as transmitting",
              keyed == ["TX-500", "FX-4CR", "Icom USB", "Xiegu X6100", "Radio Control", "TCI"], keyed.sorted().joined(separator: ", "))

        _ = SerialLog.drain()
        let released = Set(TransmitShutdown.releaseAll())
        let written = SerialLog.drain().map(\.text).joined()
        check("releaseAll releases every one of them", released == keyed, released.sorted().joined(separator: ", "))
        check("the serial radios are released", !tx500.isTransmitting && !fx4cr.isTransmitting && !icom.isTransmitting && !xiegu.isTransmitting)
        check("the TX-500 and FX-4CR get RX;", written.components(separatedBy: "RX;").count - 1 >= 2, written.debugDescription)
        let pttOff = String(decoding: [0x1C, 0x00, 0x00, 0xFD] as [UInt8], as: UTF8.self)
        check("the Icom USB and Xiegu get CI-V PTT OFF (1C 00 00)", written.components(separatedBy: pttOff).count - 1 >= 2)
        check("Radio Control and TCI are released", !rig.isPTT && !tci.isPTTActive)
        check("after releaseAll nothing is transmitting", TransmitShutdown.transmitting.isEmpty, TransmitShutdown.transmitting.joined(separator: ", "))
        check("a second releaseAll releases nothing", TransmitShutdown.releaseAll().isEmpty)

        tx500.isConnected = false; fx4cr.isConnected = false; icom.isConnected = false; xiegu.isConnected = false
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        if failures > 0 {
            print("Transmit shutdown regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Transmit shutdown regression passed")
    }
}
