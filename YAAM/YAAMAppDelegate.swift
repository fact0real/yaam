import AppKit

@MainActor
final class YAAMAppDelegate: NSObject, NSApplicationDelegate {
    private var waitingToQuit = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !waitingToQuit else { return .terminateLater }
        TransmitShutdown.beginShutdown()
        let keyer = CWKeyerService.shared
        let cwActive = keyer.isTransmitting || keyer.isAutoCQActive
        if cwActive { keyer.beginTermination() }
        // Every other path that can key a radio (TransmitShutdown) is released now, not only CW.
        let released = TransmitShutdown.releaseAll()
        guard cwActive || !released.isEmpty else { return .terminateNow }
        if !released.isEmpty {
            NSLog("YAAM is quitting: released transmit on %@", released.joined(separator: ", "))
        }
        waitingToQuit = true
        Task { [weak self] in
            if cwActive { await keyer.prepareForTermination() }
            // TCI, flrig and rigctld send their release over the network or a queue: leave them time to go out. Best
            // effort: the task below quits after 2 s in any case (transport completion does not confirm physical RX).
            if !released.isEmpty { try? await Task.sleep(for: .seconds(2)) }
            self?.finishTermination(sender)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.finishTermination(sender)
        }
        return .terminateLater
    }

    private func finishTermination(_ application: NSApplication) {
        guard waitingToQuit else { return }
        waitingToQuit = false
        application.reply(toApplicationShouldTerminate: true)
    }
}
