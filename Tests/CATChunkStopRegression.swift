import Foundation

// Behaviour test of CW sent over CAT to a Lab599 TX-500 or an FX-4CR (Kenwood KY): once the driver has sent
// "KY ;RX;" (STOP, Esc, or the clear that every new message starts with) or has been disconnected, nothing of the
// old message reaches the radio any more. The drivers cut a long text into KY pieces and send the later ones on a
// timer; before this change, those timers still fired after STOP, after a new message and after a reconnect, and
// the radio keyed the old text again.
//
// It runs the real YAAM/Lab599TX500Driver.swift and YAAM/FX4CRDriver.swift against the stand-ins of Tests/Support/:
// a SerialPortService that opens nothing and records every write with its time, and an FT8808Engine module that
// lists no audio devices. The test marks a driver connected directly (never connect(), which would open a port).
//
// Build and run from the repository root, with the app's Swift settings. First the FT8808Engine stand-in, as a
// module of its own, in a work folder (here w/):
//   mkdir -p w && swiftc -parse-as-library -emit-library -emit-module -module-name FT8808Engine \
//       -emit-module-path w/FT8808Engine.swiftmodule -o w/libFT8808Engine.dylib \
//       Tests/Support/FT8808EngineStandIn.swift
// then the test:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM -I w -L w -lFT8808Engine -Xlinker -rpath -Xlinker @executable_path \
//       Tests/CATChunkStopRegression.swift Tests/Support/CATDriverStandIns.swift \
//       YAAM/Lab599TX500Driver.swift YAAM/FX4CRDriver.swift YAAM/Lab599TX500SMeter.swift YAAM/MorseTiming.swift \
//       -o w/catstop && w/catstop
// Instead of the stand-in module, the package's own build can be used (-I and -L on an ft8-808 build, as
// Tests/TransmitGatesFT8Regression.swift describes); the test only needs AudioDevices to list nothing real.
// Nothing opens a port, a socket or a device, and nothing is keyed. The operator is EA3JIC. Each check waits one
// second longer than the driver took to send the whole message alone.

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

/// Lets the drivers' timers run for a while.
@MainActor private func run(_ seconds: Double) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

private func isStop(_ w: SerialWrite) -> Bool { w.text == "KY ;RX;" }
/// A KY that carries text (not the "KY ;" of a stop).
private func isText(_ w: SerialWrite) -> Bool { w.text.hasPrefix("KY ") && !isStop(w) }
private func kyText(_ w: SerialWrite) -> String { String(w.text.dropFirst(3).dropLast()) }
private func show(_ log: [SerialWrite]) -> String { log.map(\.text).joined(separator: " | ") }

/// One of the two drivers, through the members the test uses.
@MainActor struct Radio {
    let name: String
    let setConnected: (Bool) -> Void
    let send: (String, Int) -> Void
    let stop: () -> Void
    let disconnect: () -> Void
}

@main
struct CATChunkStopRegression {
    static let a = "CQ CQ CQ DE EA3JIC EA3JIC EA3JIC K"   // 34 characters: more than one KY piece
    static let b = "TU EA3JIC TEST"                       // one KY piece
    static let wpm = 24

    static func main() {
        let tx500 = Lab599TX500Driver.shared
        let fx4cr = FX4CRDriver.shared
        let radios = [
            Radio(name: "TX-500", setConnected: { tx500.isConnected = $0 }, send: { tx500.sendMorse($0, wpm: $1) },
                  stop: { tx500.stopMorse() }, disconnect: { tx500.disconnect() }),
            Radio(name: "FX-4CR", setConnected: { fx4cr.isConnected = $0 }, send: { fx4cr.sendMorse($0, wpm: $1) },
                  stop: { fx4cr.stopMorse() }, disconnect: { fx4cr.disconnect() }),
        ]
        for radio in radios {
            radio.setConnected(true)
            _ = SerialLog.drain()
            for text in ["CQ;TX;", "CQ\u{001B}2", String(repeating: "E", count: 1025)] {
                radio.send(text, wpm)
                check("\(radio.name): unsafe or oversized text sends no commands", SerialLog.drain().isEmpty)
            }
            let window = control(radio)
            stopCancelsTheRest(radio, window)
            newMessageCancelsTheRest(radio, window)
            reconnectDoesNotReplayTheRest(radio, window)
            radio.setConnected(false)
        }

        if failures > 0 {
            print("CAT chunk stop regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("CAT chunk stop regression passed")
    }

    /// The message alone goes out whole: KS, then its KY pieces in order. Returns how long the checks below wait:
    /// one second more than the driver took to send the last piece here.
    static func control(_ radio: Radio) -> Double {
        let start = Date()
        radio.send(a, wpm)
        var log: [SerialWrite] = []
        while log.filter(isText).count < 2 && Date().timeIntervalSince(start) < 30 {
            run(0.1)
            log += SerialLog.drain()
        }
        run(1.0)
        log += SerialLog.drain()
        let pieces = log.filter(isText).map(kyText)
        check("\(radio.name): control: a message alone sets the speed and goes out whole, its KY pieces in order",
              log.first?.text == "KS024;" && pieces.count >= 2
                  && (pieces.joined() == a || pieces.joined(separator: " ") == a),
              show(log))
        let last = log.filter(isText).last?.time ?? start
        return last.timeIntervalSince(start) + 1.0
    }

    static func stopCancelsTheRest(_ radio: Radio, _ window: Double) {
        radio.send(a, wpm)
        radio.stop()
        run(window)
        let log = SerialLog.drain()
        let stopIndex = log.lastIndex(where: isStop)
        let after = stopIndex.map { log.suffix(from: log.index(after: $0)) } ?? log[...]
        check("\(radio.name): after STOP (KY ;RX;) nothing more of the message is written (\(String(format: "%.1f", window)) s)",
              log.contains(where: isStop) && after.isEmpty, show(log))
    }

    static func newMessageCancelsTheRest(_ radio: Radio, _ window: Double) {
        radio.send(a, wpm)
        run(0.2)
        radio.send(b, wpm)    // CWKeyerService.send() also calls stopMorse() first; the driver must not need it
        run(window)
        let log = SerialLog.drain()
        let after = log.drop(while: { $0.text != "KY \(b);" }).dropFirst()
        check("\(radio.name): a new message: no KY of the old one comes after it (the radio would key it after "
              + "or inside the new one)",
              log.contains(where: { $0.text == "KY \(b);" }) && !after.contains(where: isText), show(log))
        radio.stop()
        _ = SerialLog.drain()
    }

    static func reconnectDoesNotReplayTheRest(_ radio: Radio, _ window: Double) {
        radio.send(a, wpm)
        radio.disconnect()
        run(0.5)
        radio.setConnected(true)    // connected again, within the time the next piece was due
        run(window)
        let log = SerialLog.drain()
        check("\(radio.name): after a disconnect and a quick reconnect, the rest of the message is not written",
              log.filter(isText).count == 1, show(log))
    }
}
