import Foundation

// Behaviour test of CW through a WinKeyer: a message stays "transmitting" until the WinKeyer reports its end,
// Auto-CQ does not cut its own CQ, and a message sent during its pause goes out whole and ends Auto-CQ. It runs
// the real CWKeyerService against the recording stand-ins of Tests/Support/, whose WinKeyerDriver does what the
// real driver does (checked below in the source of YAAM/WinKeyerDriver.swift). The WinKeyer "reports the end"
// when the test calls its completion callback, as the real driver does when the WinKeyer's status byte says it is
// no longer busy.
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/WinKeyerAutoCQRegression.swift Tests/Support/TransmitGateStubs.swift \
//       Tests/Support/TransmitGateDXCCStub.swift YAAM/CWKeyerService.swift YAAM/TransmitIdentity.swift \
//       YAAM/GridLocator.swift -o wkq && ./wkq
// Nothing opens a port or a socket, and nothing is keyed. The operator is EA3JIC; the other station is invented
// (0A1BC). Auto-CQ runs with a 1 s pause so that the test takes a few seconds.

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

/// Lets the keyer's background tasks run for a while, then returns what reached the (stand-in) WinKeyer.
@MainActor private func run(_ seconds: Double) -> [String] {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    return KeyLog.drain()
}

private func keyed(_ log: [String]) -> [String] { log.filter { $0.hasPrefix("KEYED") } }

/// The WinKeyer says it has finished sending (as WinKeyerDriver does on a status byte with the busy bit clear).
@MainActor private func winKeyerFinishes() {
    WinKeyerDriver.shared.isTransmitting = false
    WinKeyerDriver.shared.onTransmissionComplete?()
}

private func source(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }

private func slice(_ text: String, from start: String, to end: String) -> String {
    guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { return "" }
    return String(text[a.lowerBound..<b.lowerBound])
}

@main
struct WinKeyerAutoCQRegression {
    static let cq = "CQ TEST {MYCALL} {MYCALL} TEST"
    static let cqSent = "KEYED via WinKeyer: CQ TEST EA3JIC EA3JIC TEST"

    static func main() {
        realDriverMatchesStandIn()

        let keyer = CWKeyerService.shared
        keyer.transmissionMode = .winkeyer
        keyer.sidetoneEnabled = false
        keyer.useCutNumbers = false
        keyer.autoCQIntervalSeconds = 1
        WinKeyerDriver.shared.isConnected = true

        messageEndsWithTheWinKeyer(keyer)
        autoCQDoesNotCutItsOwnCQ(keyer)
        aReplyDuringThePauseEndsAutoCQ(keyer)

        if failures > 0 {
            print("WinKeyer Auto-CQ regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("WinKeyer Auto-CQ regression passed")
    }

    // MARK: - The stand-in does what the real driver does

    static func realDriverMatchesStandIn() {
        let driver = source("YAAM/WinKeyerDriver.swift")
        let abort = slice(driver, from: "public func abort(reportEnd: Bool = true) {", to: "// MARK: - Raw I/O")
        let send = slice(driver, from: "public func sendMorseText(", to: "public func abort(")
        check("the real WinKeyerDriver.abort() clears the WinKeyer, marks it idle and, unless told not to, reports the end at once",
              abort.contains("sendRawBytes([0x0A])") && abort.contains("self.isTransmitting = false\n") &&
              abort.contains("if reportEnd { onTransmissionComplete?() }"))
        check("the real WinKeyerDriver.sendMorseText marks the WinKeyer busy",
              send.contains("self.isTransmitting = true"))
        check("the real driver reports completion only after idle and all queued text has been echoed",
              driver.contains("if !hardwareBusy, pendingText.isEmpty, outstandingText.isEmpty, isTransmitting {"))
    }

    // MARK: - A message lasts until the WinKeyer has sent it

    static func messageEndsWithTheWinKeyer(_ keyer: CWKeyerService) {
        keyer.send(text: cq, myCall: "EA3JIC")
        let log = run(0.3)
        check("the CQ goes to the WinKeyer", keyed(log) == [cqSent], log.joined(separator: " | "))
        check("while the WinKeyer sends it, the keyer says it is transmitting (the end reported by the abort() that "
              + "send() does first does not count)", keyer.isTransmitting)
        winKeyerFinishes()
        _ = run(0.1)
        check("when the WinKeyer reports the end, the keyer stops saying it is transmitting", !keyer.isTransmitting)
        keyer.stop()
        _ = run(0.1)
    }

    // MARK: - Auto-CQ sends the whole CQ

    static func autoCQDoesNotCutItsOwnCQ(_ keyer: CWKeyerService) {
        keyer.startAutoCQ(template: cq, myCall: "EA3JIC")
        let first = run(2.5)
        check("Auto-CQ: while the WinKeyer is still sending a CQ, no new CQ clears it (2.5 s with a 1 s pause)",
              keyed(first) == [cqSent], first.joined(separator: " | "))
        winKeyerFinishes()
        let next = run(1.6)
        check("Auto-CQ: after the WinKeyer reports the end and the pause, the next CQ goes out",
              keyed(next) == [cqSent], next.joined(separator: " | "))
        keyer.stopAutoCQ()
        keyer.stop()
        _ = run(0.2)
    }

    // MARK: - A reply sent during the pause goes out whole and ends Auto-CQ

    static func aReplyDuringThePauseEndsAutoCQ(_ keyer: CWKeyerService) {
        keyer.startAutoCQ(template: cq, myCall: "EA3JIC")
        _ = run(0.3)
        winKeyerFinishes()           // the CQ is over: the 1 s pause starts
        _ = run(0.3)
        keyer.send(text: "{CALL} 5NN", myCall: "EA3JIC", call: "0A1BC")
        let during = run(2.0)        // the pause ends while the reply is still being sent
        check("Auto-CQ: a reply sent during the pause goes out", keyed(during).first == "KEYED via WinKeyer: 0A1BC 5NN",
              during.joined(separator: " | "))
        check("Auto-CQ: no CQ is sent over the reply while the WinKeyer is still sending it",
              keyed(during) == ["KEYED via WinKeyer: 0A1BC 5NN"], during.joined(separator: " | "))
        winKeyerFinishes()           // the reply is over
        let after = run(0.5)
        check("Auto-CQ: a reply sent during the pause ends Auto-CQ: no CQ follows",
              !keyer.isAutoCQActive && keyed(after).isEmpty, after.joined(separator: " | "))
        keyer.stopAutoCQ()
        keyer.stop()
        _ = run(0.2)
    }
}
