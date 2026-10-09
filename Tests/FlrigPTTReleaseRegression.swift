import Foundation

// Standalone, no flrig or radio needed:
//   swiftc -parse-as-library Tests/FlrigPTTReleaseRegression.swift YAAM/FlrigXMLRPC.swift -o flrigptt && ./flrigptt
// A rig.set_ptt 0 that YAAM sends to flrig is read back with rig.get_ptt and repeated if flrig still reports PTT on
// (flrig 2.0.12 can answer a release with TX;: xml_server.cxx:1947, :1955, :1961 and support.cxx:1263). If the radio
// stays keyed, or its state cannot be read, the user is warned.

/// A stand-in for flrig and the radio behind it. It records every request, the pauses, and the state of the radio
/// after every request.
final class FakeFlrig: @unchecked Sendable {
    enum SetAnswer { case value, fault, silent }
    enum GetAnswer { case truth, fault, silent, text(String), malformed }

    private let lock = NSLock()
    private var events: [String] = []
    private var radio: [String] = []        // "TX" or "RX" after each request, in step with `requests`
    private var requests: [String] = []
    private var keyed: Bool
    private var releaseCalls = 0
    private var getCalls = 0

    /// per rig.set_ptt 0 call, in order: does it release the radio? (calls past the end of the list release it)
    var releases: [Bool] = []
    /// per rig.set_ptt 0 call: what flrig answers (calls past the end: a value)
    var setAnswers: [SetAnswer] = []
    /// per rig.get_ptt call: what flrig answers (calls past the end: the truth)
    var getAnswers: [GetAnswer] = []
    /// answers to rig.cwio_send
    var cwioFault = false

    init(keyed: Bool = true) { self.keyed = keyed }

    var log: [String] { lock.withLock { events } }
    var requestLog: [String] { lock.withLock { requests } }
    var radioAfterEach: [String] { lock.withLock { radio } }
    var radioIsKeyed: Bool { lock.withLock { keyed } }
    var setPTTValues: [Int] {
        lock.withLock { requests.compactMap { r in r.hasPrefix("rig.set_ptt i4:") ? Int(r.dropFirst("rig.set_ptt i4:".count)) : nil } }
    }

    func send(_ command: FlrigCommand) async -> FlrigReply? {
        lock.withLock {
            events.append(command.summary)
            requests.append(command.summary)
            let reply = answer(command)
            radio.append(keyed ? "TX" : "RX")
            return reply
        }
    }

    private func answer(_ command: FlrigCommand) -> FlrigReply? {
        switch command.summary {
        case "rig.set_ptt i4:1":
            keyed = true
            return .value("")
        case "rig.set_ptt i4:0":
            releaseCalls += 1
            let index = releaseCalls - 1
            if index >= releases.count || releases[index] { keyed = false }
            switch index < setAnswers.count ? setAnswers[index] : .value {
            case .value: return .value("")
            case .fault: return .fault(code: -1, message: "type error")
            case .silent: return nil
            }
        case "rig.get_ptt":
            getCalls += 1
            let index = getCalls - 1
            switch index < getAnswers.count ? getAnswers[index] : .truth {
            case .truth: return .value(keyed ? "1" : "0")
            case .fault: return .fault(code: -1, message: "type error")
            case .silent: return nil
            case .text(let text): return .value(text)
            case .malformed: return .malformed
            }
        case "rig.cwio_send i4:0":
            return cwioFault ? .fault(code: -1, message: "type error") : .value("")
        default:
            return .value("")
        }
    }

    func pause(_ nanoseconds: UInt64) async {
        lock.withLock { events.append("pause \(nanoseconds / 1_000_000) ms") }
    }
}

@main
struct FlrigPTTReleaseRegression {
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var failed = 0
    static func check(_ condition: Bool, _ name: String) {
        checks += 1
        if !condition { failed += 1; print("FAIL: \(name)") }
    }

    static let set0 = "rig.set_ptt i4:0", get = "rig.get_ptt"

    static func release(_ fake: FakeFlrig) async -> FlrigOutcome {
        await FlrigPTTRelease.release(send: fake.send, pause: fake.pause)
    }

