import Foundation

// Shadows only in this executable. No WebSocket, network, radio or audio device can be opened.
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
    static var suppressPongs = false
    var sent: [String] = []
    var cancelled = false
    var completeWrites = true
    var writeError: Error?
    var completions: [(Error?) -> Void] = []
    var received: ((Result<Message, Error>) -> Void)?
    func resume() {}
    func send(_ message: Message, completionHandler: @escaping (Error?) -> Void) {
        if case .string(let text) = message { sent.append(text) }
        if completeWrites { completionHandler(writeError) } else { completions.append(completionHandler) }
    }
    func receive(completionHandler: @escaping (Result<Message, Error>) -> Void) { received = completionHandler }
    func sendPing(pongReceiveHandler: @escaping (Error?) -> Void) { if !Self.suppressPongs { pongReceiveHandler(nil) } }
    func cancel(with: CloseCode, reason: Data?) { cancelled = true }
    func deliver(_ text: String) { received?(.success(.string(text))) }
}
nonisolated enum AmateurBandPlan {
    static func band(forMHz value: Double) -> String? { nil }
}
@main
struct TCIReleaseIntegrationRegression {
    static func pump(_ seconds: Double = 0.05) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    static func main() {
        let client = TCIClient()
        client.connect(host: "fixture.invalid", port: 40001)
        let old = URLSession.tasks.last!
        old.deliver("ready;"); pump()
        precondition(client.isConnected)
        client.setPTT(true, receiver: 2)
        client.setTune(true, receiver: 3)
        precondition(client.holdsTransmit)
        old.completeWrites = false
        client.disconnect()
        precondition(!old.cancelled, "The socket must stay alive until the release write completes")
        let release = old.sent.last!
        for command in ["trx:2,false;", "tune:3,false;", "cw_macros_stop;"] { precondition(release.contains(command)) }
        old.completions.forEach { $0(nil) }
        precondition(old.cancelled && !client.holdsTransmit)
        client.connect(host: "fixture.invalid", port: 40001)
        let current = URLSession.tasks.last!
        current.deliver("ready;"); pump()
        old.deliver("trx:9,true;"); pump()
        precondition(!client.isPTTActive, "A retired connection must not publish state into its replacement")
        client.sendCW(text: "TEST")
        precondition(client.holdsTransmit, "CW macros participate in shutdown ownership without a trx event")
        current.deliver("trx:0,true;"); pump()
        current.deliver("trx:0,false;"); pump()
        precondition(!client.holdsTransmit, "Server TX-to-RX ends macro ownership without trusting the local clock")
        client.sendCW(text: "TEST")
        current.received?(.failure(NSError(domain: "fixture", code: 1)))
        pump()
        precondition(!client.isConnected && current.cancelled)
        precondition(TransmitNotices.shared.notices.contains { $0.text.contains("may still be transmitting") })
        client.stopCW() // must not erase the persistent warning or the pending original endpoint
        client.connect(host: "other.invalid", port: 40001)
        let other = URLSession.tasks.last!
        other.deliver("ready;"); pump()
        precondition(other.sent.isEmpty, "Recovery must not stop an unrelated SDR")
        client.connect(host: "fixture.invalid", port: 40001)
        let recovered = URLSession.tasks.last!
        recovered.completeWrites = false
        recovered.deliver("ready;"); pump()
        client.setPTT(true)
        precondition(recovered.sent.count == 1 && recovered.sent[0].hasPrefix("cw_macros_stop;"), "Recovery release precedes every possible key-down")
        recovered.completions.forEach { $0(nil) }; recovered.completeWrites = true; pump()
        precondition(client.isConnected)
        client.setPTT(true, receiver: 4)
        recovered.writeError = NSError(domain: "fixture-write", code: 2)
        client.setPTT(false, receiver: 4); pump()
        precondition(!client.isConnected && TransmitNotices.shared.notices.contains { $0.text.contains("release write failed") })
        client.connect(host: "fixture.invalid", port: 40001)
        let final = URLSession.tasks.last!; final.deliver("ready;"); pump()
        precondition(final.sent.first?.contains("trx:4,false;") == true, "Recovery retains the exact receiver whose release write failed")
        URLSessionWebSocketTask.suppressPongs = true
        let silentClient=TCIClient(); silentClient.connect(host:"silent.invalid",port:40001)
        let silent=URLSession.tasks.last!; silent.deliver("ready;"); pump()
        silentClient.sendCW(text:"TEST"); pump(3.3)
        precondition(!silentClient.isConnected && silent.cancelled)
        precondition(TransmitNotices.shared.notices.contains{$0.text.contains("No WebSocket pong") && $0.text.contains("may still be transmitting")})
        silentClient.disconnect(); URLSessionWebSocketTask.suppressPongs = false
        client.setPTT(true, receiver: 4)
        TransmitShutdown.beginShutdown()
        _ = TransmitShutdown.releaseAll()
        precondition(final.sent.contains { $0.contains("trx:4,false;") })
        let count = final.sent.count
        client.setPTT(true); client.setTune(true); client.sendCW(text: "TEST")
        precondition(final.sent.count == count && !client.holdsTransmit, "Shutdown must refuse all new key-downs")
        print("PASS TCI multi-receiver release before close, stale callbacks and shutdown latch without sockets")
    }
}
