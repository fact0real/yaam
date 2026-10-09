import Foundation

// Pure helpers for YAAM's ways of talking to flrig's XML-RPC server (default 127.0.0.1:12345).
// Foundation only, so it can be regression-tested standalone:
//   swiftc -parse-as-library Tests/FlrigXMLRPCRegression.swift YAAM/FlrigXMLRPC.swift -o /tmp/flrigx && /tmp/flrigx
//
// What flrig 2.0.12 does (read in xml_server.cxx, checked against a running flrig):
//  - rig.set_vfo reads its argument as <double>; rig.set_power and rig.set_ptt read <i4>; rig.set_mode reads <string>.
//    Any other type is answered with a fault ("type error").
//  - A fault arrives with HTTP 200. Only the body says "fault".
//  - rig.get_xcvr answers "NONE" when no radio is selected in flrig, "" when a radio is configured but did not answer
//    at start-up (or flrig's XML-RPC control is switched off), and the radio's name otherwise. In the first two cases
//    the other get_* methods return made-up values (rig.get_vfo = 14070000, rig.get_mode = USB): they must not be read.
//  - When the radio is switched off later, rig.get_xcvr, rig.get_vfo and rig.get_mode keep returning the same
//    values (watched for more than 20 s with a simulated radio). YAAM therefore says "flrig reports ...", never "radio connected".

/// One XML-RPC parameter with the type flrig expects.
nonisolated enum FlrigParam: Equatable, Sendable {
    case int(Int)
    case double(Double)
    case string(String)
}

/// What flrig answered.
nonisolated enum FlrigReply: Equatable, Sendable {
    case value(String)                       // the scalar result as text; "" for an empty <value></value>
    case fault(code: Int, message: String)   // HTTP 200 with a <fault> body
    case malformed                           // not an XML-RPC reply YAAM can read

    var text: String? {
        if case .value(let text) = self { return text }
        return nil
    }
}

/// What YAAM knows about flrig and its radio, from one rig.get_xcvr call.
public nonisolated enum FlrigLink: Equatable, Sendable {
    case idle                      // YAAM has not asked yet
    case unreachable               // no answer on host:port
    case noRadio                   // get_xcvr = NONE
    case radioNotAnswering         // get_xcvr = "": the radio set up in flrig did not answer at start-up, or XML-RPC control is off in flrig
    case reporting(String)         // get_xcvr = the radio's name
    case unexpected(String)        // a fault, or something that is not flrig

    public var isReporting: Bool {
        if case .reporting = self { return true }
        return false
    }

    public var radioName: String? {
        if case .reporting(let name) = self { return name }
        return nil
    }

    /// Short text for a status pill.
    public var summary: String {
        switch self {
        case .idle: return "flrig: not connected"
        case .unreachable: return "flrig: not reachable"
        case .noRadio: return "flrig: no radio selected"
        case .radioNotAnswering: return "flrig: no radio name"
        case .reporting(let name): return "flrig reports \(name)"
        case .unexpected: return "flrig: unexpected answer"
        }
    }

    /// One or two sentences for a banner. Never claims more than flrig says.
    public var detail: String {
        switch self {
        case .idle:
            return "Not connected to flrig."
        case .unreachable:
            return "YAAM cannot reach flrig. flrig may not be running, the host and port may differ from flrig's XML-RPC settings, or flrig may be waiting for you to close one of its own windows."
        case .noRadio:
            return "flrig is running but has no radio selected (it reports NONE). Choose the radio in flrig under Config > Setup > Transceiver."
        case .radioNotAnswering:
            return "flrig is running but reports an empty radio name: the radio set up in flrig did not answer when flrig started, or XML-RPC control is switched off in flrig. Check the cable and the radio's power, then open Config > Setup > Transceiver in flrig and press Init."
        case .reporting(let name):
            return "flrig reports \(name). If the radio is switched off later, flrig keeps reporting the last frequency."
        case .unexpected(let why):
            return why
        }
    }

    /// The text for an error banner: set only while flrig is not usable (not while idle or reporting a radio).
    public var problem: String? {
        switch self {
        case .idle, .reporting: return nil
        case .unreachable, .noRadio, .radioNotAnswering, .unexpected: return detail
        }
    }
}

