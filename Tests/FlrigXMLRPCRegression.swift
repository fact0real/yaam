import Foundation

// Standalone, no flrig or radio needed:
//   swiftc -parse-as-library Tests/FlrigXMLRPCRegression.swift YAAM/FlrigXMLRPC.swift -o /tmp/flrigx && /tmp/flrigx
// The reply bodies are the bytes flrig 2.0.12 sends (CR LF and a tab between the tags), taken from a run against flrig.

/// Stands in for the network: records the order in which commands arrive, after a short random delay (the
/// delay is what lets separate Tasks overtake each other).
final class Arrivals: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    private var running = 0
    private var peak = 0

    var arrived: [String] { lock.withLock { log } }
    var maxRunning: Int { lock.withLock { peak } }

    private func begin() { lock.withLock { running += 1; peak = max(peak, running) } }
    private func end(_ command: FlrigCommand) { lock.withLock { log.append(command.summary); running -= 1 } }

    func arrive(_ command: FlrigCommand, maxDelayMicroseconds: UInt64 = 3_000) async {
        begin()
        try? await Task.sleep(nanoseconds: UInt64.random(in: 0...maxDelayMicroseconds) * 1_000)
        end(command)
    }
}

@main
struct FlrigXMLRPCRegression {
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var failed = 0
    static func check(_ condition: Bool, _ name: String) {
        checks += 1
        if !condition { failed += 1; print("FAIL: \(name)") }
    }

    static let crlf = "\r\n"
    static func ok(_ inner: String) -> Data {
        Data("<?xml version=\"1.0\"?>\(crlf)<methodResponse><params><param>\(crlf)\t<value>\(inner)</value>\(crlf)</param></params></methodResponse>\(crlf)".utf8)
    }
    static func fault(_ message: String, code: Int = -1) -> Data {
        Data("<?xml version=\"1.0\"?>\(crlf)<methodResponse><fault>\(crlf)\t<value><struct><member><name>faultCode</name><value><i4>\(code)</i4></value></member><member><name>faultString</name><value>\(message)</value></member></struct></value>\(crlf)</fault></methodResponse>\(crlf)".utf8)
    }

