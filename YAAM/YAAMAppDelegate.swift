import AppKit

@MainActor
final class YAAMAppDelegate: NSObject, NSApplicationDelegate {
    private var waitingForCWStop = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let keyer = CWKeyerService.shared
        guard keyer.isTransmitting || keyer.isAutoCQActive else { return .terminateNow }
        guard !waitingForCWStop else { return .terminateLater }
        waitingForCWStop = true
        Task { [weak self] in
            await keyer.prepareForTermination()
            self?.finishTermination(sender)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.finishTermination(sender)
        }
        return .terminateLater
    }

    private func finishTermination(_ application: NSApplication) {
        guard waitingForCWStop else { return }
        waitingForCWStop = false
        application.reply(toApplicationShouldTerminate: true)
    }
}
