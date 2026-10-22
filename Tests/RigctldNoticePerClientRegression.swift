import Dispatch
import Foundation
import Network

// Behaviour test (Y-001, B-018): each rigctld client keeps its own PTT safety notice in TransmitNotices. Multi-Rig
// makes one RigControlClient per slot besides RigControlClient.shared, so a notice keyed by the name "rigctld" alone
// let the second safety timer replace the first radio's notice, and one radio keyed again cleared the other's.
// It runs two real RigControlClients. Their connection is a stand-in for Network's NWConnection, declared below in
// this module (as in Tests/HamlibCWStopRegression.swift): no socket is opened and nothing is keyed.
// Build and run from the repository root (Tests/run-cw-safety-regressions.sh does it):
//   swiftc <the app's flags> -module-name YAAM Tests/RigctldNoticePerClientRegression.swift YAAM/RigControlClient.swift \
//       YAAM/TXLimits.swift YAAM/MorseTiming.swift YAAM/TransmitNotices.swift -o rnpc && ./rnpc
// The operator is EA3JIC.

private var failures = 0

private func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok {
        print("PASS \(name)")
    } else {
        let more = detail()
        print("FAIL \(name)\(more.isEmpty ? "" : "   [\(more)]")")
        failures += 1
    }
}

// MARK: - Stand-ins

/// The band plan as YAAM/OperatorModels.swift has it, only the two members RigSnapshot uses.
nonisolated enum AmateurBandPlan {
    static func formattedMHz(_ frequency: Double) -> String { String(format: "%.6f", frequency) }
    static func band(forMHz frequency: Double) -> String? { (7.0..<7.3).contains(frequency) ? "40m" : nil }
}

/// Stand-in for Network's NWConnection, with the members RigControlClient uses and Network's signatures. It never
/// opens a socket: start(queue:) reports .ready on the client's queue, and send() drops the bytes.
nonisolated final class NWConnection: @unchecked Sendable {
    enum State: Equatable, Sendable {
        case setup
        case waiting(NWError)
        case preparing
        case ready
        case failed(NWError)
        case cancelled
    }

    enum SendCompletion {
        case contentProcessed(@Sendable (_ error: NWError?) -> Void)
        case idempotent
    }

    final class ContentContext: Sendable {}

    typealias Receive = @Sendable (Data?, ContentContext?, Bool, NWError?) -> Void

    var stateUpdateHandler: (@Sendable (_ state: State) -> Void)?
    private var queue: DispatchQueue?

    init(host: NWEndpoint.Host, port: NWEndpoint.Port, using: NWParameters) {}

    func start(queue: DispatchQueue) {
        self.queue = queue
        queue.async { self.stateUpdateHandler?(.ready) }
    }

    func cancel() {}

    func receive(minimumIncompleteLength: Int, maximumLength: Int, completion: @escaping Receive) {}

    func send(content: Data?, completion: SendCompletion) {
        if case .contentProcessed(let done) = completion { queue?.async { done(nil) } }
    }
}

// MARK: - The test

private func runUntil(_ seconds: Double, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return condition()
}

@main
struct RigctldNoticePerClientRegression {
    static func main() {
        let a = RigControlClient(), b = RigControlClient()     // two Multi-Rig slots
        a.connect(host: "127.0.0.1", port: 4532)
        b.connect(host: "127.0.0.1", port: 4533)
        check("both clients connect through the stand-in", runUntil(2) { a.state.isConnected && b.state.isConnected })

        let notices = TransmitNotices.shared
        let rigctld: () -> [TransmitNotices.Notice] = { notices.notices.filter { $0.source.name.hasPrefix("rigctld") } }
        a.setPTT(true, maximumDuration: 1)                  // one after the other, so A's notice is the first
        check("slot A's safety timer releases PTT", runUntil(3) { !a.isTransmitting && rigctld().count == 1 })
        b.setPTT(true, maximumDuration: 1)
        check("slot B's safety timer releases PTT", runUntil(3) { !b.isTransmitting && rigctld().count == 2 })
        check("each client keeps its own notice: the second does not replace the first", rigctld().count == 2,
              "\(rigctld().count) notice(s)")

        let before = rigctld().map(\.id)
        b.setPTT(true, maximumDuration: 16)                 // slot B keyed again
        _ = runUntil(0.3) { false }
        let after = rigctld()
        check("re-keying either client leaves both unacknowledged notices",
              after.map(\.id) == before, "\(after.count) notice(s)")
        b.setPTT(false)
        _ = runUntil(0.3) { false }

        if failures > 0 {
            print("Rigctld notice per client regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Rigctld notice per client regression passed")
    }
}
