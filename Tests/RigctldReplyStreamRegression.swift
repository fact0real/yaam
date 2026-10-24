import Foundation
import Network

nonisolated final class NWConnection: @unchecked Sendable {
    enum SendCompletion { case contentProcessed(@Sendable (NWError?) -> Void) }
    final class ContentContext: Sendable {}
    typealias Read = @Sendable (Data?, ContentContext?, Bool, NWError?) -> Void
    var pending: Read?
    var sent: [String] = []
    var cancelled = false
    var writeError: NWError?
    func send(content: Data?, completion: SendCompletion) {
        sent.append(String(decoding: content ?? Data(), as: UTF8.self))
        if case .contentProcessed(let done) = completion { done(writeError) }
    }
    func receive(minimumIncompleteLength: Int, maximumLength: Int, completion: @escaping Read) { pending = completion }
    func inject(_ text: String) {
        let read = pending; pending = nil
        precondition(read != nil, "Exactly one continuous reader must be waiting")
        read?(Data(text.utf8), nil, false, nil)
    }
    func cancel() { cancelled = true }
}

@main struct RigctldReplyStreamRegression {
    static func pump(_ seconds: Double = 0.03) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    static func main() {
        let c = NWConnection(), s = RigctldReplyStream(NWConnection())
        let stream = RigctldReplyStream(c)
        var errors: [(String, Bool)] = [], replies: [RigctldReplyStream.Reply] = []
        stream.onError = { errors.append(($0, $1)) }
        stream.onReply = { replies.append($0) }
        stream.start()
        stream.send("T 1\nT 0\n")
        precondition(c.sent == ["+T 1\n", "+T 0\n"])
        c.inject("set_ptt: 1\nRPRT 0\nset_pt"); pump()
        c.inject("t: 0\r\nRPR"); pump()
        c.inject("T 0\nget_level: RFPOWER\nRPRT -11\n"); pump()
        precondition(stream.pendingReleases.isEmpty && !stream.hasTransmitRisk)
        precondition(errors.count == 1 && !errors[0].1 && errors[0].0.contains("get_level"))
        precondition(replies[1].command == "set_ptt" && replies[1].arguments == "0")
        print("PASS fragmented/coalesced ERP replies clear release state; refused receive poll is not a TX alert")
        stream.send("b CQ TEST\n\\stop_morse\n")
        c.inject("send_morse: CQ TEST\nRPRT 0\nstop_morse:\nRPRT -11\n"); pump()
        precondition(errors.last!.1 && errors.last!.0.contains("stop_morse"))
        precondition(c.sent.last == "+\\stop_morse\n")
        let before = errors.count
        c.inject("get_freq:\nRPRT -11\nget_mode:\nRPRT -11\n"); pump()
        precondition(errors.dropFirst(before).allSatisfy { !$0.1 })
        print("PASS rejected CW stop is visible; later polls cannot repeatedly replace its safety notice")
        stream.send("T 0\n")
        pump(1.6)
        precondition(stream.pendingReleases.isEmpty && errors.last!.1 && errors.last!.0.contains("timed out"))
        let timedOutCount = errors.count
        pump(0.1)
        precondition(errors.count == timedOutCount)
        print("PASS missing acknowledgement posts once and ends the pending-release window")
        stream.send("T 0\nT 1\n")
        c.inject("set_ptt: 0\nRPRT 0\nset_ptt: 1\nRPRT 0\n"); pump()
        precondition(stream.hasTransmitRisk, "A late old release reply cannot clear a newer key-down")
        stream.send("T 0\n", closeAfterRelease: true)
        precondition(!c.cancelled)
        c.inject("set_ptt: 0\nRPRT -8\n"); pump()
        precondition(c.cancelled && errors.last!.1)
        print("PASS retired connection reads a rejected release before close; newer TX keeps its ownership")
        var lost: Bool?
        s.onError = { _, safety in lost = safety }
        s.send("T 1\n"); s.fail("lost")
        precondition(lost == true)
        print("PASS lost TX connection is a safety event; no sockets or radio devices used")
        let silent=NWConnection(), health=RigctldReplyStream(NWConnection())
        let monitored=RigctldReplyStream(silent)
        var timedOut=false
        monitored.onFailure={ reason,risk in timedOut=reason.contains("stopped answering") && risk }
        monitored.start(); monitored.send("T 1\n")
        pump(3.3)
        precondition(timedOut && silent.sent.contains("+T 0\n") && !silent.cancelled,"A silent link requests RX before its bounded retirement")
        pump(1.6)
        precondition(silent.cancelled)
        health.finish()
        print("PASS an open but silent CAT link expires its reply deadline and retains TX uncertainty")
    }
}
