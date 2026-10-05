import Foundation

// A WebSDR reply is composed as "<partner> <monitored target> ..." and sent by the FT8 Station as
// the callsign it was configured with, on the WebSDR dial. WebSDRReplyGuard decides whether that
// is allowed. Build and run from the repository root (DEVELOPER_DOCUMENTATION.md section 8.2):
//   swiftc -parse-as-library Tests/WebSDRReplyGuardRegression.swift YAAM/WebSDRReplyPlanner.swift \
//       -o /tmp/wrg && /tmp/wrg
// The dial tables are read as text from YAAM/FT8EngineService.swift (FT8BandPreset.common) and
// YAAM/WebSDRFT8Monitor.swift (WebSDRFT8Monitor.bands), so the test checks the tables the app uses.
// The engine and the view cannot be compiled on their own, so their calls to the guard are
// checked in the source text.

@main
struct WebSDRReplyGuardRegression {
    static func main() {
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print("\(ok ? "PASS" : "FAIL") \(name)")
            if !ok { failures += 1 }
        }

        // Identity: only the operator's own callsign may be the monitored target. The operator's
        // callsign is EA3JIC in one run and EP2AES in the other; both get the same checks. Refused
        // and near-miss cases use sample calls.
        for own in ["EA3JIC", "EP2AES"] {
            check("\(own) as the operator: own callsign is accepted",
                  WebSDRReplyGuard.identityIssue(target: own, ownCallsign: own) == nil)
            check("\(own) as the operator: case and surrounding spaces are ignored",
                  WebSDRReplyGuard.identityIssue(target: " \(own.lowercased())\n",
                                                 ownCallsign: own.capitalized + " ") == nil)
            let foreign = WebSDRReplyGuard.identityIssue(target: "K1ABC", ownCallsign: own)
            check("\(own) as the operator: foreign target K1ABC is refused", foreign != nil)
            check("\(own) as the operator: the refusal names the own callsign",
                  foreign == "Replies are sent as your own station (\(own)).")
            check("\(own) as the operator: an empty target is refused",
                  WebSDRReplyGuard.identityIssue(target: "  ", ownCallsign: own) != nil)
        }
        // Near misses, with sample calls: a longer or shorter callsign, and a portable suffix.
        check("a longer or shorter callsign is refused",
              WebSDRReplyGuard.identityIssue(target: "K1ABC1", ownCallsign: "K1ABC") != nil
              && WebSDRReplyGuard.identityIssue(target: "K1ABC", ownCallsign: "K1ABC1") != nil)
        check("another sample callsign, VK2ABC, is refused",
              WebSDRReplyGuard.identityIssue(target: "VK2ABC", ownCallsign: "K1ABC") != nil)
        check("a portable suffix must match on both sides",
              WebSDRReplyGuard.identityIssue(target: "K1ABC/P", ownCallsign: "K1ABC") != nil
              && WebSDRReplyGuard.identityIssue(target: "K1ABC", ownCallsign: "K1ABC/P") != nil
              && WebSDRReplyGuard.identityIssue(target: "K1ABC/P", ownCallsign: "K1ABC/P") == nil)
        check("no station callsign configured: refused, even when the target says DEFAULT",
              !WebSDRReplyGuard.targetIsOwnCallsign("DEFAULT", ownCallsign: "DEFAULT")
              && !WebSDRReplyGuard.targetIsOwnCallsign("K1ABC", ownCallsign: "DEFAULT")
              && !WebSDRReplyGuard.targetIsOwnCallsign("", ownCallsign: ""))
        check("no station callsign configured: the refusal points to Settings",
              WebSDRReplyGuard.identityIssue(target: "K1ABC", ownCallsign: "DEFAULT")?
                  .contains("Settings") == true)

        // Dial: only an FT8 band preset dial may become the TX dial.
        let ft8 = tableDials("YAAM/FT8EngineService.swift", from: "struct FT8BandPreset",
                             to: "struct FT4BandPreset", key: "frequencyHz")
        check("FT8BandPreset.common was read from the source (\(ft8.count) dials)", !ft8.isEmpty)
        check("7.074 MHz is allowed", WebSDRReplyGuard.dialIssue(dialHz: 7_074_000, ft8DialsHz: ft8) == nil)
        check("14.074 MHz is allowed", WebSDRReplyGuard.dialIssue(dialHz: 14_074_000, ft8DialsHz: ft8) == nil)
        check("every FT8 preset dial is allowed",
              ft8.allSatisfy { WebSDRReplyGuard.dialIssue(dialHz: $0, ft8DialsHz: ft8) == nil })
        let manual40 = WebSDRReplyGuard.dialIssue(dialHz: 7_250_000, ft8DialsHz: ft8)
        check("7.250 MHz is refused", manual40 != nil)
        check("3.850 MHz is refused", WebSDRReplyGuard.dialIssue(dialHz: 3_850_000, ft8DialsHz: ft8) != nil)
        check("the refusal describes what works: band preset, start receive, pick the message again",
              manual40 == "The WebSDR dial is not an FT8 band preset. "
                  + "Use band preset, start receive and pick the message again.")
        check("a dial 1 Hz or 1 kHz away from a preset is refused",
              WebSDRReplyGuard.dialIssue(dialHz: 7_074_001, ft8DialsHz: ft8) != nil
              && WebSDRReplyGuard.dialIssue(dialHz: 7_073_999, ft8DialsHz: ft8) != nil
              && WebSDRReplyGuard.dialIssue(dialHz: 7_075_000, ft8DialsHz: ft8) != nil)
        check("0 Hz is refused", WebSDRReplyGuard.dialIssue(dialHz: 0, ft8DialsHz: ft8) != nil)
        let receiver = tableDials("YAAM/WebSDRFT8Monitor.swift",
                                  from: "static let bands: [WebSDRFT8Band] = [", to: "\n    ]", key: "dialHz")
        check("WebSDRFT8Monitor.bands was read from the source (\(receiver.count) dials)", !receiver.isEmpty)
        check("every WebSDR band-preset dial is allowed, so picking a band never trips the guard",
              receiver.allSatisfy { WebSDRReplyGuard.dialIssue(dialHz: $0, ft8DialsHz: ft8) == nil })

