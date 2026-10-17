import Foundation

// Behaviour test of CW texts with letters outside ASCII. A name or QTH with an accent goes out with the plain
// letter (JOSÉ → JOSE), and a text with a character that has no Morse (Ø, ß, an invisible no-break space…) is
// refused before anything is stopped or sent, with a refusal that names the character. Before, the keyer handed
// the text to the radio as typed and showed it as sent: the TX-500 and the FX-4CR drop a whole KY command that
// holds a character outside ASCII (their sendRaw converts with .ascii; checked here in their source), and the
// WinKeyer got bytes outside its range. It runs the real CWKeyerService against the recording stand-ins of
// Tests/Support/.
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/CWTextFoldingRegression.swift Tests/Support/TransmitGateStubs.swift \
//       Tests/Support/TransmitGateDXCCStub.swift YAAM/CWKeyerService.swift \
//       YAAM/TransmitIdentity.swift YAAM/GridLocator.swift -o folding && ./folding
// Nothing opens a port or a socket, and nothing is keyed. The operator is EA3JIC; José, Núria and Bjørn are
// invented first names, Gironès a QTH. Auto-CQ runs with a 1 s pause.

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

/// Runs the main loop until the condition holds or the time is up; returns whether it held.
@MainActor private func runUntil(_ seconds: Double, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return condition()
}

private func keyed(_ log: [String]) -> [String] { log.filter { $0.hasPrefix("KEYED") } }
private func shown(_ log: [String]) -> String { log.isEmpty ? "nothing" : log.joined(separator: " | ") }
private func source(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }

