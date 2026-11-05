import AppKit
import Combine
import Sparkle

/// One updater for the process, using Sparkle's signed feed, verifier and sandbox installer.
@MainActor
final class YAAMUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = YAAMUpdater()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var automaticallyDownloads = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var status = "Updates are checked against the signed YAAM release feed."

    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    private var observations = Set<AnyCancellable>()
    private var started = false
    private var relaunchTask: Task<Void, Never>?

    private override init() { super.init() }

    func start() {
        guard !started else { return }
        do {
            try controller.updater.start()
            started = true
            controller.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: DispatchQueue.main).sink { [weak self] in self?.canCheckForUpdates = $0 }.store(in: &observations)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates)
                .receive(on: DispatchQueue.main).sink { [weak self] in self?.automaticallyChecks = $0 }.store(in: &observations)
            controller.updater.publisher(for: \.automaticallyDownloadsUpdates)
                .receive(on: DispatchQueue.main).sink { [weak self] in self?.automaticallyDownloads = $0 }.store(in: &observations)
            controller.updater.publisher(for: \.lastUpdateCheckDate)
                .receive(on: DispatchQueue.main).sink { [weak self] in self?.lastCheck = $0 }.store(in: &observations)
        } catch {
            status = "The updater could not start. Use the YAAM website to download a release, or try again."
        }
    }

    func checkForUpdates() {
        start()
        guard started else {
            let alert = NSAlert()
            alert.messageText = "Software Update Unavailable"
            alert.informativeText = status
            alert.runModal()
            return
        }
        guard controller.updater.canCheckForUpdates else { return }
        status = "Checking the signed YAAM release feed…"
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        start()
        guard started else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
        if !enabled { controller.updater.automaticallyDownloadsUpdates = false }
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        start()
        guard started else { return }
        controller.updater.automaticallyDownloadsUpdates = enabled
    }

    // Do not allow a UserDefaults feed override to redirect this product to a different channel/host.
    func feedURLString(for updater: SPUUpdater) -> String? { YAAMUpdatePolicy.feedURL.absoluteString }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        do {
            try YAAMUpdatePolicy.validate(archiveURL: item.fileURL, version: item.displayVersionString,
                build: item.versionString, installedBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                bytes: item.contentLength)
        } catch let rejection as YAAMUpdatePolicy.Rejection {
            throw NSError(domain: "ASIS.YAAM.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: rejection.rawValue])
        }
    }

    private var stationIsIdle: Bool {
        let keyer = CWKeyerService.shared
        return YAAMUpdatePolicy.mayRelaunch(transmitters: TransmitShutdown.transmitting,
            cwActive: keyer.isTransmitting || keyer.isAutoCQActive)
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard !stationIsIdle else { return false }
        status = "Update verified. Waiting for transmit and Auto-CQ to stop before restarting."
        relaunchTask?.cancel()
        relaunchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.stationIsIdle {
                    self.status = "The station is idle. Restarting to finish the update…"
                    installHandler()
                    return
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        // Preserve the regular quit path; it already drains CAT/PTT release and CW termination.
        TransmitShutdown.beginShutdown()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = "YAAM \(item.displayVersionString) (build \(item.versionString)) is available."
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        relaunchTask?.cancel()
        relaunchTask = nil
        if let error = error as NSError? {
            if error.domain == SUSparkleErrorDomain && error.code == SUError.noUpdateError.rawValue {
                status = "You have the latest compatible YAAM release."
            } else {
                status = "The update did not finish. Your installed app remains in place. Try again or download from the YAAM website."
            }
        }
    }
}