        // Retune: the reply is only valid on the dial where it was prepared.
        check("same dial is accepted", WebSDRReplyGuard.retuneIssue(plannedDialHz: 14_074_000,
                                                                    currentDialHz: 14_074_000) == nil)
        check("another band is refused", WebSDRReplyGuard.retuneIssue(plannedDialHz: 14_074_000,
                                                                      currentDialHz: 7_074_000) != nil)
        check("no recorded dial is refused", WebSDRReplyGuard.retuneIssue(plannedDialHz: nil,
                                                                          currentDialHz: 14_074_000) != nil)
        check("the rules can be called off the main actor", offMainActor())
        check("WebSDRReplyGuard is declared nonisolated, as the app's default isolation is the main actor",
              sourceText("YAAM/WebSDRReplyPlanner.swift")?.contains("nonisolated enum WebSDRReplyGuard") == true)

        // Call sites: the rules only protect the transmitter if the engine and the view call them.
        let engine = functionBody("func prepareWebSDRReply(", in: "YAAM/FT8EngineService.swift")
        check("prepareWebSDRReply calls WebSDRReplyGuard.dialIssue with the FT8BandPreset dials, "
              + "before it changes the station or the dial",
              before("WebSDRReplyGuard.dialIssue(", "configureStation(", in: engine)
              && before("FT8BandPreset.common", "configureStation(", in: engine)
              && before("WebSDRReplyGuard.dialIssue(", "dialFrequencyHz = dialHz", in: engine))
        check("prepareWebSDRReply configures the station with the callsign it is given, not the target",
              engine?.contains("configureStation(callsign: stationCallsign,") == true)
        let queue = functionBody("func queueWebSDRReply(", in: "YAAM/HamTrackerWorkspaceView.swift")
        check("queueWebSDRReply calls WebSDRReplyGuard.identityIssue before the engine",
              before("WebSDRReplyGuard.identityIssue(", "ft8.prepareWebSDRReply(", in: queue))
        check("queueWebSDRReply passes the station's own callsign to the engine",
              queue?.contains("ownCallsign: ownCall") == true
              && queue?.contains("= appState.currentStationCallsign") == true
              && queue?.contains("stationCallsign: ownCall") == true)
        check("queueWebSDRReply calls WebSDRReplyGuard.retuneIssue before the engine",
              before("WebSDRReplyGuard.retuneIssue(", "ft8.prepareWebSDRReply(", in: queue))
        check("queueWebSDRReply sets the TX parity only after the engine accepts the reply",
              before("ft8.prepareWebSDRReply(", "ft8.txParity = selectedWebSDRTxParity", in: queue))
        let view = "YAAM/HamTrackerWorkspaceView.swift"
        check("the reply arrow is offered only for the own callsign",
              functionBody("if targetIsOwnCallsign,", in: view) != nil)
        let follow = functionBody("func followLatestWebSDRReply(", in: view)
        check("follow-latest stops unless the target is the own callsign",
              follow?.contains("guard targetIsOwnCallsign else { return }") == true)
        check("the reply arrow records the dial it prepares on",
              functionBody("if targetIsOwnCallsign,", in: view)?
                  .contains("webSDRReplyDialHz = webSDR.dialHz") == true)
        check("follow-latest records the dial it prepares on",
              follow?.contains("webSDRReplyDialHz = webSDR.dialHz") == true)

