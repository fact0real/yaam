import Foundation

// Shadows only in this executable. No WebSocket, network, radio or audio device can be opened: every command TCIClient
// sends is recorded in `sent`, so the test checks exactly what an SDR would receive.
final class URLSession {
    static var tasks: [URLSessionWebSocketTask] = []
    init(configuration: URLSessionConfiguration) {}
    func webSocketTask(with url: URL) -> URLSessionWebSocketTask {
        let task = URLSessionWebSocketTask()
        Self.tasks.append(task)
        return task
    }
}
final class URLSessionWebSocketTask {
    enum Message { case string(String), data(Data) }
    enum CloseCode { case goingAway }
    var sent: [String] = []
    var received: ((Result<Message, Error>) -> Void)?
    func resume() {}
    func send(_ message: Message, completionHandler: @escaping (Error?) -> Void) {
        if case .string(let text) = message { sent.append(text) }
        completionHandler(nil)
    }
    func receive(completionHandler: @escaping (Result<Message, Error>) -> Void) { received = completionHandler }
    func sendPing(pongReceiveHandler: @escaping (Error?) -> Void) { pongReceiveHandler(nil) }
    func cancel(with: CloseCode, reason: Data?) {}
    func deliver(_ text: String) { received?(.success(.string(text))) }
}
nonisolated enum AmateurBandPlan {
    static func band(forMHz value: Double) -> String? { nil }
}

/// What YAAM sends to the SDR over TCI from text it did not write: CW text, and the DX cluster's or WSJT-X's spots.
@main
struct TCIOutsideTextRegression {
    nonisolated(unsafe) static var failures = 0
    static func check(_ condition: Bool, _ name: String) {
        print((condition ? "PASS " : "FAIL ") + name)
        if !condition { failures += 1 }
    }
    static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

    static func main() {
        let client = TCIClient()
        client.connect(host: "fixture.invalid", port: 40001)
        let socket = URLSession.tasks.last!
        socket.deliver("ready;"); pump()
        precondition(client.isConnected)

        // CW: TCI Protocol 2.1 names the command CW_MACROS (case does not matter); there is no "cw_macro".
        socket.sent.removeAll()
        client.sendCW(text: "CQ DE EA3JIC", wpm: 25)
        check(socket.sent.contains("cw_macros_speed:25;"), "CW speed is sent as cw_macros_speed")
        check(socket.sent.contains("cw_macros:0,CQ DE EA3JIC;"), "CW text is sent with cw_macros, the command TCI has")
        check(!socket.sent.contains { $0.hasPrefix("cw_macro:") }, "nothing is sent as cw_macro:, which TCI does not have")

        // CW text: TCI reserves ":", "," and ";"; the protocol sends them as "^", "~" and "*" (Working in CW mode).
        socket.sent.removeAll()
        client.sendCW(text: "UR RST 599, NAME EA3JIC", wpm: 25)
        check(socket.sent.contains("cw_macros:0,UR RST 599~ NAME EA3JIC;"), "a comma in CW text is sent as ~, not as an argument break")
        check(TCIClient.macroText("A:B,C;D") == "A^B~C*D", "macroText sends : , ; as ^ ~ *")

        // Spots come from the DX cluster or WSJT-X: text from outside, written by anyone. A ";" in it must not end the
        // spot command and let the rest be read as another one, such as trx:0,true; (which keys the SDR).
        // The protocol says the case of letters does not matter, so TRX:0,TRUE counts too.
        socket.sent.removeAll()
        let keyings = { socket.sent.filter { $0.lowercased().contains("trx:0,true") }.count }
        check(client.postSpot(callsign: "EP2AES", mode: "CW", frequencyHz: 7_030_000, text: "UR 599, TNX; QSL: OK"), "a spot is sent")
        check(socket.sent.contains("spot:EP2AES,cw,7030000,4278255360,UR 599~ TNX* QSL^ OK;"),
              "its comment's :, , and ; go as ^, ~ and *")
        check(client.postSpot(callsign: "EP2AES", mode: "CW", frequencyHz: 7_030_000, text: "x;trx:0,true;"),
              "a spot whose comment carries a command is still sent")
        check(socket.sent.contains("spot:EP2AES,cw,7030000,4278255360,x*trx^0~true*;"), "but the command in it arrives as text only")
        let count = socket.sent.count
        check(!client.postSpot(callsign: "EP2AES;trx:0,true", mode: "CW", frequencyHz: 7_030_000),
              "a callsign with a reserved character: the spot is not sent")
        check(!client.postSpot(callsign: "EP2AES", mode: "cw;trx:0,true", frequencyHz: 7_030_000),
              "a mode with a reserved character: the spot is not sent")
        check(!client.postSpot(callsign: "EP2AES", mode: " ", frequencyHz: 7_030_000),
              "an empty mode: the spot is not sent (TCI drops empty arguments, and the fields would shift)")
        client.deleteSpot(callsign: "EP2AES;trx:0,true")
        check(socket.sent.count == count, "nothing is sent for them, nor to delete a spot whose callsign has a reserved character")
        check(keyings() == 0, "nothing the SDR could read as trx:0,true; was sent")

        // Tuning to a spot sets its mode, which can come from the DX cluster or a WSJT-X decode on the network.
        socket.sent.removeAll()
        check(client.setMode("CW"), "a mode is sent (unchanged)")
        check(socket.sent.contains("modulation:0,cw;"), "as modulation:0,cw;")
        check(client.mode == "CW", "and shown")
        check(!client.setMode("x;trx:0,true"), "a mode with a reserved character is not sent")
        check(client.mode == "CW", "the mode shown stays the SDR's")
        check((client.lastError ?? "").hasPrefix("TCI: mode \"x;trx:0,true\" not sent to the SDR at ")
                && (client.lastError ?? "").contains("choose the mode by hand"), "and the operator is told why and what to do")
        check(!client.setMode("  "), "an empty mode is not sent")
        check(TCIClient.modeRefusal("FT8") == nil && TCIClient.modeRefusal("cw;trx:0,true") != nil,
              "the bandmap's check (modeRefusal) agrees with setMode")
        let shownText = TCIClient.modeRefusal("a\nFAKE LOG;\t") ?? ""
        check(shownText.hasPrefix("TCI: mode \"a?FAKE LOG;?\" not sent") && !shownText.contains("\n") && !shownText.contains("\t"),
              "a line break or control character in the mode is shown as ?, so it cannot add a line to the log: \(shownText)")
        check(socket.sent == ["modulation:0,cw;"] && keyings() == 0, "nothing reached the SDR from them")

        client.disconnect()
        check(!client.postSpot(callsign: "EP2AES", mode: "CW", frequencyHz: 7_030_000), "without a connection, postSpot says it was not sent")

        if failures > 0 {
            print("TCI outside text regression: \(failures) FAIL")
            exit(1)
        }
        print("TCI outside text regression passed")
    }
}
