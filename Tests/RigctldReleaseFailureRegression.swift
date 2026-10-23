import Foundation
import Network

nonisolated enum AmateurBandPlan {
    static func band(forMHz frequency: Double) -> String? { nil }
    static func formattedMHz(_ frequency: Double) -> String { String(frequency) }
}
nonisolated final class NWConnection: @unchecked Sendable {
    enum State { case ready, waiting(NWError), failed(NWError), cancelled }
    enum SendCompletion { case contentProcessed(@Sendable (NWError?) -> Void) }
    final class ContentContext: Sendable {}
    nonisolated(unsafe) static var instances: [NWConnection] = []
    var stateUpdateHandler: (@Sendable (State) -> Void)?
    var writeError: NWError?
    var deferWrites = false
    var completions: [@Sendable (NWError?) -> Void] = []
    var sent: [String] = []
    init(host: NWEndpoint.Host, port: NWEndpoint.Port, using: NWParameters) { Self.instances.append(self) }
    func start(queue: DispatchQueue) { stateUpdateHandler?(.ready) }
    func cancel() {}
    func receive(minimumIncompleteLength: Int, maximumLength: Int, completion: @escaping @Sendable (Data?, ContentContext?, Bool, NWError?) -> Void) {}
    func send(content: Data?, completion: SendCompletion) {
        sent.append(String(decoding: content ?? Data(), as: UTF8.self))
        if case .contentProcessed(let done) = completion {
            if deferWrites { completions.append(done) } else { done(writeError) }
        }
    }
}
@main
struct RigctldReleaseFailureRegression {
    static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.08)) }
    static func main() {
        let a = RigControlClient()
        a.connect(host: "a.invalid", port: 4532); pump()
        precondition(a.state.isConnected)
        let first = NWConnection.instances.last!
        a.setPTT(true)
        first.writeError = .posix(.EPIPE)
        a.setPTT(false); pump()
        precondition(TransmitNotices.shared.notices.contains { $0.text.contains("T 0 write failed") && $0.text.contains("a.invalid") })
        first.writeError = nil
        a.connect(host: "c.invalid", port: 4532); pump()
        a.setPTT(true)
        let replacement = NWConnection.instances.last!
        replacement.stateUpdateHandler?(.failed(.posix(.ECONNRESET))); pump()
        precondition(TransmitNotices.shared.notices.contains { $0.text.contains("link failed during TX") })
        a.disconnect(); pump()

        var b: RigControlClient? = RigControlClient()
        b!.connect(host: "b.invalid", port: 4533); pump()
        let removed = NWConnection.instances.last!
        b!.setPTT(true)
        removed.deferWrites = true
        b!.disconnect()
        weak var retired = b
        b = nil; pump()
        precondition(retired == nil)
        removed.completions.forEach { $0(.posix(.EPIPE)) }; pump()
        precondition(TransmitNotices.shared.notices.contains { $0.text.contains("T 0 write failed") && $0.text.contains("b.invalid") }, "Removing a Multi-Rig slot must not discard its delayed release failure")
        print("PASS real rigctld client: release write errors, TX link loss, per-slot notices and delayed failure after slot removal; no sockets")
    }
}
