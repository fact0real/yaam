import Foundation

// Behaviour test of the keyer's end-of-message clock when no sidetone is played (the sidetone off, and always for
// TCI): the screen stays ON AIR until the radio has keyed the whole message, plus a short tail, and then goes idle.
// The radio's keying time is computed here with the test's own PARIS timing, key-down to key-up (unit 1.2/WPM s;
// dit 1, dah 3; gaps 1 inside a letter, 3 between letters, 7 between words; PARIS = 43 units). It runs the real
// CWKeyerService against the recording stand-ins of Tests/Support/, through TCI and a TX-500. The clock with the
// sidetone on is not measured here: it plays audio.
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/CWSilentClockRegression.swift Tests/Support/TransmitGateStubs.swift \
//       Tests/Support/TransmitGateDXCCStub.swift YAAM/CWKeyerService.swift YAAM/TransmitIdentity.swift \
//       YAAM/GridLocator.swift -o cwclock && ./cwclock
// Nothing opens a port or a socket, and nothing is keyed. The operator is EA3JIC; the other station is invented
// (0A1BC). 40 and 50 WPM, so that the test takes about 15 s.

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

private func keyed(_ log: [String]) -> [String] { log.filter { $0.hasPrefix("KEYED") } }
private func seconds(_ s: Double) -> String { String(format: "%.2f s", s) }

/// The test's own Morse table: only the characters it sends.
private let elements: [Character: String] = [
    "0": "-----", "1": ".----", "3": "...--", "5": ".....", "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".",
    "I": "..", "J": ".---", "K": "-.-", "N": "-.", "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
]

/// Units from the first key-down to the last key-up.
private func parisUnits(_ text: String) -> Int {
    var total = 0
    for (w, word) in text.split(separator: " ").enumerated() {
        if w > 0 { total += 7 }
        for (c, char) in word.enumerated() {
            if c > 0 { total += 3 }
            let e = elements[char] ?? ""
            total += e.reduce(0) { $0 + ($1 == "." ? 1 : 3) } + max(0, e.count - 1)
        }
    }
    return total
}

/// One message: when the screen went idle (seconds after send()), and the characters it showed meanwhile.
@MainActor private func measure(_ keyer: CWKeyerService, _ text: String, limit: Double) -> (idle: Double?, chars: [String]) {
    let start = Date()
    keyer.send(text: text, myCall: "EA3JIC")
    var chars: [String] = []
    while keyer.isTransmitting && Date().timeIntervalSince(start) < limit {
        let c = keyer.currentlyTransmittingChar
        if !c.isEmpty && c != chars.last { chars.append(c) }
        run(0.005)
    }
    return (keyer.isTransmitting ? nil : Date().timeIntervalSince(start), chars)
}

@main
struct CWSilentClockRegression {
    static func main() {
        check("control: PARIS is 43 units key-down to key-up", parisUnits("PARIS") == 43, "\(parisUnits("PARIS"))")
        check("control: \"0A1BC 5NN TT1\" is 141 units", parisUnits("0A1BC 5NN TT1") == 141, "\(parisUnits("0A1BC 5NN TT1"))")

        let keyer = CWKeyerService.shared
        keyer.sidetoneEnabled = false
        keyer.useCutNumbers = false

        keyer.transmissionMode = .tci
        TCIClient.shared.isConnected = true
        message(keyer, "0A1BC 5NN TT1", wpm: 50, via: "TCI")
        message(keyer, "TTTTT", wpm: 50, via: "TCI")
        stopDuringTheTail(keyer)
        TCIClient.shared.isConnected = false

        keyer.transmissionMode = .lab599TX500
        Lab599TX500Driver.shared.isConnected = true
        message(keyer, "0A1BC 5NN TT1", wpm: 40, via: "Lab599 TX-500")
        message(keyer, "CQ DE EA3JIC K", wpm: 40, via: "Lab599 TX-500")
        Lab599TX500Driver.shared.isConnected = false

        if failures > 0 {
            print("CW silent clock regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("CW silent clock regression passed")
    }

    static func message(_ keyer: CWKeyerService, _ text: String, wpm: Int, via radio: String) {
        keyer.wpm = wpm
        run(0.1)
        _ = KeyLog.drain()
        let unit = 1.2 / Double(wpm)
        let real = Double(parisUnits(text)) * unit
        // The keyer's clock: the real Morse, 3 more units per word gap and after the last letter, and the 0.3 s tail.
        let spaces = text.filter { $0 == " " }.count
        let expected = real + Double(3 * (spaces + 1)) * unit + 0.3
        let label = "\(radio), \(wpm) WPM, \"\(text)\""
        let m = measure(keyer, text, limit: expected * 2 + 5)
        check("\(label): the text goes out", keyed(KeyLog.drain()) == ["KEYED via \(radio): \(text)"])
        check("\(label): still ON AIR when the radio ends its Morse (\(seconds(real)))",
              (m.idle ?? .infinity) >= real, "idle after \(m.idle.map(seconds) ?? "never")")
        check("\(label): still ON AIR 0.3 s after that (\(seconds(real + 0.3)))",
              (m.idle ?? .infinity) >= real + 0.3, "idle after \(m.idle.map(seconds) ?? "never")")
        // Each of the clock's short sleeps may wake a few milliseconds late, which adds up over a message.
        let latest = expected * 1.3 + 0.3
        check("\(label): idle soon after (by \(seconds(latest)))",
              m.idle != nil && m.idle! <= latest, "idle after \(m.idle.map(seconds) ?? "never")")
        // what the screen can show: each character in turn, the same one twice in a row counting once
        let shownInTurn = text.map(String.init).reduce(into: [String]()) { if $1 != $0.last { $0.append($1) } }
        check("\(label): the screen followed the text, letter by letter",
              m.chars.filter { $0 != " " } == shownInTurn.filter { $0 != " " }, m.chars.joined())
    }

    // STOP during the tail ends the message at once, as STOP during the Morse does.
    static func stopDuringTheTail(_ keyer: CWKeyerService) {
        keyer.wpm = 50
        run(0.1)
        let text = "TTTTT"
        let unit = 1.2 / 50.0
        let start = Date()
        keyer.send(text: text, myCall: "EA3JIC")
        // after the last letter and its 3 units, inside the tail
        let inTail = Double(parisUnits(text) + 3) * unit + 0.1
        while Date().timeIntervalSince(start) < inTail { run(0.005) }
        let wasOn = keyer.isTransmitting
        keyer.stop()
        check("STOP inside the tail: the message was still ON AIR", wasOn)
        check("STOP inside the tail: idle at once", !keyer.isTransmitting && keyer.activeBufferText.isEmpty)
        run(0.5)
        check("STOP inside the tail: still idle 0.5 s later", !keyer.isTransmitting)
        _ = KeyLog.drain()
    }
}
