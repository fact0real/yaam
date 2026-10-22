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
    var sent: [String] = []
    var cancelled = false
    var completeWrites = true
    var completions: [(Error?) -> Void] = []
    var received: ((Result<Message, Error>) -> Void)?
    func resume() {}
    func send(_ message: Message, completionHandler: @escaping (Error?) -> Void) {
        if case .string(let text) = message { sent.append(text) }
        if completeWrites { completionHandler(nil) } else { completions.append(completionHandler) }
    }
    func receive(completionHandler: @escaping (Result<Message, Error>) -> Void) { received = completionHandler }
    func sendPing(pongReceiveHandler: @escaping (Error?) -> Void) { pongReceiveHandler(nil) }
    func cancel(with: CloseCode, reason: Data?) { cancelled = true }
    func deliver(_ text: String) { received?(.success(.string(text))) }
}
nonisolated enum AmateurBandPlan {
    static func band(forMHz value: Double) -> String? { nil }
}
@main
struct TCIReleaseIntegrationRegression {
    static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
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
        client.setPTT(true, receiver: 4)
        TransmitShutdown.beginShutdown()
        _ = TransmitShutdown.releaseAll()
        precondition(current.sent.contains { $0.contains("trx:4,false;") })
        let count = current.sent.count
        client.setPTT(true); client.setTune(true); client.sendCW(text: "TEST")
        precondition(current.sent.count == count && !client.holdsTransmit, "Shutdown must refuse all new key-downs")
        print("PASS TCI multi-receiver release before close, stale callbacks and shutdown latch without sockets")
    }
}
