import Foundation
import Network

nonisolated final class NWConnection: @unchecked Sendable {
    enum State { case ready, failed(NWError), cancelled, setup }
    enum SendCompletion { case contentProcessed(@Sendable (NWError?) -> Void) }
    nonisolated(unsafe) static var instances: [NWConnection] = []
    var stateUpdateHandler: (@Sendable (State) -> Void)?
    var sent: [String] = []
    var cancelled = false
    var writeError: NWError?
    init(host: NWEndpoint.Host, port: NWEndpoint.Port, using: NWParameters) { Self.instances.append(self) }
    final class ContentContext: Sendable {}
    func receive(minimumIncompleteLength: Int, maximumLength: Int, completion: @escaping @Sendable (Data?, ContentContext?, Bool, NWError?) -> Void) {}
    func start(queue: DispatchQueue) { stateUpdateHandler?(.ready) }
    func cancel() { cancelled = true }
    func send(content: Data?, completion: SendCompletion) {
        sent.append(String(decoding: content ?? Data(), as: UTF8.self))
        if case .contentProcessed(let done) = completion { done(writeError) }
    }
}
@main
struct RigControlReleaseDestinationRegression {
    static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    static func main() {
        UserDefaults.standard.set(false, forKey: "rigAutoConnect")
        UserDefaults.standard.set(RigDriverType.disabled.rawValue, forKey: "rigDriverType")
        let rig = RigControlEngine.shared
        rig.driverType = .rigctld
        rig.host = "fixture.invalid"; rig.port = 4532
        rig.connect(); pump()
        precondition(rig.isConnected)
        if CommandLine.arguments.contains("--watchdog-only") {
            let keyed = NWConnection.instances.last!
            rig.setPTT(true)
            rig.driverType = .disabled // settings changed without a transport disconnect
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            precondition(keyed.sent.contains("T 0\n"), "The timer must release its original connection even after the driver selection changes")
            precondition(TransmitShutdown.transmitting.isEmpty, "A completed safety timer must leave no stale transmit owner")
            print("PASS Radio Control watchdog retains original destination across settings changes (accelerated fixture clock)")
            return
        }
        let first = NWConnection.instances.last!
        rig.setPTT(true)
        let release = rig.capturePTTRelease()
        rig.disconnect()
        precondition(first.sent.contains("T 0\n") && first.cancelled)
        rig.connect(); pump()
        let second = NWConnection.instances.last!
        precondition(first !== second && rig.isConnected)
        rig.setPTT(true)
        release()
        first.stateUpdateHandler?(.cancelled); pump()
        precondition(!second.sent.contains("T 0\n") && rig.isPTT && rig.isConnected,
                     "An old release/callback must not stop or disconnect a replacement radio")
        second.writeError = .posix(.EPIPE)
        rig.capturePTTRelease()(); pump()
        precondition(TransmitNotices.shared.notices.contains { $0.text.contains("T 0 write failed") })
        rig.lastError = "poll overwritten"
        precondition(TransmitNotices.shared.notices.contains { $0.text.contains("Receive is unconfirmed") })
        rig.setPTT(true)
        second.stateUpdateHandler?(.failed(.posix(.ECONNRESET))); pump()
        precondition(TransmitNotices.shared.notices.contains { $0.text.contains("connection failed during TX") })
        second.writeError = nil
        _ = TransmitShutdown.releaseAll()
        precondition(second.sent.contains("T 0\n") && !rig.isPTT)
        rig.disconnect()
        let radio = Lab599TX500Driver.shared
        radio.isConnected = true
        rig.driverType = .tx500; rig.isConnected = true
        rig.setPTT(true)
        let serialRelease = rig.capturePTTRelease()
        rig.driverType = .disabled
        _ = SerialLog.drain()
        serialRelease()
        precondition(!radio.isTransmitting && SerialLog.drain().contains { $0.text == "RX;" })
        radio.isConnected = false
        print("PASS actual Radio Control: release-before-disconnect, captured destinations, stale callbacks, global shutdown and serial route snapshot; no sockets")
    }
}
