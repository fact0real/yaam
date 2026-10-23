import Dispatch
import Foundation
import Network

// Behaviour test of CW STOP through rigctld (Hamlib): RigControlClient.stopMorse() must send rigctld the command that
// stops the radio's keyer, stop_morse, and not "b" alone. rigctld's "b" is send_morse and takes the rest of the line
// as the text, so "b" with no text sends nothing and stops nothing: the radio went on with the whole message.
// It runs the real RigControlClient. Its connection is a stand-in for Network's NWConnection, declared below in this
// module: the client, compiled with this file, uses it instead of Network's, so no socket is opened and the test
// reads, line by line, the exact bytes the client hands to rigctld. The stand-in rigctld answers "RPRT 0" to
// send_morse and an error code, "RPRT -11", to stop_morse, as a radio without stop_morse would.
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/HamlibCWStopRegression.swift YAAM/RigControlClient.swift -o hcws && ./hcws
// Nothing opens a port, a socket or a device, and nothing is keyed. The operator is EA3JIC.

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

/// What reached the stand-in rigctld: each line the client sent, in order.
nonisolated enum Rigctld {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var received: [String] = []
    nonisolated(unsafe) private static var connections: [String] = []

    static func add(lines text: String) {
        lock.lock(); defer { lock.unlock() }
        received += text.components(separatedBy: "\n").dropLast()
    }

    static func opened(_ endpoint: String) {
        lock.lock(); defer { lock.unlock() }
        connections.append(endpoint)
    }

    static func drain() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let lines = received
        received = []
        return lines
    }

    static var endpoints: [String] {
        lock.lock(); defer { lock.unlock() }
        return connections
    }
}

/// Stand-in for Network's NWConnection, with the members RigControlClient uses and Network's signatures. It never
/// opens a socket: start(queue:) reports .ready on the client's queue, as Network does once TCP is up; send() records
/// the bytes; a CW command gets rigctld's "RPRT" answer through the pending receive().
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
    private let lock = NSLock()
    private var pendingReceive: Receive?
    private var queuedReply = ""
    private var queue: DispatchQueue?

    init(host: NWEndpoint.Host, port: NWEndpoint.Port, using: NWParameters) {
        Rigctld.opened("\(host):\(port.rawValue)")
    }

    func start(queue: DispatchQueue) {
        self.queue = queue
        queue.async { self.stateUpdateHandler?(.ready) }
    }

    func cancel() {}

    func receive(minimumIncompleteLength: Int, maximumLength: Int, completion: @escaping Receive) {
        lock.lock(); pendingReceive = completion; lock.unlock()
        deliver()
    }
    private func deliver() {
        lock.lock()
        let read = pendingReceive, text = queuedReply
        if read != nil && !text.isEmpty { pendingReceive = nil; queuedReply = "" }
        lock.unlock()
        if let read, !text.isEmpty { queue?.async { read(Data(text.utf8), nil, false, nil) } }
    }

    func send(content: Data?, completion: SendCompletion) {
        let text = content.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        Rigctld.add(lines: text)
        if case .contentProcessed(let done) = completion { queue?.async { done(nil) } }
        var reply = ""
        for line in text.components(separatedBy: "\n") {
            if line == "+\\stop_morse" { reply += "stop_morse:\nRPRT -11\n" } else if line.hasPrefix("+b ") { reply += "send_morse: CQ TEST\nRPRT 0\n" }
        }
        guard !reply.isEmpty else { return }
        lock.lock(); queuedReply += reply; lock.unlock()
        deliver()
    }
}

// MARK: - The test

@main
struct HamlibCWStopRegression {
    static let text = "CQ TEST EA3JIC"

    static func main() {
        let rig = RigControlClient.shared
        stopWhileOfflineSendsNothing(rig)

        rig.connect(host: "127.0.0.1", port: 4532)
        let deadline = Date().addingTimeInterval(2)
        while !rig.state.isConnected && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        check("the client connects through the stand-in, so no socket is opened",
              rig.state.isConnected && Rigctld.endpoints == ["127.0.0.1:4532"],
              "state \(rig.state.title), connections \(Rigctld.endpoints)")
        _ = Rigctld.drain()

        stopAfterAMessage(rig)

        if failures > 0 {
            print("Hamlib CW stop regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Hamlib CW stop regression passed")
    }

    /// The lines that concern CW: send_morse ("b …" or "b") and stop_morse. The client's 1 s polls (+f, +m) are left out.
    static func cwLines(_ lines: [String]) -> [String] {
        lines.filter { $0 == "b" || $0.hasPrefix("+b ") || $0.contains("morse") }
    }

    static func stopWhileOfflineSendsNothing(_ rig: RigControlClient) {
        rig.stopMorse()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        check("STOP with no rigctld connected sends nothing (unchanged)", Rigctld.drain().isEmpty && Rigctld.endpoints.isEmpty)
    }

    static func stopAfterAMessage(_ rig: RigControlClient) {
        rig.sendMorse(text)
        rig.stopMorse()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let cw = cwLines(Rigctld.drain())

        check("the message goes out as one send_morse line (unchanged)", cw.first == "+b \(text)", "\(cw)")
        check("STOP sends stop_morse after the message",
              cw.count == 2 && cw.last == "+\\stop_morse", "\(cw)")
        check("STOP sends no send_morse without a text (it stops nothing)", !cw.contains("b"), "\(cw)")
        check("an error answer to stop_morse leaves the connection up", rig.state.isConnected, rig.state.title)
        check("a refused stop posts a persistent transmit warning", TransmitNotices.shared.notices.contains { $0.text.contains("stop_morse") && $0.text.contains("RPRT -11") })
    }
}
