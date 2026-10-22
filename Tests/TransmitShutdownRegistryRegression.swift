import Foundation

private final class Owner { var transmitting = true }
private final class Payload {}
@main
struct TransmitShutdownRegistryRegression {
    static func main() {
        var log: [String] = []
        let transport = Owner(), producer = Owner()
        TransmitShutdown.register("transport", isTransmitting: { transport.transmitting }, owner: transport, release: {
            log.append("transport"); transport.transmitting = false
        })
        TransmitShutdown.register("audio", isTransmitting: { producer.transmitting }, producer: true, owner: producer, release: {
            log.append("audio"); producer.transmitting = false
        })
        _ = TransmitShutdown.releaseAll()
        precondition(log == ["audio", "transport"], "Quiesce audio/VOX before releasing a transport")
        precondition(TransmitShutdown.releaseAll().isEmpty)
        weak var captured: Payload?
        do {
            let owner = Owner(), payload = Payload()
            captured = payload
            TransmitShutdown.register("temporary", isTransmitting: { [weak owner] in owner?.transmitting ?? false }, owner: owner,
                                      release: { _ = payload })
        }
        precondition(captured != nil)
        TransmitShutdown.register("idle", isTransmitting: { false }, release: {})
        precondition(captured == nil, "A dead Multi-Rig owner must not retain its registry entry")
        TransmitShutdown.beginShutdown()
        precondition(TransmitShutdown.isShuttingDown)
        print("PASS shutdown producer ordering, idempotence, dead owner cleanup and latch")
    }
}