// MARK: - Commands

/// One request to flrig. A request is made only by the functions below, each with the parameter types flrig reads,
/// and call sites pass the result on; nothing outside this file builds a method name and a parameter list by hand.
/// (rig.set_power with the watts as a <string> was how flrig came to answer "type error" and ignore the command.)
nonisolated struct FlrigCommand: Equatable, Sendable {
    let method: String
    let params: [FlrigParam]

    private init(_ method: String, _ params: [FlrigParam] = []) {
        self.method = method
        self.params = params
    }

    // Queries
    static let getXcvr = FlrigCommand("rig.get_xcvr")
    static let getVFO = FlrigCommand("rig.get_vfo")
    static let getMode = FlrigCommand("rig.get_mode")
    static let getPower = FlrigCommand("rig.get_power")
    static let getSmeter = FlrigCommand("rig.get_smeter")
    static let getPTT = FlrigCommand("rig.get_ptt")

    // Commands
    static func setVFO(hz: Double) -> FlrigCommand { FlrigCommand("rig.set_vfo", [.double(hz)]) }
    static func setPower(watts: Int) -> FlrigCommand { FlrigCommand("rig.set_power", [.int(watts)]) }
    static func setPTT(_ transmit: Bool) -> FlrigCommand { FlrigCommand("rig.set_ptt", [.int(transmit ? 1 : 0)]) }
    static func setMode(_ name: String) -> FlrigCommand { FlrigCommand("rig.set_mode", [.string(name)]) }

    /// True for rig.set_ptt 0. Every place that sends it goes through FlrigPTTRelease (see below).
    var isPTTRelease: Bool { self == FlrigCommand.setPTT(false) }

    /// The XML-RPC request body.
    var body: String { FlrigXMLRPC.requestBody(method: method, params: params) }

    /// "rig.set_power i4:10": the method and the typed parameters, for logs and tests.
    var summary: String {
        let args = params.map { param -> String in
            switch param {
            case .int(let value): return "i4:\(value)"
            case .double(let value): return "double:\(String(format: "%.1f", value))"
            case .string(let value): return "string:\(value)"
            }
        }
        return ([method] + args).joined(separator: " ")
    }
}

/// What flrig answered to one command (or to the last call of a sequence of commands).
nonisolated struct FlrigOutcome: Equatable, Sendable {
    let method: String
    let reply: FlrigReply?       // nil = no usable answer
    var releaseCheck: FlrigPTTCheck? = nil   // set when the outcome comes from FlrigPTTRelease (a rig.set_ptt 0 that was read back)
}

