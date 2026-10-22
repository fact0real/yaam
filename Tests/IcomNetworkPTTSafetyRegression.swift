import Foundation

/// The runner appends a same-file fixture extension; transport sockets are asserted nil throughout this test.
@main
struct IcomNetworkPTTSafetyRegression {
    static func wait(_ seconds: Double, until condition: () -> Bool = { false }) {
        let end = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < end, !condition() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
    static func main() {
        let a = IcomNetworkRadio(), b = IcomNetworkRadio()
        a.setPTT(true, maximumDuration: 1)
        precondition(!a.isTransmitting, "Disconnected and unarmed must refuse")
        a.primeSafetyFixture(); b.primeSafetyFixture()
        a.setPTT(true, maximumDuration: 1)
        precondition(a.isTransmitting)
        wait(0.6)
        a.setPTT(true, maximumDuration: .infinity)
        wait(0.65, until: { !a.isTransmitting })
        precondition(!a.isTransmitting && !a.transmitArmed, "Repeat key-down must not renew the deadline")
        precondition(TransmitNotices.shared.notices.count == 1)
        b.setPTT(true, maximumDuration: 1)
        wait(1.3, until: { !b.isTransmitting })
        precondition(!b.isTransmitting && TransmitNotices.shared.notices.count == 2)
        let ids = TransmitNotices.shared.notices.map(\.id)
        a.primeSafetyFixture()
        a.setPTT(true, maximumDuration: 5)
        precondition(TransmitNotices.shared.notices.map(\.id) == ids, "Rekey must retain unacknowledged warnings")
        TransmitShutdown.beginShutdown()
        _ = TransmitShutdown.releaseAll()
        precondition(!a.isTransmitting && !b.isTransmitting)
        a.setPTT(true)
        precondition(!a.isTransmitting)
        a.assertNoSafetyFixtureSockets(); b.assertNoSafetyFixtureSockets()
        print("PASS Icom LAN actual PTT code: disconnect/arming refusal, nonrenewable timer, disarm, per-instance notices, shutdown; no sockets")
    }
}

extension AmateurBandPlan {
    nonisolated static func formattedMHz(_ frequency: Double) -> String { String(format: "%.6f", frequency) }
}
