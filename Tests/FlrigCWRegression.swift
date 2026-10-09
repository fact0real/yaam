import Foundation

// Standalone, no flrig or radio needed:
//   swiftc -parse-as-library Tests/FlrigCWRegression.swift YAAM/FlrigXMLRPC.swift -o /tmp/flrigcw && /tmp/flrigcw
// CW through flrig's cwio: the requests, the order of the calls, and the pause after a stop.

/// Records what a sequence sends and when it pauses, and answers from a script.
final class FakeFlrig: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    var faultOn: String? = nil        // method that answers with a fault
    var silentOn: String? = nil       // method that gets no answer at all

    var log: [String] { lock.withLock { events } }

    func send(_ command: FlrigCommand) async -> FlrigReply? {
        lock.withLock { events.append(command.summary) }
        if command.method == silentOn { return nil }
        if command.method == faultOn { return .fault(code: -1, message: "type error") }
        if command.method == "rig.get_ptt" { return .value("0") }   // the radio is in receive
        return .value("")
    }

    func pause(_ nanoseconds: UInt64) async {
        lock.withLock { events.append("pause \(nanoseconds / 1_000_000) ms") }
    }
}

@main
struct FlrigCWRegression {
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var failed = 0
    static func check(_ condition: Bool, _ name: String) {
        checks += 1
        if !condition { failed += 1; print("FAIL: \(name)") }
    }

    static func main() async {
        // --- Requests
        check(FlrigCommand.cwText("cq test")?.summary == "rig.cwio_text string:[CQ TEST]", "CW text is upper-cased and bracketed, as a string")
        check(FlrigCommand.cwText("CQ [TEST] DE ]X[")?.summary == "rig.cwio_text string:[CQ TEST DE X]", "brackets inside the text are removed (they would start or stop flrig early)")
        check(FlrigCommand.cwText("  \n ") == nil, "blank text is not sent")
        check(FlrigCommand.cwText("[]") == nil, "only brackets is not sent")
        check(FlrigCommand.cwText(" ea3jic de ep2aes ")?.summary == "rig.cwio_text string:[EA3JIC DE EP2AES]", "spaces around the text are trimmed")
        check(FlrigCommand.cwText("a<b>&c")?.body.contains("<string>[A&lt;B&gt;&amp;C]</string>") == true, "text is XML-escaped (flrig prosign characters < > &)")
        check(FlrigCommand.cwSpeed(wpm: 24).summary == "rig.cwio_set_wpm i4:24", "the speed goes as an i4")
        check(FlrigCommand.cwSpeed(wpm: 2).summary == "rig.cwio_set_wpm i4:5", "a speed below 5 wpm is raised to flrig's minimum")
        check(FlrigCommand.cwSpeed(wpm: 400).summary == "rig.cwio_set_wpm i4:100", "a speed above 100 wpm is lowered to flrig's maximum")
        check(FlrigCommand.cwStop.summary == "rig.cwio_send i4:0", "stop is cwio_send with an i4 0")

        // --- Send: speed first, then the text
        var fake = FakeFlrig()
        let sent1 = await FlrigSequences.sendCW("cq test", wpm: 24, send: fake.send)
        check(sent1 == FlrigOutcome(method: "rig.cwio_text", reply: .value("")) && fake.log == ["rig.cwio_set_wpm i4:24", "rig.cwio_text string:[CQ TEST]"],
              "send: speed first (i4), then the bracketed text (string)")
        fake = FakeFlrig()
        let sent2 = await FlrigSequences.sendCW("   ", wpm: 24, send: fake.send)
        check(sent2 == nil && fake.log.isEmpty, "send: nothing to send, nothing goes to flrig")
        fake = FakeFlrig()
        _ = await FlrigSequences.sendCW("CQ", wpm: nil, send: fake.send)
        check(fake.log == ["rig.cwio_text string:[CQ]"], "send without a speed: only the text")
        fake = FakeFlrig(); fake.faultOn = "rig.cwio_set_wpm"
        let sent3 = await FlrigSequences.sendCW("CQ", wpm: 24, send: fake.send)
        check(sent3 == FlrigOutcome(method: "rig.cwio_set_wpm", reply: .fault(code: -1, message: "type error")) && fake.log == ["rig.cwio_set_wpm i4:24"],
              "send: a fault from the speed call is returned, with its method, and the text is not sent")
        fake = FakeFlrig(); fake.faultOn = "rig.cwio_text"
        let sent4 = await FlrigSequences.sendCW("CQ", wpm: 24, send: fake.send)
        check(sent4 == FlrigOutcome(method: "rig.cwio_text", reply: .fault(code: -1, message: "type error")), "send: a fault from the text call is returned")
        fake = FakeFlrig(); fake.silentOn = "rig.cwio_text"
        let sent5 = await FlrigSequences.sendCW("CQ", wpm: 24, send: fake.send)
        check(sent5 == FlrigOutcome(method: "rig.cwio_text", reply: nil), "send: no answer from flrig is returned as no answer")
        check(!fake.log.contains { $0.hasPrefix("pause") }, "send: no pause of its own")

        // --- Stop: cwio_send 0, then PTT off (read back with get_ptt), then the pause
        fake = FakeFlrig()
        let stopped = await FlrigSequences.stopCW(send: fake.send, pause: fake.pause)
        check(stopped.method == "rig.set_ptt" && stopped.reply == .value("") && fake.log == ["rig.cwio_send i4:0", "rig.set_ptt i4:0", "rig.get_ptt", "pause 150 ms"],
              "stop: cwio_send 0 (i4), then set_ptt 0 (i4), then get_ptt, then a pause of 150 ms")
        fake = FakeFlrig(); fake.faultOn = "rig.cwio_send"
        let stopped2 = await FlrigSequences.stopCW(send: fake.send, pause: fake.pause)
        check(stopped2.method == "rig.cwio_send" && stopped2.reply == .fault(code: -1, message: "type error") && fake.log == ["rig.cwio_send i4:0", "rig.set_ptt i4:0", "rig.get_ptt", "pause 150 ms"],
              "stop: PTT is released even when cwio_send faults, and that fault is returned")
        fake = FakeFlrig(); fake.faultOn = "rig.set_ptt"
        let stopped3 = await FlrigSequences.stopCW(send: fake.send, pause: fake.pause)
        check(stopped3.method == "rig.set_ptt" && stopped3.reply == .fault(code: -1, message: "type error"), "stop: a fault from set_ptt is returned")
        fake = FakeFlrig(); fake.silentOn = "rig.cwio_send"
        let stopped4 = await FlrigSequences.stopCW(send: fake.send, pause: fake.pause)
        check(stopped4.method == "rig.cwio_send" && stopped4.reply == nil, "stop: no answer to cwio_send is returned as no answer")

        // --- The app starts a message with a stop and then the text, from two Tasks; the chain keeps that order, and
        // the text starts only after the pause
        let chained = FakeFlrig()
        let chain = FlrigCommandChain()
        let stop = chain.enqueue { await FlrigSequences.stopCW(send: chained.send, pause: chained.pause) }
        let message = chain.enqueue { await FlrigSequences.sendCW("CQ", wpm: 12, send: chained.send) }
        _ = await stop.value
        _ = await message.value
        check(chained.log == ["rig.cwio_send i4:0", "rig.set_ptt i4:0", "rig.get_ptt", "pause 150 ms", "rig.cwio_set_wpm i4:12", "rig.cwio_text string:[CQ]"],
              "stop then message through the chain: the text goes out after the stop, the read-back and the pause")

        print("FlrigCWRegression: \(checks) checks, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