nonisolated enum FlrigXMLRPC {

    // MARK: Request

    /// XML-RPC request body. Parameters keep their type; text is XML-escaped.
    static func requestBody(method: String, params: [FlrigParam] = []) -> String {
        var xml = "<?xml version=\"1.0\"?><methodCall><methodName>\(method)</methodName><params>"
        for param in params {
            switch param {
            case .int(let value): xml += "<param><value><i4>\(value)</i4></value></param>"
            case .double(let value): xml += "<param><value><double>\(String(format: "%.1f", value))</double></value></param>"
            case .string(let value): xml += "<param><value><string>\(xmlEscape(value))</string></value></param>"
            }
        }
        return xml + "</params></methodCall>"
    }

    static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// "&amp;" is decoded last, so "&amp;lt;" becomes the text "&lt;" and not "<".
    static func xmlUnescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Reply

    /// Reads one flrig reply. flrig answers scalars as <value>text</value> (strings) or <value><i4>n</i4></value>.
    /// A <fault> is never returned as a value (the old engine parser read its faultCode, -1, as if it were the result).
    static func parse(_ data: Data) -> FlrigReply {
        guard let body = String(data: data, encoding: .utf8), body.contains("<methodResponse") else { return .malformed }

        if let fault = body.range(of: "<fault>") {
            let rest = String(body[fault.upperBound...])
            let code = member(named: "faultCode", in: rest).flatMap { Int($0) } ?? -1
            let message = member(named: "faultString", in: rest) ?? ""
            return .fault(code: code, message: message)
        }

        guard let open = body.range(of: "<param>"),
              let close = body.range(of: "</param>", range: open.upperBound..<body.endIndex) else { return .malformed }
        let param = String(body[open.upperBound..<close.lowerBound])
        guard let valueOpen = param.range(of: "<value>"),
              let valueClose = param.range(of: "</value>", options: .backwards),
              valueOpen.upperBound <= valueClose.lowerBound else { return .malformed }
        let inner = String(param[valueOpen.upperBound..<valueClose.lowerBound])
        if inner.contains("<array") || inner.contains("<struct") { return .malformed }   // YAAM reads no lists
        return .value(xmlUnescape(stripTags(inner)).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    /// Text of <member><name>NAME</name><value>...</value></member>.
    private static func member(named name: String, in text: String) -> String? {
        guard let start = text.range(of: "<name>\(name)</name>"),
              let end = text.range(of: "</member>", range: start.upperBound..<text.endIndex) else { return nil }
        return xmlUnescape(stripTags(String(text[start.upperBound..<end.lowerBound]))).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Connection state

    /// `reply` is nil when flrig gave no usable HTTP answer at all.
    static func link(forXcvr reply: FlrigReply?) -> FlrigLink {
        switch reply {
        case nil:
            return .unreachable
        case .value(let raw)?:
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { return .radioNotAnswering }
            if name.uppercased() == "NONE" { return .noRadio }
            return .reporting(name)
        case .fault(_, let message)?:
            return .unexpected("The server answered rig.get_xcvr with an error (\(message)). Is this flrig?")
        case .malformed?:
            return .unexpected("The server's answer to rig.get_xcvr is not XML-RPC. Is this flrig?")
        }
    }
}

// MARK: - Transport

nonisolated enum FlrigTransport {

    /// One request to flrig. nil = no usable HTTP answer (refused, timed out, a status other than 200). A fault comes
    /// back as .fault, never as a value. The only error thrown is CancellationError: a request that was cancelled
    /// (the user disconnected) is not "flrig cannot be reached".
    static func send(_ command: FlrigCommand, host: String, port: Int, session: URLSession = .shared,
                     timeout: TimeInterval? = nil, userAgent: String? = nil) async throws -> FlrigReply? {
        guard let url = URL(string: "http://\(host):\(port)") else { return nil }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        if let timeout { request.timeoutInterval = timeout }
        request.httpMethod = "POST"
        request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        request.httpBody = Data(command.body.utf8)

        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return FlrigXMLRPC.parse(data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    /// For commands that run in a FlrigCommandChain job: those jobs are never cancelled, so a failure is just nil.
    static func sendUncancelled(_ command: FlrigCommand, host: String, port: Int, session: URLSession = .shared,
                                timeout: TimeInterval? = nil, userAgent: String? = nil) async -> FlrigReply? {
        (try? await send(command, host: host, port: port, session: session, timeout: timeout, userAgent: userAgent)) ?? nil
    }
}

// MARK: - Order of commands

/// Runs flrig commands one at a time, in the order they were queued. `enqueue` is not async: the place in the line
/// is taken at the moment of the call, so two calls made one after the other on the main actor are sent in that
/// order, and the last PTT wish is the last one flrig receives. (Commands sent as separate Tasks reach flrig in any
/// order: in a test about half of 60 back-to-back key-down/key-up pairs arrived reversed, which leaves the radio keyed.)
/// A job is never cancelled by its caller: a release that is queued is still sent.
nonisolated final class FlrigCommandChain: @unchecked Sendable {
    private let lock = NSLock()
    private var tail: Task<Void, Never> = Task {}

    @discardableResult
    func enqueue<T: Sendable>(_ work: @escaping @Sendable () async -> T) -> Task<T, Never> {
        lock.lock()
        defer { lock.unlock() }
        let previous = tail
        let job = Task { () -> T in
            await previous.value
            return await work()
        }
        tail = Task { _ = await job.value }
        return job
    }
}

// MARK: - Releasing PTT, and making sure it was released

/// What the check after a rig.set_ptt 0 found.
nonisolated enum FlrigPTTCheck: Equatable, Sendable {
    /// rig.get_ptt read 0 after rig.set_ptt 0 had been sent `attempts` times (1 = the first try worked).
    case released(attempts: Int)
    /// rig.get_ptt still read 1 after the last of `attempts` calls of rig.set_ptt 0.
    case stillKeyed(attempts: Int)
    /// YAAM could not read the state (no answer, a fault, something that is not 0 or 1). `String` says why.
    case unknown(String)

    /// For the operator. nil when the release is confirmed. It says "may", because flrig's answer is all that is known.
    var warning: String? {
        switch self {
        case .released:
            return nil
        case .stillKeyed(let attempts):
            let times = attempts == 1 ? "once" : "\(attempts) times"
            return "The radio may still be transmitting: flrig still reports PTT on after YAAM sent rig.set_ptt 0 \(times). Release PTT in flrig or on the radio."
        case .unknown(let why):
            return "YAAM cannot tell whether the radio has stopped transmitting: \(why). Check the radio."
        }
    }

    /// For the system log: every result that is not "released at the first try".
    var logLine: String? {
        switch self {
        case .released(let attempts):
            return attempts > 1 ? "rig.get_ptt read PTT off only after rig.set_ptt 0 had been sent \(attempts) times" : nil
        case .stillKeyed, .unknown:
            return warning
        }
    }
}

/// rig.set_ptt 0, read back with rig.get_ptt and repeated if flrig still reports PTT on.
///
/// Why: flrig 2.0.12's rig.set_ptt writes the requested value to the global PTT before it takes the serial lock
/// (xml_server.cxx:1947, lock at :1955). If flrig's own poll is talking to the radio at that moment and the radio is still
/// transmitting, the poll writes PTT = 1 (support.cxx:1263), and rigPTT(PTT) at :1961 sends TX; instead of RX;. The
/// check at :1963-1969 then sees 1 = 1. rig.get_ptt returns flrig's PTT (xml_server.cxx:321-334), so it reads 1.
/// rig.set_verify_ptt (:1900, :1908, :1914) and rig.set_ptt_fast (:2031, :2040, :2045) have the same order; YAAM sends neither.
///
/// Every rig.set_ptt 0 that YAAM sends to flrig goes through `release`: RigControlEngine.flrigEnqueue, FLRigClient.run
/// (rig.set_ptt 0 from setPTT) and FlrigSequences.stopCW. It runs inside one job of a FlrigCommandChain, so nothing
/// can be sent between the release, the read-back and the repeats, and the release is still the last command.
///
/// The policy (the numbers come from runs against flrig 2.0.12 with a simulated radio):
///  - After each rig.set_ptt 0, ask rig.get_ptt at once. flrig answers from the value it read from the radio at the end
///    of rig.set_ptt (it updates xml_A at :1971 and rig.get_ptt uses that value for 200 ms, :61 and :321), so the read-back
///    needs no extra serial exchange and costs one local request.
///  - Reads 0: released. Reads 1: send rig.set_ptt 0 again, at most three times, after 100, 200 and 300 ms.
///    A repeat can only turn a transmitting radio to receive: if the radio is in receive, the poll writes PTT = 0.
///  - Why three repeats: in 160 releases against flrig 2.0.12, 13 went wrong (8.1 %, 95 % interval 4.8 to 13.4 %). If each
///    try went wrong independently with that chance, four tries in a row would all go wrong in about 1 release in 23,000
///    (1 in 3,100 at the top of the interval); two repeats would leave 1 in 1,900 (1 in 415). More repeats would only keep
///    the command chain busy longer when the radio really cannot be released.
///  - Why 100, 200 and 300 ms: short, so that the release is not late (0.6 s in all). The first is longer than flrig's lock
///    retry step (50 ms, threads.cxx:46-58) and one serial exchange (14 ms in the run), so a repeat does not queue behind the
///    exchange that went wrong. They grow because flrig read the radio's PTT 89 to 867 ms apart while transmitting
///    (10th to 90th percentile), so no single pause could be chosen to miss the poll; growing pauses put the repeats at
///    different points of it; a model of the race shows that the outcome hardly depends on the pauses unless a fixed pause
///    is close to the poll period. (A radio that is slow to drop is not what the repeats are for: one rig.set_ptt already waits
///    for it, up to 100 x (10 ms + one serial exchange), :1965-1968.)
///  - A repeat is sent only after rig.set_ptt 0 was answered with a value. A refusal would be repeated as a refusal,
///    and a missing answer means flrig is busy: more requests would only queue behind it.
///  - rig.get_ptt with no answer, a fault, or something other than 0 or 1: the state is unknown. That is reported as
///    unknown, never as released. With a radio that does not answer, flrig's own rig.get_ptt takes about 240 ms instead of
///    30 ms, far below YAAM's 1.5 s and 2 s time-outs.
nonisolated enum FlrigPTTRelease {
    /// The pause before each repeat, in nanoseconds. The count is the number of repeats.
    static let repeatPauses: [UInt64] = [100_000_000, 200_000_000, 300_000_000]

    /// Sends rig.set_ptt 0, reads rig.get_ptt, repeats while it reads 1. The outcome has method rig.set_ptt, the
    /// answer to the last rig.set_ptt 0, and the result of the read-back.
    static func release(send: FlrigSequences.Send, pause: FlrigSequences.Pause) async -> FlrigOutcome {
        let command = FlrigCommand.setPTT(false)
        var attempts = 1
        var reply = await send(command)
        while true {
            let check: FlrigPTTCheck
            switch reading(of: await send(.getPTT)) {
            case .off:
                check = .released(attempts: attempts)
            case .unreadable(let why):
                check = .unknown(why)
            case .on:
                guard attempts <= repeatPauses.count, case .value? = reply else {
                    check = .stillKeyed(attempts: attempts)
                    break
                }
                await pause(repeatPauses[attempts - 1])
                attempts += 1
                reply = await send(command)
                continue
            }
            return FlrigOutcome(method: command.method, reply: reply, releaseCheck: check)
        }
    }

    private enum Reading {
        case off, on
        case unreadable(String)
    }

    private static func reading(of reply: FlrigReply?) -> Reading {
        switch reply {
        case nil:
            return .unreadable("rig.get_ptt got no answer from flrig")
        case .fault(_, let message)?:
            return .unreadable("flrig refused rig.get_ptt (\(message))")
        case .malformed?:
            return .unreadable("the answer to rig.get_ptt could not be read")
        case .value(let text)?:
            switch Int(text) {
            case 0?: return .off
            case 1?: return .on
            default: return .unreadable("rig.get_ptt answered \"\(text.prefix(30))\"")
            }
        }
    }
}

// MARK: - What went wrong, for the user

/// The error text of a flrig connection. A refused command stays until the next command flrig accepts or until the
/// link changes; the text is only reported when it differs from what is shown, so a poll that sees the same
/// problem every 0.5 s does not publish it again.
nonisolated struct FlrigErrorState: Equatable, Sendable {
    private(set) var commandFault: String?
    /// Set when a rig.set_ptt 0 could not be confirmed (see FlrigPTTCheck). Unlike a refused command it is not cleared by
    /// the next accepted command or by a link change: the radio may still be keyed. It is cleared by a release that
    /// is read back as off, by a poll that reads PTT off, and by Connect and Disconnect (a new FlrigErrorState).
    private(set) var pttWarning: String?
    private var lastLogged: String?

    mutating func refused(_ method: String, _ message: String) {
        commandFault = "flrig refused \(method): \(message)"
    }

    /// A command got a value back.
    mutating func succeeded() { commandFault = nil }

    /// What flrig answered to a command: a fault is kept, a value clears it, no answer changes nothing. A release
    /// that was read back also sets or clears the PTT warning.
    mutating func record(_ outcome: FlrigOutcome) {
        switch outcome.reply {
        case .fault(_, let message)?: refused(outcome.method, message)
        case .value?: succeeded()
        case .malformed?, nil: break
        }
        if let check = outcome.releaseCheck { pttWarning = check.warning }
    }

    /// A poll read rig.get_ptt. Reading it off ends a PTT warning (true = the warning was cleared); reading it on
    /// changes nothing, since that is what a transmission looks like.
    mutating func pttObserved(keyed: Bool) -> Bool {
        guard !keyed, pttWarning != nil else { return false }
        pttWarning = nil
        return true
    }

    /// The link to flrig changed (or was reset): an old refusal no longer says anything. A PTT warning stays.
    mutating func linkChanged() { commandFault = nil }

    /// What `lastError` should say now: a radio that may be keyed first, then a refused command, then the link.
    func text(for link: FlrigLink) -> String? { pttWarning ?? commandFault ?? link.problem }

    /// For the system log: the problem the first time it is seen, nil while it stays the same.
    mutating func newProblemToLog(_ problem: String?) -> String? {
        defer { lastLogged = problem }
        guard let problem, problem != lastLogged else { return nil }
        return problem
    }
}

// MARK: - CW through flrig's cwio

extension FlrigCommand {
    /// rig.cwio_set_wpm. flrig's CW speed slider runs from 5 to 100 wpm (cwioUI.fl).
    nonisolated static func cwSpeed(wpm: Int) -> FlrigCommand { FlrigCommand("rig.cwio_set_wpm", [.int(min(100, max(5, wpm)))]) }

    /// rig.cwio_text with "[TEXT]". flrig starts sending at "[" and stops at "]"; a text without "[" is only queued
    /// (cwio.cxx add_cwio). "[" and "]" inside the text would start or end the sending early, so they are removed.
    /// The text is sent in upper case, the form that was run against flrig. nil = nothing to send.
    nonisolated static func cwText(_ text: String) -> FlrigCommand? {
        let cleaned = String(text.uppercased().filter { $0 != "[" && $0 != "]" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : FlrigCommand("rig.cwio_text", [.string("[" + cleaned + "]")])
    }

    /// rig.cwio_send 0: finish the letter in progress and drop the rest of the text.
    nonisolated static let cwStop = FlrigCommand("rig.cwio_send", [.int(0)])
}

/// Call sequences that need more than one request. `send` is the caller's own transport, so the order of requests
/// and the pauses can be tested without a network.
nonisolated enum FlrigSequences {
    typealias Send = (_ command: FlrigCommand) async -> FlrigReply?
    typealias Pause = (_ nanoseconds: UInt64) async -> Void

    /// After a stop, flrig empties its text box a moment later on its own thread (xml_server.cxx:4210-4221), while
    /// rig.cwio_text writes the box at once (cwio.cxx:631-650): text that arrives in between can be wiped. The stop
    /// therefore ends with this pause, so the next command in the chain (the next message) starts 150 ms later.
    static let pauseAfterStop: UInt64 = 150_000_000

    /// CW: set the speed, then queue "[text]". flrig makes the Morse timing itself and keys the line set in its
    /// "CW keying" window. nil = nothing to send. Otherwise the answer of the call that failed (a fault from the speed
    /// call stops the sequence: the text is not sent), or of the last call.
    static func sendCW(_ text: String, wpm: Int?, send: Send) async -> FlrigOutcome? {
        guard let textCommand = FlrigCommand.cwText(text) else { return nil }
        if let wpm {
            let speed = FlrigCommand.cwSpeed(wpm: wpm)
            let reply = await send(speed)
            if case .fault? = reply { return FlrigOutcome(method: speed.method, reply: reply) }
        }
        return FlrigOutcome(method: textCommand.method, reply: await send(textCommand))
    }

    /// Stop CW: cwio_send 0 finishes the letter in progress and drops the rest of the text; set_ptt 0 releases a PTT
    /// that cwio_send 1 may have keyed with no text behind it (cwio_send 0 does not release that one). Both are always
    /// sent, the release is read back and repeated if flrig still reports PTT on (FlrigPTTRelease), then the pause.
    /// Returns the first answer that is not a value (a fault, or nil for no answer), or the last value; in both cases
    /// with the result of the read-back.
    static func stopCW(send: Send, pause: Pause) async -> FlrigOutcome {
        let stop = FlrigCommand.cwStop
        let first = await send(stop)
        let release = await FlrigPTTRelease.release(send: send, pause: pause)
        await pause(pauseAfterStop)
        if case .value? = first { return release }
        return FlrigOutcome(method: stop.method, reply: first, releaseCheck: release.releaseCheck)
    }
}
