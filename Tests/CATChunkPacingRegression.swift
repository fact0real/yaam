import Foundation

// Behaviour test of CW sent over CAT to a Lab599 TX-500 or an FX-4CR (Kenwood KY): a text longer than one KY piece
// reaches the radio whole, whichever way the radio treats a KY that comes while it is still keying. Lab599's CAT
// document does not say: the radio may queue KY texts, or refuse one while it is busy. Before this change, the
// drivers cut the text every 24 characters, inside words, and sent each later piece 1.5 s after the one before,
// while the radio was still keying (a piece of 24 characters takes 5 to 27 s): a radio that refuses lost the
// middle of every long message, without a word.
//
// It runs the real YAAM/Lab599TX500Driver.swift and YAAM/FX4CRDriver.swift against the stand-ins of Tests/Support/
// (a recording SerialPortService and an FT8808Engine module that lists no audio devices). Behind the stand-in port,
// CATRadio models the radio's keyer: it reads KS and KY and keys each text it accepts with this test's OWN Morse
// clock (paris() below, not MorseTiming), from 80 ms after the text arrives. Model "queue" accepts every KY; model
// "refuse" drops a KY that arrives while the one before is still being keyed. Both drivers, both models, at 40 WPM.
// The test marks a driver connected directly (never connect(), which would open a port).
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
//       Tests/CATChunkPacingRegression.swift Tests/Support/CATDriverStandIns.swift \
//       YAAM/Lab599TX500Driver.swift YAAM/FX4CRDriver.swift YAAM/Lab599TX500SMeter.swift YAAM/MorseTiming.swift YAAM/TransmitShutdown.swift \
//       -o w/catpace && w/catpace
// Instead of the stand-in module, the package's own build can be used (-I and -L on an ft8-808 build, as
// Tests/TransmitGatesFT8Regression.swift describes). Nothing opens a port, a socket or a device, and nothing is
// keyed. The operator is EA3JIC; the other station (0A1BC) and the name (Josep) are invented. It takes about three
// minutes: every message is keyed in real time, twelve times.

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

@MainActor private func run(_ seconds: Double) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

// MARK: - The test's own Morse clock

nonisolated private let morse: [Character: String] = [
    "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.", "H": "....", "I": "..",
    "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---", "P": ".--.", "Q": "--.-", "R": ".-.",
    "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--", "Z": "--..",
    "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-", "5": ".....", "6": "-....", "7": "--...",
    "8": "---..", "9": "----.", "?": "..--..", "/": "-..-.",
]

/// PARIS timing, first key-down to last key-up: every element is followed by a 1-unit gap, every character by 2
/// more (3 in all) and every space by 4 more (7 in all); the gaps after the last element are not keyed.
nonisolated private func paris(_ text: String, _ wpm: Int) -> TimeInterval {
    var units = 0
    var trailing = 0
    for c in text {
        if c == " " {
            if units > 0 { units += 4; trailing += 4 }
            continue
        }
        guard let code = morse[c] else { continue }
        for e in code { units += (e == "." ? 1 : 3) + 1 }
        units += 2
        trailing = 3
    }
    return Double(max(0, units - trailing)) * 1.2 / Double(wpm)
}

private func handover(_ wpm: Int) -> TimeInterval { max(0.3, 7 * 1.2 / Double(wpm)) }

private func near(_ x: Double, _ y: Double) -> Bool { abs(x - y) < 0.001 }

// MARK: - The two drivers

@MainActor struct Radio {
    let name: String
    let setConnected: (Bool) -> Void
    let send: (String, Int) -> Void
}

@main
struct CATChunkPacingRegression {
    static let wpm = 40
    static let a = "CQ CQ CQ DE EA3JIC EA3JIC EA3JIC K"
    static let r = "TNX FER CALL BT OP JOSEP ES QTH ANDORRA BT HW CPY? 0A1BC DE EA3JIC K"
    static let w = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123"
    static let pieces: [String: [String]] = [
        a: ["CQ CQ CQ DE EA3JIC", "EA3JIC EA3JIC K"],
        r: ["TNX FER CALL BT OP JOSEP", "ES QTH ANDORRA BT HW", "CPY? 0A1BC DE EA3JIC K"],
        w: ["ABCDEFGHIJKLMNOPQRSTUVWX", "YZ0123"],
    ]
    static let label = [a: "A (34 characters)", r: "R (68 characters)", w: "W (30 characters, no space)"]