        // Prepared reply and decoded rows: dropped whenever the receiver, band or dial changes, so
        // a row decoded on the old selection cannot be answered on the new dial.
        for picker in ["webSDR.selectedReceiverID", "webSDR.selectedBand", "webSDR.selectedUtahReceiver"] {
            let handler = functionBody(".onChange(of: \(picker))", in: view,
                                       last: picker == "webSDR.selectedBand")
            check("changing \(picker) clears the decoded rows and the prepared reply",
                  handler?.contains("webSDR.clearMessages()") == true
                  && handler?.contains("discardWebSDRReply()") == true)
        }
        check("changing the target clears the prepared reply",
              functionBody(".onChange(of: engine.targetCallsign)", in: view)?
                  .contains("discardWebSDRReply()") == true)
        check("WebSDRFT8Monitor.clearMessages() removes the decoded rows",
              functionBody("func clearMessages(", in: "YAAM/WebSDRFT8Monitor.swift")?
                  .contains("messages.removeAll()") == true)
        check("Use band preset clears the prepared reply",
              functionBody("Button(\"Use band preset\")", in: view)?.contains("discardWebSDRReply()") == true)
        check("a successful manual Tune clears the prepared reply",
              functionBody("func applyWebSDRFrequency(", in: view)?.contains("discardWebSDRReply()") == true)
        check("discardWebSDRReply clears the reply, its draft and its recorded dial",
              ["selectedWebSDRReply = nil", "webSDRReplyDialHz = nil", "webSDRReplyDraft = \"\""].allSatisfy {
                  functionBody("func discardWebSDRReply(", in: view)?.contains($0) == true
              })

        if failures > 0 {
            print("WebSDR reply guard regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("WebSDR reply guard regression passed")
    }

    // Called from a nonisolated function on purpose. With the guard declared @MainActor this does
    // not compile. With no annotation and the app's -default-isolation MainActor (Swift 5 mode) it
    // compiles and only warns, so the declaration is also checked in the source text in main().
    nonisolated private static func offMainActor() -> Bool {
        ["EA3JIC", "EP2AES"].allSatisfy {
            WebSDRReplyGuard.targetIsOwnCallsign($0, ownCallsign: $0)
                && WebSDRReplyGuard.identityIssue(target: "K1ABC", ownCallsign: $0) != nil
        }
            && WebSDRReplyGuard.dialIssue(dialHz: 7_250_000, ft8DialsHz: [7_074_000]) != nil
            && WebSDRReplyGuard.retuneIssue(plannedDialHz: 1, currentDialHz: 2) != nil
    }

    /// A source file of the checkout, found from this file's location or the working directory.
    nonisolated private static func sourceText(_ path: String) -> String? {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let roots = [here, URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
        let text = roots.lazy.compactMap { try? String(contentsOf: $0.appendingPathComponent(path),
                                                       encoding: .utf8) }.first
        if text == nil { print("cannot read \(path); run from the repository root") }
        return text
    }

    /// The text between the braces of the block that follows `marker` in a source file: a function
    /// body, a closure, or a button action. nil when the file or the marker is missing.
    /// Strings and // comments are skipped so their braces do not count.
    nonisolated private static func functionBody(_ marker: String, in path: String,
                                                 last: Bool = false) -> String? {
        guard let text = sourceText(path),
              let start = text.range(of: marker, options: last ? .backwards : []) else { return nil }
        // The marker may end inside a parameter list; the block starts at the first "{" outside it.
        var parens = marker.filter { $0 == "(" }.count - marker.filter { $0 == ")" }.count
        var braces = 0
        var bodyStart: String.Index?
        var index = start.upperBound
        while index < text.endIndex {
            let ch = text[index]
            if ch == "\"" {
                index = text.index(after: index)
                while index < text.endIndex, text[index] != "\"" {
                    if text[index] == "\\" { index = text.index(after: index) }
                    if index < text.endIndex { index = text.index(after: index) }
                }
            } else if ch == "/", text[text.index(after: index)...].hasPrefix("/") {
                while index < text.endIndex, text[index] != "\n" { index = text.index(after: index) }
                continue
            } else if bodyStart == nil {
                if ch == "(" { parens += 1 }
                if ch == ")" { parens -= 1 }
                if ch == "{" && parens <= 0 {
                    bodyStart = text.index(after: index)
                    braces = 1
                }
            } else if ch == "{" {
                braces += 1
            } else if ch == "}" {
                braces -= 1
                if braces == 0, let first = bodyStart { return String(text[first..<index]) }
            }
            if index < text.endIndex { index = text.index(after: index) }
        }
        return nil
    }

    /// True when both strings are in `body` and `first` comes before `second`.
    nonisolated private static func before(_ first: String, _ second: String, in body: String?) -> Bool {
        guard let body, let a = body.range(of: first), let b = body.range(of: second) else { return false }
        return a.lowerBound < b.lowerBound
    }

    /// The numbers written as `key: 7_074_000` between two markers of a source file in the checkout.
    nonisolated private static func tableDials(_ path: String, from start: String, to end: String,
                                               key: String) -> [UInt64] {
        guard let text = sourceText(path),
              let begin = text.range(of: start),
              let finish = text.range(of: end, range: begin.upperBound..<text.endIndex),
              let regex = try? NSRegularExpression(pattern: "\(key):\\s*([0-9_]+)") else {
            return []
        }
        let block = String(text[begin.upperBound..<finish.lowerBound])
        let nsBlock = block as NSString
        return regex.matches(in: block, range: NSRange(location: 0, length: nsBlock.length)).compactMap {
            UInt64(nsBlock.substring(with: $0.range(at: 1)).replacingOccurrences(of: "_", with: ""))
        }
    }
}
