import AppKit

@MainActor
final class YAAMAppDelegate: NSObject, NSApplicationDelegate {
    private var waitingToQuit = false
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var sleepRelease = ""
    private let sleepNotice = TransmitNotices.Source(name: "Mac sleep")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseBeforeSleep() }
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.sleepRelease.isEmpty else { return }
                TransmitNotices.shared.post(self.sleepNotice, text: self.sleepRelease + " The Mac is awake; receiving and logging remain available. Check physical receive before arming TX again.")
                self.sleepRelease = ""
            }
        }
    }

    func releaseBeforeSleep() {
        let keyer = CWKeyerService.shared
        let cw = keyer.isTransmitting || keyer.isAutoCQActive
        if cw { keyer.stop() }
        let paths = TransmitShutdown.releaseAll(reason: "Mac is going to sleep")
        guard cw || !paths.isEmpty else { return }
        sleepRelease = "YAAM requested transmit release before Mac sleep at \(TXLimits.utc()) (\((cw ? ["CW"] : []) + paths)). Delivery is best effort; receive is unconfirmed."
        TransmitNotices.shared.post(sleepNotice, text: sleepRelease + " Check the radio locally.")
    }

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
