import Foundation

// Behaviour test of the serial-pin CW keyer (DTR/RTS) when a message is replaced or aborted: the cancelled message
// does not report an end (CWKeyerService would mark the new message ended), does not mark the driver idle, and does
// not write the key or PTT line again after abort() has released them. It runs the real YAAM/SerialKeyerDriver.swift
// against two stand-ins declared below: a SerialPortService that records every DTR and RTS write instead of touching
// a port, and a CWKeyerService that holds only the Morse letters this test sends (the driver reads its table).
// Key on DTR, PTT on RTS, not inverted, 25 ms PTT lead-in and 50 ms tail (the driver's defaults).
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/SerialKeyerReplacedMessageRegression.swift YAAM/SerialKeyerDriver.swift -o skreplaced && ./skreplaced
// Nothing opens a port or a device. Messages at 5 WPM ("T", a 720 ms dah; "E", a 240 ms dit) make sure the
// replacement and the aborts land while the key is down.

/// Stand-in: records the line writes the driver makes.
final class SerialPortService {
    struct Write { let line: String; let active: Bool; let at: Date }
    static var writes: [Write] = []
    init() {}
    static func availablePorts(includeBluetooth: Bool = true) -> [String] { [] }
    func openPort(path: String, baudRate: Int = 1200, stopBits: Int = 1, onReceive: ((Data) -> Void)? = nil) -> Bool { true }
    func closePort() {}
    @discardableResult func setDTR(active: Bool) -> Bool { Self.writes.append(Write(line: "DTR", active: active, at: Date())); return true }
    @discardableResult func setRTS(active: Bool) -> Bool { Self.writes.append(Write(line: "RTS", active: active, at: Date())); return true }
}

/// Stand-in: only the Morse letters this test sends.
enum CWKeyerService {
    static let morseAlphabet: [Character: String] = ["E": ".", "T": "-", "S": "...", "O": "---"]
}

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

@MainActor private func run(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

/// The last value written to a line (false when never written).
private func last(_ line: String) -> Bool { SerialPortService.writes.last(where: { $0.line == line })?.active ?? false }

private func describe(_ writes: ArraySlice<SerialPortService.Write>) -> String {
    writes.isEmpty ? "none" : writes.map { "\($0.line) \($0.active ? "on" : "off")" }.joined(separator: ", ")
}

/// Counts the end reports of each message.
@MainActor final class Ends { var count: [String: Int] = [:] }

@main
struct SerialKeyerReplacedMessageRegression {
    static func main() {
        let driver = SerialKeyerDriver.shared
        driver.cwPin = .dtr
        driver.pttPin = .rts
        driver.isInverted = false
        driver.pttLeadInMs = 25
        driver.pttTailMs = 50
        driver.connect(port: "stand-in")
        check("control: the driver opens the stand-in port", driver.isConnected)
        let ends = Ends()

        // 1. A message that is not interrupted ends normally (control).
        driver.sendMorse(text: "EE", wpm: 30, onComplete: { ends.count["whole", default: 0] += 1 })
        run(1.0)
        check("control: a whole message reports its end once", ends.count["whole"] == 1, "\(ends.count)")
        check("control: at its end both lines are released and the driver is idle",
              !last("DTR") && !last("RTS") && !driver.isTransmitting)

        // 2. A message replaced by another while its key is down.
        driver.sendMorse(text: "TT", wpm: 5, onComplete: { ends.count["replaced", default: 0] += 1 })
        run(0.3)
        let mark = SerialPortService.writes.count
        driver.sendMorse(text: "SOS", wpm: 30, onComplete: { ends.count["new", default: 0] += 1 })
        run(0.2)
        check("replaced: the replaced message reports no end", ends.count["replaced"] == nil, "\(ends.count)")
        check("replaced: the driver is transmitting the new message", driver.isTransmitting)
        run(0.3)
        let pttOn = SerialPortService.writes[mark...].firstIndex(where: { $0.line == "RTS" && $0.active })
        let newEnd = Date()
        let during = pttOn.map { SerialPortService.writes[$0...].filter { $0.at < newEnd } } ?? []
        check("replaced: once the new message has keyed PTT, nothing releases it while it goes out",
              pttOn != nil && !during.contains(where: { $0.line == "RTS" && !$0.active }),
              describe(SerialPortService.writes[mark...]))
        let limit = Date().addingTimeInterval(4)     // "SOS" at 30 WPM: about 1.3 s
        while ends.count["new"] == nil && Date() < limit { run(0.05) }
        run(0.3)
        check("replaced: the new message reports its end once", ends.count["new"] == 1, "\(ends.count)")
        check("replaced: still no end for the replaced message", ends.count["replaced"] == nil, "\(ends.count)")
        check("replaced: at the end both lines are released and the driver is idle",
              !last("DTR") && !last("RTS") && !driver.isTransmitting)

        // 3. STOP (abort) while the key is down: the lines stay released.
        driver.sendMorse(text: "TT", wpm: 5, onComplete: { ends.count["aborted", default: 0] += 1 })
        run(0.3)
        check("abort: the key is down when STOP comes", last("DTR") && last("RTS"))
        driver.abort()
        let afterAbort = SerialPortService.writes.count
        run(1.5)
        let later = SerialPortService.writes[afterAbort...]
        check("abort: no line is written again after abort() released them",
              !later.contains(where: { $0.active }), describe(later))
        check("abort: PTT and key stay released", !last("DTR") && !last("RTS"), describe(later))
        check("abort: the aborted message reports no end", ends.count["aborted"] == nil, "\(ends.count)")
        check("abort: the driver is idle", !driver.isTransmitting)

        // 4. The same during a dit ("E" at 5 WPM: 240 ms key-down).
        driver.sendMorse(text: "EE", wpm: 5, onComplete: { ends.count["aborted dit", default: 0] += 1 })
        run(0.15)
        check("abort during a dit: the key is down when STOP comes", last("DTR") && last("RTS"))
        driver.abort()
        let afterDit = SerialPortService.writes.count
        run(1.0)
        let laterDit = SerialPortService.writes[afterDit...]
        check("abort during a dit: no line is written again, PTT and key stay released",
              !laterDit.contains(where: { $0.active }) && !last("DTR") && !last("RTS"), describe(laterDit))
        check("abort during a dit: no end is reported", ends.count["aborted dit"] == nil, "\(ends.count)")

        driver.disconnect()
        if failures > 0 {
            print("Serial keyer replaced message regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Serial keyer replaced message regression passed")
    }
}
