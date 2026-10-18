import Foundation
import Combine

/// Controls only the public orbit/space-weather/image feeds, not account services or MapKit.
@MainActor
final class PublicDataFeedPolicy: ObservableObject {
    static let shared = PublicDataFeedPolicy()
    static let defaultsKey = "allowPublicDataFeeds"
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.defaultsKey)
            changes.send(isEnabled)
        }
    }
    let changes = PassthroughSubject<Bool, Never>()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.defaultsKey) as? Bool ?? true
    }
}

/// Multiple visible windows may share an engine. Only the last consumer stops its refresh timer.
@MainActor
final class PublicDataFeedActivity {
    private let policy: PublicDataFeedPolicy
    private let interval: TimeInterval
    private let refresh: () -> Void
    private let cancel: () -> Void
    private var consumers = Set<UUID>()
    private var timer: AnyCancellable?
    private var policySubscription: AnyCancellable?
    private(set) var isActive = false

    init(interval: TimeInterval, policy: PublicDataFeedPolicy? = nil,
         refresh: @escaping () -> Void, cancel: @escaping () -> Void = {}) {
        self.interval = interval
        let policy = policy ?? .shared
        self.policy = policy
        self.refresh = refresh
        self.cancel = cancel
        policySubscription = policy.changes.sink { [weak self] enabled in
            self?.update(enabled: enabled)
        }
    }

    func setConsumer(_ id: UUID, active: Bool) {
        if active { consumers.insert(id) } else { consumers.remove(id) }
        update(enabled: policy.isEnabled)
    }

    private func update(enabled: Bool) {
        let shouldRun = enabled && !consumers.isEmpty
        guard shouldRun != isActive else { return }
        isActive = shouldRun
        if shouldRun {
            refresh()
            timer = Timer.publish(every: interval, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in self?.refresh() }
        } else {
            timer = nil
            cancel()
        }
    }
}