    static func main() {
        unitChecks()

        let tx500 = Lab599TX500Driver.shared
        let fx4cr = FX4CRDriver.shared
        let radios = [
            Radio(name: "TX-500", setConnected: { tx500.isConnected = $0 }, send: { tx500.sendMorse($0, wpm: $1) }),
            Radio(name: "FX-4CR", setConnected: { fx4cr.isConnected = $0 }, send: { fx4cr.sendMorse($0, wpm: $1) }),
        ]
        for (model, modelName) in [(CATRadio.Model.queue, "radio that queues KY"),
                                   (CATRadio.Model.refuse, "radio that refuses a KY while busy")] {
            for radio in radios {
                CATRadio.use(model, keyingSeconds: { paris($0, $1) })
                radio.setConnected(true)
                _ = SerialLog.drain()
                for message in [a, r, w] {
                    pacing(radio, "\(radio.name), \(modelName)", message)
                }
                radio.setConnected(false)
            }
        }
        CATRadio.use(.none, keyingSeconds: { _, _ in 0 })

        if failures > 0 {
            print("CAT chunk pacing regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("CAT chunk pacing regression passed")
    }

    // MARK: - The Morse timing and the cut, on their own

    static func unitChecks() {
        check("MorseTiming: PARIS at 24 WPM is 43 units, 2.15 s, key-down to key-up (50 units with the word gap "
              + "that follows it: PARIS PARIS is 93 units)",
              near(MorseTiming.duration(of: "PARIS", wpm: 24), 2.15) && near(MorseTiming.duration(of: "PARIS PARIS", wpm: 24), 4.65),
              "\(MorseTiming.duration(of: "PARIS", wpm: 24)) \(MorseTiming.duration(of: "PARIS PARIS", wpm: 24))")
        check("MorseTiming: CQ TEST EA3JIC EA3JIC TEST at 24 WPM lasts 10.95 s",
              near(MorseTiming.duration(of: "CQ TEST EA3JIC EA3JIC TEST", wpm: 24), 10.95),
              "\(MorseTiming.duration(of: "CQ TEST EA3JIC EA3JIC TEST", wpm: 24))")
        check("the test's own clock gives the same three figures",
              near(paris("PARIS", 24), 2.15) && near(paris("PARIS PARIS", 24), 4.65)
                  && near(paris("CQ TEST EA3JIC EA3JIC TEST", 24), 10.95))
        check("MorseTiming: the gap between pieces is a word gap, at least 0.3 s (0.3 s at 40 WPM, 0.84 s at 10 WPM)",
              near(MorseTiming.handover(wpm: 40), 0.3) && near(MorseTiming.handover(wpm: 10), 0.84))
        for message in [a, r, w] {
            check("MorseTiming.chunks: \(label[message]!) is cut into \(pieces[message]!.map { "\"\($0)\"" }.joined(separator: " + "))",
                  MorseTiming.chunks(of: message, limit: 24) == pieces[message]!,
                  MorseTiming.chunks(of: message, limit: 24).joined(separator: " | "))
        }
    }

    // MARK: - One message through one driver to one radio model

    static func pacing(_ radio: Radio, _ name: String, _ message: String) {
        let start = Date()
        radio.send(message, wpm)
        repeat { run(0.2) } while Date().timeIntervalSince(start) < 120
            && (Date().timeIntervalSince(start) < 1.0 || Date() < CATRadio.busyUntil().addingTimeInterval(1.5))
        let written = SerialLog.drain().filter { $0.text.hasPrefix("KY ") && $0.text != "KY ;RX;" }
            .map { String($0.text.dropFirst(3).dropLast()) }
        let (keyed, refused) = CATRadio.drain()
        let accepted = keyed.map(\.text)
        let what = "\(name), \(label[message]!)"

        check("\(what): the radio keys the whole message", accepted.joined() == message
                  || accepted.joined(separator: " ") == message,
              "keyed: " + accepted.joined(separator: " | ") + "; refused: " + refused.map(\.text).joined(separator: " | "))

        // Every KY that reached the radio after the first, accepted or not, in order of arrival.
        var events: [(arrival: Date, accepted: Keyed?)] = keyed.map { ($0.arrival, $0) } + refused.map { ($0.arrival, nil) }
        events.sort { $0.arrival < $1.arrival }
        var lastEnd: Date? = nil
        var early: [String] = []
        var late: [String] = []
        for event in events {
            if let end = lastEnd {
                let gap = event.arrival.timeIntervalSince(end)
                if gap < 0 { early.append(String(format: "%.2f s before the end", -gap)) }
                if gap > handover(wpm) + 0.5 { late.append(String(format: "%.2f s after the end", gap)) }
            }
            if let k = event.accepted { lastEnd = k.end }
        }
        check("\(what): no KY reaches the radio while it is still keying the one before", early.isEmpty,
              early.joined(separator: ", "))
        check("\(what): each later piece comes within the gap + 0.5 s of the end of the one before", late.isEmpty,
              late.joined(separator: ", "))
        check("\(what): the KY pieces are at most 24 characters, cut at spaces (a longer word at 24), with no space "
              + "at either end", written == pieces[message]!, written.joined(separator: " | "))
    }
}

typealias Keyed = CATRadio.Keyed