@main
struct CWTextFoldingRegression {
    static func main() {
        let keyer = CWKeyerService.shared
        keyer.sidetoneEnabled = false
        keyer.useCutNumbers = false
        keyer.wpm = 40
        keyer.autoCQIntervalSeconds = 1

        realDriversDropNonASCII()
        accentsAreFolded(keyer)
        nameFromTheLog(keyer)
        noMorseIsRefused(keyer)
        asciiIsUntouched(keyer)
        refusedTextDoesNotStopTheMessage(keyer)
        autoCQ(keyer)
        otherKeyers(keyer)

        if failures > 0 {
            print("CW text folding regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("CW text folding regression passed")
    }

    /// Every stand-in radio disconnected, then only the TX-500 connected (unless another mode is given), nothing
    /// going out, no refusal.
    static func reset(_ keyer: CWKeyerService, _ mode: CWTransmissionMode = .lab599TX500) {
        keyer.stop()
        WinKeyerDriver.shared.isConnected = false
        SerialKeyerDriver.shared.isConnected = false
        FX4CRDriver.shared.isConnected = false
        Lab599TX500Driver.shared.isConnected = false
        IcomUSBRadioDriver.shared.isConnected = false
        Xiegu6100Driver.shared.isConnected = false
        TCIClient.shared.isConnected = false
        FLRigClient.shared.isConnected = false
        keyer.rigControlClientRef = nil
        keyer.useCutNumbers = false
        keyer.transmissionMode = mode
        switch mode {
        case .lab599TX500: Lab599TX500Driver.shared.isConnected = true
        case .fx4cr: FX4CRDriver.shared.isConnected = true
        case .winkeyer: WinKeyerDriver.shared.isConnected = true
        default: break
        }
        keyer.transmitRefusal = ""
        _ = run(0.1)
    }

    // 0. What the real TX-500 and FX-4CR drivers do with such a text (the stand-ins only record it).

    static func realDriversDropNonASCII() {
        for path in ["YAAM/Lab599TX500Driver.swift", "YAAM/FX4CRDriver.swift"] {
            let driver = source(path)
            check("source: \(path)'s sendRaw still converts the command with .ascii (a KY with JOSÉ is dropped)",
                  driver.contains("guard let data = command.data(using: .ascii) else { return false }"))
        }
        check("control: a KY command with an accent has no ASCII form", "KY OP JOSÉ;".data(using: .ascii) == nil)
    }

    // 1. A live text with an accented name and QTH goes out with the plain letters.

    static func accentsAreFolded(_ keyer: CWKeyerService) {
        reset(keyer)
        keyer.send(text: "OP JOSÉ QTH GIRONÈS", myCall: "EA3JIC")
        let log = run(0.3)
        check("accents: the TX-500 gets the plain letters",
              keyed(log) == ["KEYED via Lab599 TX-500: OP JOSE QTH GIRONES"], shown(log))
        check("accents: the screen shows what goes out", keyer.activeBufferText == "OP JOSE QTH GIRONES",
              keyer.activeBufferText.debugDescription)
        check("accents: the recent list holds what went out", keyer.sentHistory.first == "OP JOSE QTH GIRONES",
              String(describing: keyer.sentHistory.first))
        check("accents: not refused, transmitting", keyer.transmitRefusal.isEmpty && keyer.isTransmitting,
              keyer.transmitRefusal.debugDescription)

        reset(keyer)
        keyer.send(text: "op josé, muñoz ç ü", myCall: "EA3JIC")
        let lower = run(0.3)
        check("accents: lower case and Ñ, Ç, Ü are folded too",
              keyed(lower) == ["KEYED via Lab599 TX-500: op jose, munoz c u"], shown(lower))
        keyer.stop()
    }

    // 2. A name from the log entry, through the {NAME} macro.

    static func nameFromTheLog(_ keyer: CWKeyerService) {
        reset(keyer)
        keyer.send(text: "OP {NAME}", myCall: "EA3JIC", call: "0A1BC", name: "Núria")
        let log = run(0.3)
        check("{NAME} Núria goes out as NURIA", keyed(log) == ["KEYED via Lab599 TX-500: OP NURIA"], shown(log))
        keyer.stop()
    }

    // 3. A character with no Morse: nothing keyed, nothing shown as sent, the refusal names it.

    static func noMorseIsRefused(_ keyer: CWKeyerService) {
        reset(keyer)
        keyer.sentHistory = []
        keyer.send(text: "OP BJØRN", myCall: "EA3JIC")
        var log = run(0.3)
        check("Ø: nothing is keyed", keyed(log).isEmpty, shown(log))
        check("Ø: not transmitting, nothing on screen", !keyer.isTransmitting && keyer.activeBufferText.isEmpty,
              "isTransmitting \(keyer.isTransmitting), text \(keyer.activeBufferText.debugDescription)")
        check("Ø: the refusal names Ø", keyer.transmitRefusal.contains("Ø"), keyer.transmitRefusal.debugDescription)
        check("Ø: the refused text is not put in the recent list", !keyer.sentHistory.contains { $0.contains("BJ") },
              keyer.sentHistory.description)

        reset(keyer)
        keyer.send(text: "{NAME} ß Æ ß", myCall: "EA3JIC", name: "Bjørn")
        log = run(0.3)
        check("ß, Æ and Ø from {NAME}: nothing is keyed", keyed(log).isEmpty, shown(log))
        let refusal = keyer.transmitRefusal
        check("ß, Æ and Ø: each is named once",
              ["Ø", "ß", "Æ"].allSatisfy { ch in refusal.components(separatedBy: ch).count == 2 }, refusal.debugDescription)

        reset(keyer)
        keyer.send(text: "QTH\u{00A0}GIRONA", myCall: "EA3JIC")
        log = run(0.3)
        check("a no-break space: nothing is keyed", keyed(log).isEmpty, shown(log))
        check("a no-break space: the refusal names it by its code, as it cannot be seen",
              keyer.transmitRefusal.contains("U+00A0"), keyer.transmitRefusal.debugDescription)

        reset(keyer, .audioOnly)
        keyer.send(text: "OP BJØRN", myCall: "EA3JIC")
        _ = run(0.2)
        check("Ø in Audio Sidetone Only: refused too (the sidetone has no Morse for it either)",
              keyer.transmitRefusal.contains("Ø") && !keyer.isTransmitting, keyer.transmitRefusal.debugDescription)

        reset(keyer)
        keyer.send(text: "OP BJØRN", myCall: "")
        check("control: with no callsign, the callsign refusal comes first",
              keyer.transmitRefusal == TransmitIdentity.callsignMissingMessage, keyer.transmitRefusal.debugDescription)
    }

    // 4. ASCII is left exactly as it is; cut numbers still apply.

    static func asciiIsUntouched(_ keyer: CWKeyerService) {
        reset(keyer)
        keyer.send(text: "AR K = ? / . , - @ !", myCall: "EA3JIC")
        var log = run(0.3)
        check("control: ASCII punctuation goes out as it is",
              keyed(log) == ["KEYED via Lab599 TX-500: AR K = ? / . , - @ !"], shown(log))
        check("control: ASCII is not refused", keyer.transmitRefusal.isEmpty, keyer.transmitRefusal.debugDescription)
        keyer.stop()
        _ = run(0.1)
        for text in ["CQ;TX;", "CQ\u{001B}2", "CQ ^ ~ `"] {
            keyer.send(text: text, myCall: "EA3JIC")
            check("unsupported or command-bearing text is refused: \(text.debugDescription)",
                  !keyer.transmitRefusal.isEmpty && keyed(run(0.05)).isEmpty)
        }

        reset(keyer)
        keyer.useCutNumbers = true
        keyer.send(text: "UR 599 JOSÉ", myCall: "EA3JIC")
        log = run(0.3)
        check("cut numbers still apply, with the accent folded",
              keyed(log) == ["KEYED via Lab599 TX-500: UR 5NN JOSE"], shown(log))
        keyer.useCutNumbers = false
        keyer.stop()
    }

    // 5. A refused text does not stop a message under way (as the callsign refusal does not).

    static func refusedTextDoesNotStopTheMessage(_ keyer: CWKeyerService) {
        reset(keyer)
        keyer.wpm = 15
        keyer.send(text: "CQ CQ DE EA3JIC EA3JIC K", myCall: "EA3JIC")
        var log = run(0.3)
        check("control: the first message goes out", keyed(log) == ["KEYED via Lab599 TX-500: CQ CQ DE EA3JIC EA3JIC K"],
              shown(log))
        keyer.send(text: "OP BJØRN", myCall: "EA3JIC")
        log = run(0.3)
        check("a refused text keys nothing", keyed(log).isEmpty, shown(log))
        check("a refused text leaves the message under way on screen",
              keyer.isTransmitting && keyer.activeBufferText == "CQ CQ DE EA3JIC EA3JIC K",
              "isTransmitting \(keyer.isTransmitting), text \(keyer.activeBufferText.debugDescription)")
        check("the refusal is shown meanwhile", keyer.transmitRefusal.contains("Ø"), keyer.transmitRefusal.debugDescription)
        keyer.stop()
        keyer.wpm = 40
    }

    // 6. Auto-CQ with a template that has no Morse: it ends at once, keys nothing, and the refusal stays.

    static func autoCQ(_ keyer: CWKeyerService) {
        reset(keyer)
        keyer.startAutoCQ(template: "CQ DE {MYCALL} OP BJØRN", myCall: "EA3JIC")
        let ended = runUntil(3) { !keyer.isAutoCQActive }
        let log = KeyLog.drain()
        check("Auto-CQ with Ø: it ends", ended)
        check("Auto-CQ with Ø: nothing is keyed", keyed(log).isEmpty, shown(log))
        check("Auto-CQ with Ø: the refusal names Ø", keyer.transmitRefusal.contains("Ø"), keyer.transmitRefusal.debugDescription)
        keyer.stop()

        reset(keyer)
        keyer.startAutoCQ(template: "CQ DE {MYCALL} OP JOSÉ", myCall: "EA3JIC")
        let first = run(0.3)
        check("Auto-CQ with É: the CQ goes out folded", keyed(first) == ["KEYED via Lab599 TX-500: CQ DE EA3JIC OP JOSE"],
              shown(first))
        keyer.stop()
    }

    // 7. The folded text is what every keyer gets, not only the TX-500.

    static func otherKeyers(_ keyer: CWKeyerService) {
        for (mode, via) in [(CWTransmissionMode.fx4cr, "FX-4CR"), (.winkeyer, "WinKeyer")] {
            reset(keyer, mode)
            keyer.send(text: "OP JOSÉ", myCall: "EA3JIC")
            var log = run(0.3)
            check("\(via): gets the plain letters", keyed(log) == ["KEYED via \(via): OP JOSE"], shown(log))
            keyer.send(text: "OP BJØRN", myCall: "EA3JIC")
            log = run(0.3)
            check("\(via): Ø is refused and nothing is keyed", keyed(log).isEmpty && keyer.transmitRefusal.contains("Ø"),
                  "\(shown(log)); \(keyer.transmitRefusal.debugDescription)")
            keyer.stop()
        }
    }
}
