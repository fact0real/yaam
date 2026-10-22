import Foundation

// Behaviour test of TransmitShutdown for the digital modes (Y-001): DigitalModemEngine registers itself when it is
// created, and releaseAll stops a transmission under way, which releases PTT through Radio Control. It runs the real
// DigitalModemEngine against the recording stand-ins of Tests/Support/ (which record "PTT false via ..."). The
// serial drivers, Radio Control and TCI are checked in Tests/TransmitShutdownRegression.swift. Nothing is keyed.
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
struct TransmitShutdownDigitalRegression {
    static func main() {
        let dm = DigitalModemEngine.shared
        check("not transmitting: not listed", !TransmitShutdown.transmitting.contains("Digital modes"))
        dm.isTransmitting = true
        check("a digital transmission under way is listed", TransmitShutdown.transmitting == ["Digital modes"],
              TransmitShutdown.transmitting.joined(separator: ", "))
        _ = KeyLog.drain()
        let released = TransmitShutdown.releaseAll()
        let log = KeyLog.drain()
        check("releaseAll stops it", released == ["Digital modes"] && !dm.isTransmitting, released.joined(separator: ", "))
        check("an engine with no acquired PTT route does not touch unrelated radios", log.isEmpty,
              log.joined(separator: " | "))
        if failures > 0 {
            print("Transmit shutdown digital regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Transmit shutdown digital regression passed")
    }
}