    static func main() async {
        // --- The requests
        check(FlrigCommand.getPTT.summary == "rig.get_ptt" && FlrigCommand.getPTT.params.isEmpty, "rig.get_ptt has no parameters")
        check(FlrigCommand.setPTT(false).isPTTRelease, "set_ptt 0 is a release")
        check(!FlrigCommand.setPTT(true).isPTTRelease, "set_ptt 1 is not a release")
        check(![FlrigCommand.setVFO(hz: 7_040_000), .setMode("CW"), .setPower(watts: 0), .getPTT, .cwStop].contains { $0.isPTTRelease }, "no other command is a release")
        check(FlrigPTTRelease.repeatPauses == [100_000_000, 200_000_000, 300_000_000], "three repeats, after 100, 200 and 300 ms")

        // --- Released at the first try: set_ptt 0, get_ptt reads 0, nothing else
        var fake = FakeFlrig()
        var outcome = await release(fake)
        check(fake.requestLog == [set0, get] && !fake.log.contains { $0.hasPrefix("pause") }, "first try: set_ptt 0, then get_ptt, no repeat and no pause")
        check(fake.radioAfterEach == ["RX", "RX"] && !fake.radioIsKeyed, "first try: the radio is in receive after every request")
        check(outcome.method == "rig.set_ptt" && outcome.reply == .value("") && outcome.releaseCheck == .released(attempts: 1), "first try: released after 1 attempt, the answer to set_ptt is kept")
        check(outcome.releaseCheck?.warning == nil && outcome.releaseCheck?.logLine == nil, "first try: no warning and nothing to log")

        // --- Released after 1, 2 and 3 repeats (the first 1, 2, 3 releases are turned into TX; by the race)
        for lost in 1...3 {
            fake = FakeFlrig()
            fake.releases = Array(repeating: false, count: lost)
            outcome = await release(fake)
            var expected: [String] = []
            for n in 0...lost {
                if n > 0 { expected.append("pause \(n * 100) ms") }
                expected += [set0, get]
            }
            check(fake.log == expected, "released after \(lost) repeat(s): set_ptt 0 and get_ptt, then pause \(Array(1...lost).map { "\($0 * 100)" }.joined(separator: ", ")) ms and again")
            let radio = Array(repeating: ["TX", "TX"], count: lost).flatMap { $0 } + ["RX", "RX"]
            check(fake.radioAfterEach == radio, "released after \(lost) repeat(s): the radio is keyed after every request until the last set_ptt 0, receive after that")
            check(outcome.releaseCheck == .released(attempts: lost + 1) && !fake.radioIsKeyed, "released after \(lost) repeat(s): released, attempts \(lost + 1)")
            check(outcome.releaseCheck?.warning == nil && outcome.releaseCheck?.logLine != nil, "released after \(lost) repeat(s): no warning, but the log is told")
        }

        // --- Never released: 4 tries, 3 pauses, then a warning
        fake = FakeFlrig()
        fake.releases = Array(repeating: false, count: 20)
        outcome = await release(fake)
        check(fake.log == [set0, get, "pause 100 ms", set0, get, "pause 200 ms", set0, get, "pause 300 ms", set0, get], "never released: 4 x (set_ptt 0, get_ptt) with pauses of 100, 200, 300 ms, and no more")
        check(fake.radioAfterEach == Array(repeating: "TX", count: 8) && fake.radioIsKeyed, "never released: the radio is keyed after every request")
        check(outcome.releaseCheck == .stillKeyed(attempts: 4), "never released: still keyed after 4 attempts")
        let warning = outcome.releaseCheck?.warning ?? ""
        check(warning.contains("may still be transmitting") && warning.contains("4 times") && warning.contains("rig.set_ptt 0"), "never released: the warning says the radio may still be transmitting and how often set_ptt 0 was sent")
        check(outcome.releaseCheck?.logLine == warning, "never released: the same text goes to the log")

        // --- rig.get_ptt cannot be read: unknown, which is a warning too, and no repeat
        let unreadable: [(String, FakeFlrig.GetAnswer, String)] = [
            ("a fault", .fault, "flrig refused rig.get_ptt (type error)"),
            ("no answer", .silent, "rig.get_ptt got no answer from flrig"),
            ("an unreadable answer", .malformed, "the answer to rig.get_ptt could not be read"),
            ("the text x", .text("x"), "rig.get_ptt answered \"x\""),
            ("the number 2", .text("2"), "rig.get_ptt answered \"2\""),
            ("an empty value", .text(""), "rig.get_ptt answered \"\""),
        ]
        for (name, answer, why) in unreadable {
            fake = FakeFlrig(keyed: true)
            fake.getAnswers = [answer]
            outcome = await release(fake)
            check(fake.requestLog == [set0, get], "get_ptt with \(name): one set_ptt 0, one get_ptt, no repeat")
            check(outcome.releaseCheck == .unknown(why), "get_ptt with \(name): unknown (\(why))")
            let text = outcome.releaseCheck?.warning ?? ""
            check(text.contains("cannot tell") && !text.lowercased().contains("released") && text.contains(why), "get_ptt with \(name): the warning says YAAM cannot tell, and why")
        }
        // the radio WAS released in that case: the state is still reported as unknown, never as released
        fake = FakeFlrig(keyed: true)
        fake.getAnswers = [.silent]
        _ = await release(fake)
        check(!fake.radioIsKeyed, "get_ptt with no answer: (the radio had been released, but YAAM could not know)")

        // --- A repeat only after set_ptt 0 was answered with a value
        fake = FakeFlrig()
        fake.setAnswers = [.fault]; fake.releases = [false]
        outcome = await release(fake)
        check(fake.requestLog == [set0, get], "set_ptt refused and PTT on: no repeat (it would be refused again)")
        check(outcome.releaseCheck == .stillKeyed(attempts: 1) && outcome.reply == .fault(code: -1, message: "type error"), "set_ptt refused and PTT on: still keyed after 1 attempt, the refusal is kept")
        check(outcome.releaseCheck?.warning?.contains("once") == true, "set_ptt refused and PTT on: the warning says set_ptt 0 was sent once")
        fake = FakeFlrig()
        fake.setAnswers = [.silent]; fake.releases = [false]
        outcome = await release(fake)
        check(fake.requestLog == [set0, get] && outcome.releaseCheck == .stillKeyed(attempts: 1) && outcome.reply == nil, "set_ptt without answer and PTT on: no repeat (flrig is busy; more requests would queue behind it)")
        fake = FakeFlrig()
        fake.setAnswers = [.silent]
        outcome = await release(fake)
        check(outcome.releaseCheck == .released(attempts: 1) && outcome.reply == nil, "set_ptt without answer but get_ptt reads 0: released")
        fake = FakeFlrig(keyed: false)
        fake.setAnswers = [.fault]
        outcome = await release(fake)
        check(outcome.releaseCheck == .released(attempts: 1) && outcome.reply == .fault(code: -1, message: "type error"), "set_ptt refused but get_ptt reads 0: released, and the refusal is still reported")
        fake = FakeFlrig()
        fake.releases = [false, false]; fake.setAnswers = [.value, .silent]
        outcome = await release(fake)
        check(fake.requestLog == [set0, get, set0, get] && outcome.releaseCheck == .stillKeyed(attempts: 2), "a repeat without answer ends the repeats")

        // --- Through a chain: the repeats and the read-back are one job, so nothing is sent between them,
        // and a key-down queued behind a release goes out after it
        let chained = FakeFlrig()
        chained.releases = [false, true]
        let chain = FlrigCommandChain()
        let first = chain.enqueue { await release(chained) }
        let keyDown = chain.enqueue { await chained.send(.setPTT(true)) }
        let second = chain.enqueue { await release(chained) }
        _ = await first.value; _ = await keyDown.value; _ = await second.value
        check(chained.log == [set0, get, "pause 100 ms", set0, get, "rig.set_ptt i4:1", set0, get],
              "chain: release with a repeat, then the queued key-down, then the next release; nothing between a release and its checks")

        // 200 pairs of key-down, release, queued back to back; every 7th release goes wrong once. The set_ptt values
        // never reverse (1, then 0s, then 1, ...) and the last one is 0, with the radio in receive.
        let pairs = FakeFlrig(keyed: false)
        pairs.releases = (0..<400).map { $0 % 7 != 3 }
        var last: Task<FlrigOutcome, Never>?
        for _ in 0..<200 {
            chain.enqueue { await pairs.send(.setPTT(true)) }
            last = chain.enqueue { await release(pairs) }
        }
        _ = await last?.value
        let values = pairs.setPTTValues
        var reversed = 0
        for (index, value) in values.enumerated() where value == 1 && index > 0 && values[index - 1] == 1 { reversed += 1 }
        check(values.first == 1 && values.last == 0 && reversed == 0 && values.filter { $0 == 1 }.count == 200, "200 key-down/release pairs with repeats: key-downs and releases keep their order, the last command is a release")
        check(!pairs.radioIsKeyed, "200 pairs: the radio is in receive at the end")
        check(values.filter { $0 == 0 }.count > 200, "200 pairs: some releases were repeated")

        // --- Stop CW: cwio_send 0, the release with its read-back, then the pause
        fake = FakeFlrig()
        var stopped = await FlrigSequences.stopCW(send: fake.send, pause: fake.pause)
        check(fake.log == ["rig.cwio_send i4:0", set0, get, "pause 150 ms"], "stop CW: cwio_send 0, set_ptt 0, get_ptt, then the 150 ms pause")
        check(stopped.method == "rig.set_ptt" && stopped.releaseCheck == .released(attempts: 1), "stop CW: the outcome carries the result of the read-back")
        fake = FakeFlrig(); fake.releases = [false]
        stopped = await FlrigSequences.stopCW(send: fake.send, pause: fake.pause)
        check(fake.log == ["rig.cwio_send i4:0", set0, get, "pause 100 ms", set0, get, "pause 150 ms"] && stopped.releaseCheck == .released(attempts: 2), "stop CW: a release that went wrong is repeated before the 150 ms pause")
        fake = FakeFlrig(); fake.releases = Array(repeating: false, count: 9)
        stopped = await FlrigSequences.stopCW(send: fake.send, pause: fake.pause)
        check(stopped.releaseCheck == .stillKeyed(attempts: 4) && fake.log.last == "pause 150 ms", "stop CW: a radio that stays keyed is reported, and the 150 ms pause still ends the stop")
        fake = FakeFlrig(); fake.cwioFault = true; fake.releases = [false, false, false, false]
        stopped = await FlrigSequences.stopCW(send: fake.send, pause: fake.pause)
        check(stopped.method == "rig.cwio_send" && stopped.reply == .fault(code: -1, message: "type error") && stopped.releaseCheck == .stillKeyed(attempts: 4),
              "stop CW: a fault from cwio_send is returned, and the result of the read-back with it")

        // --- What the user is told
        var errors = FlrigErrorState()
        let up = FlrigLink.reporting("TX500")
        check(errors.pttWarning == nil && errors.text(for: up) == nil, "no warning at the start")
        errors.record(FlrigOutcome(method: "rig.set_ptt", reply: .value(""), releaseCheck: .stillKeyed(attempts: 4)))
        let stuckText = FlrigPTTCheck.stillKeyed(attempts: 4).warning
        check(errors.pttWarning == stuckText && errors.text(for: up) == stuckText, "a release that did not work becomes the error text")
        errors.record(FlrigOutcome(method: "rig.set_vfo", reply: .value("")))
        check(errors.pttWarning == stuckText, "the next accepted command does not clear it")
        errors.succeeded()
        errors.linkChanged()
        check(errors.pttWarning == stuckText && errors.text(for: .unreachable) == stuckText, "neither does a link change; the warning comes before the link's own text")
        errors.refused("rig.set_vfo", "type error")
        check(errors.text(for: up) == stuckText, "the warning comes before a refused command")
        check(!errors.pttObserved(keyed: true) && errors.pttWarning == stuckText, "a poll that reads PTT on keeps it")
        check(errors.pttObserved(keyed: false) && errors.pttWarning == nil, "a poll that reads PTT off ends it")
        check(errors.text(for: up) == "flrig refused rig.set_vfo: type error", "after it the refused command shows again")
        check(!errors.pttObserved(keyed: false), "a poll that reads PTT off with no warning set changes nothing")
        errors.record(FlrigOutcome(method: "rig.set_ptt", reply: .value(""), releaseCheck: .unknown("rig.get_ptt got no answer from flrig")))
        check(errors.pttWarning?.contains("cannot tell") == true, "an unknown state is a warning")
        errors.record(FlrigOutcome(method: "rig.set_ptt", reply: .value(""), releaseCheck: .released(attempts: 2)))
        check(errors.pttWarning == nil, "a release that is read back as off ends the warning")
        errors.record(FlrigOutcome(method: "rig.set_ptt", reply: .value(""), releaseCheck: .stillKeyed(attempts: 1)))
        errors = FlrigErrorState()
        check(errors.pttWarning == nil, "a new FlrigErrorState (Connect, Disconnect) starts without a warning")

        print("FlrigPTTReleaseRegression: \(checks) checks, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