    static func main() async {
        // --- Commands: every request is made by a function that gives the parameter the type flrig reads.
        // The summary names the type of each parameter, so a watts value sent as a string (the original defect:
        // flrig answers "type error" and ignores the command) fails here.
        check(FlrigCommand.setVFO(hz: 7_040_000).summary == "rig.set_vfo double:7040000.0", "set_vfo goes as a double")
        check(FlrigCommand.setPower(watts: 10).summary == "rig.set_power i4:10", "set_power goes as an i4, not a string")
        check(FlrigCommand.setPower(watts: 100).summary == "rig.set_power i4:100", "set_power 100 goes as an i4")
        check(FlrigCommand.setPTT(true).summary == "rig.set_ptt i4:1", "set_ptt on goes as i4 1")
        check(FlrigCommand.setPTT(false).summary == "rig.set_ptt i4:0", "set_ptt off goes as i4 0")
        check(FlrigCommand.setMode("USB").summary == "rig.set_mode string:USB", "set_mode goes as a string")
        for (command, method) in [(FlrigCommand.getXcvr, "rig.get_xcvr"), (.getVFO, "rig.get_vfo"), (.getMode, "rig.get_mode"),
                                  (.getPower, "rig.get_power"), (.getSmeter, "rig.get_smeter"), (.getPTT, "rig.get_ptt")] {
            check(command.summary == method && command.params.isEmpty, "\(method) is a query without parameters")
        }
        check(FlrigCommand.setVFO(hz: 7_040_000).body
              == "<?xml version=\"1.0\"?><methodCall><methodName>rig.set_vfo</methodName><params><param><value><double>7040000.0</double></value></param></params></methodCall>",
              "set_vfo request bytes")
        check(FlrigCommand.setVFO(hz: 1_296_100_000).body.contains("<double>1296100000.0</double>"),
              "set_vfo 1296.1 MHz is sent as a plain decimal, not 1.2961e+09")
        check(FlrigCommand.setPTT(true).body.contains("<param><value><i4>1</i4></value></param>"), "set_ptt 1 request bytes")
        check(FlrigCommand.setPower(watts: 10).body.contains("<i4>10</i4>") && !FlrigCommand.setPower(watts: 10).body.contains("<string>"),
              "set_power request bytes carry an <i4> and no <string>")
        check(FlrigCommand.setMode("USB").body.contains("<string>USB</string>"), "set_mode request bytes")
        check(FlrigCommand.getXcvr.body.hasSuffix("<params></params></methodCall>"), "a query has an empty <params>")
        check(FlrigCommand.setMode("A<B>&C").body.contains("<string>A&lt;B&gt;&amp;C</string>"), "text is XML-escaped")

        // --- Replies
        check(FlrigXMLRPC.parse(ok("TX500")) == .value("TX500"), "a string reply is read")
        check(FlrigXMLRPC.parse(ok("<string>TX500</string>")) == .value("TX500"), "a <string> reply is read")
        check(FlrigXMLRPC.parse(ok("<i4>0</i4>")) == .value("0"), "an <i4> reply is read")
        check(FlrigXMLRPC.parse(ok("<double>7074000.000000</double>")) == .value("7074000.000000"), "a <double> reply is read")
        check(FlrigXMLRPC.parse(ok("")) == .value(""), "an empty <value></value> is an empty value, not an error")
        check(FlrigXMLRPC.parse(ok("7074000")) == .value("7074000"), "a frequency reply is read")
        check(FlrigXMLRPC.parse(ok("R:TX500&amp;T:R")) == .value("R:TX500&T:R"), "entities are decoded")
        check(FlrigXMLRPC.parse(ok("a&lt;b")) == .value("a<b"), "&lt; is decoded to <")
        check(FlrigXMLRPC.parse(ok("a&amp;lt;b")) == .value("a&lt;b"), "&amp;lt; is decoded once, to the text &lt;, not to <")
        // A fault is a fault, not the value -1 (RigControlEngine.parseXMLRPCResponse read its faultCode as the result)
        check(FlrigXMLRPC.parse(fault("type error")) == .fault(code: -1, message: "type error"), "a type-error fault is read as a fault")
        check(FlrigXMLRPC.parse(fault("type error")).text == nil, "a fault has no value")
        check(FlrigXMLRPC.parse(fault("rig.send_morse: unknown method name")) == .fault(code: -1, message: "rig.send_morse: unknown method name"),
              "an unknown-method fault is read as a fault")
        check(FlrigXMLRPC.parse(fault("busy", code: 7)) == .fault(code: 7, message: "busy"), "the fault code is read (7)")
        check(FlrigXMLRPC.parse(fault("no such method", code: -32601)) == .fault(code: -32601, message: "no such method"), "a negative fault code other than -1 is read")
        check(FlrigXMLRPC.parse(fault("7 &lt; 9 &amp; 5", code: 3)) == .fault(code: 3, message: "7 < 9 & 5"), "entities in a fault message are decoded")
        check(FlrigXMLRPC.parse(fault("bad &amp;lt; tag", code: 3)) == .fault(code: 3, message: "bad &lt; tag"), "&amp;lt; in a fault message is decoded once")
        check(FlrigXMLRPC.parse(Data("<html>nope</html>".utf8)) == .malformed, "HTML is not an XML-RPC reply")
        check(FlrigXMLRPC.parse(Data()) == .malformed, "an empty body is not an XML-RPC reply")
        check(FlrigXMLRPC.parse(Data("<methodResponse><params><param><value><array><data><value>a</value></data></array></value></param></params></methodResponse>".utf8)) == .malformed,
              "a list is not read as a scalar")

        // --- Connection state from get_xcvr
        check(FlrigXMLRPC.link(forXcvr: .value("TX500")) == .reporting("TX500"), "get_xcvr TX500: flrig reports TX500")
        check(FlrigXMLRPC.link(forXcvr: .value("NONE")) == .noRadio, "get_xcvr NONE: no radio selected")
        check(FlrigXMLRPC.link(forXcvr: .value("  none ")) == .noRadio, "get_xcvr NONE is matched without case or spaces")
        check(FlrigXMLRPC.link(forXcvr: .value("")) == .radioNotAnswering, "get_xcvr empty: no radio name")
        check(FlrigXMLRPC.link(forXcvr: nil) == .unreachable, "no HTTP answer: not reachable")
        if case .unexpected = FlrigXMLRPC.link(forXcvr: .fault(code: -1, message: "x")) {} else { check(false, "a fault from get_xcvr is an unexpected answer") }
        if case .unexpected = FlrigXMLRPC.link(forXcvr: .malformed) {} else { check(false, "a non-XML-RPC answer is an unexpected answer") }
        check(FlrigLink.reporting("TX500").isReporting && FlrigLink.reporting("TX500").radioName == "TX500", "only .reporting counts as connected")
        for link in [FlrigLink.idle, .unreachable, .noRadio, .radioNotAnswering, .unexpected("x")] {
            check(!link.isReporting && link.radioName == nil, "\(link) is not connected")
        }
        check(FlrigLink.reporting("TX500").summary == "flrig reports TX500", "the label says what flrig reports")
        check(!FlrigLink.reporting("TX500").summary.lowercased().contains("connected"), "the label does not say 'connected'")
        check(FlrigLink.reporting("TX500").detail.contains("keeps reporting the last frequency"), "the detail says flrig keeps reporting the last frequency")
        check(FlrigLink.noRadio.summary == "flrig: no radio selected" && FlrigLink.noRadio.detail.contains("Config > Setup > Transceiver"), "the NONE texts name flrig's menu")
        check(FlrigLink.idle.problem == nil && FlrigLink.reporting("TX500").problem == nil, "no problem text while idle or reporting a radio")
        for link in [FlrigLink.unreachable, .noRadio, .radioNotAnswering, .unexpected("why")] {
            check(link.problem == link.detail && link.problem != nil, "\(link) has its detail as the problem text")
        }

        // --- What the user is told: a refused command stays until the next accepted command or a link change
        var errors = FlrigErrorState()
        let up = FlrigLink.reporting("TX500")
        check(errors.text(for: up) == nil && errors.text(for: .idle) == nil, "no error text at the start")
        check(errors.text(for: .noRadio) == FlrigLink.noRadio.detail, "with no radio the error text is the link's")
        errors.refused("rig.set_vfo", "type error")
        check(errors.text(for: up) == "flrig refused rig.set_vfo: type error", "a refused command is the error text while flrig reports a radio")
        check(errors.text(for: .noRadio) == "flrig refused rig.set_vfo: type error", "a refusal comes before the link's own text")
        check(errors.text(for: up) == errors.text(for: up), "asking again (a poll) gives the same text")
        errors.refused("rig.set_power", "type error")
        check(errors.text(for: up) == "flrig refused rig.set_power: type error", "a newer refusal replaces the older one")
        errors.succeeded()
        check(errors.text(for: up) == nil, "the next accepted command clears the refusal")
        errors.refused("rig.set_ptt", "type error")
        errors.linkChanged()
        check(errors.text(for: up) == nil, "a link change clears the refusal")
        check(errors.text(for: .unreachable) == FlrigLink.unreachable.detail, "after a link change the link's text is shown")
        var recorded = FlrigErrorState()
        recorded.record(FlrigOutcome(method: "rig.set_vfo", reply: .fault(code: 7, message: "busy")))
        check(recorded.text(for: up) == "flrig refused rig.set_vfo: busy", "record: a fault answer is kept, with the method that was refused")
        recorded.record(FlrigOutcome(method: "rig.set_mode", reply: nil))
        recorded.record(FlrigOutcome(method: "rig.set_mode", reply: .malformed))
        check(recorded.text(for: up) == "flrig refused rig.set_vfo: busy", "record: no answer and an unreadable answer change nothing")
        recorded.record(FlrigOutcome(method: "rig.set_mode", reply: .value("1")))
        check(recorded.text(for: up) == nil, "record: a value answer clears the refusal")
        var logged = FlrigErrorState()
        check(logged.newProblemToLog("x") == "x", "a new problem is logged")
        check(logged.newProblemToLog("x") == nil && logged.newProblemToLog("x") == nil, "the same problem is not logged again at the next polls")
        check(logged.newProblemToLog("y") == "y", "a different problem is logged")
        check(logged.newProblemToLog(nil) == nil, "no problem logs nothing")
        check(logged.newProblemToLog("y") == "y", "a problem that comes back after a good spell is logged again")

        // --- Order: commands reach flrig in the order they were issued
        // 200 pairs of key-down, key-up issued back to back, each request delayed by a random 0 to 3 ms. Sent as
        // separate Tasks they overtake each other; through the chain the last wish is always the last one sent.
        let chain = FlrigCommandChain()
        let pairs = Arrivals()
        var last: Task<Void, Never>?
        for _ in 0..<200 {
            chain.enqueue { await pairs.arrive(.setPTT(true)) }
            last = chain.enqueue { await pairs.arrive(.setPTT(false)) }
        }
        await last?.value
        let expectedPairs = Array(repeating: ["rig.set_ptt i4:1", "rig.set_ptt i4:0"], count: 200).flatMap { $0 }
        check(pairs.arrived == expectedPairs, "200 key-down/key-up pairs arrive in the order issued (none reversed)")
        check(pairs.arrived.last == "rig.set_ptt i4:0", "the last wish (release) is the last command sent")
        check(pairs.maxRunning == 1, "only one command is in flight at a time")

        let mixed = Arrivals()
        let sequence: [FlrigCommand] = (0..<300).map { i in
            switch i % 4 {
            case 0: return .setVFO(hz: Double(7_000_000 + i))
            case 1: return .setMode(i % 8 == 1 ? "CW" : "USB")
            case 2: return .setPower(watts: i % 100)
            default: return .setPTT(i % 8 == 3)
            }
        }
        var lastMixed: Task<Void, Never>?
        for command in sequence { lastMixed = chain.enqueue { await mixed.arrive(command, maxDelayMicroseconds: 500) } }
        await lastMixed?.value
        check(mixed.arrived == sequence.map { $0.summary }, "300 mixed commands (frequency, mode, power, PTT) arrive in the order issued")

        let cancelled = Arrivals()
        let caller = Task { await chain.enqueue { await cancelled.arrive(.setPTT(false)) }.value }
        caller.cancel()
        await caller.value
        let after = chain.enqueue { await cancelled.arrive(.setPTT(false), maxDelayMicroseconds: 0) }
        await after.value
        check(cancelled.arrived.count == 2, "a queued release is still sent when the task that queued it is cancelled")
        check(await chain.enqueue { 42 }.value == 42, "a job returns its result")

        print("FlrigXMLRPCRegression: \(checks) checks, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
