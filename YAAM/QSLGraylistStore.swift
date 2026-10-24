import Combine
import Foundation

@MainActor
final class QSLGraylistStore: ObservableObject {
    @Published private(set) var index = QSLGraylistIndex.empty
    @Published private(set) var isLoading = false
    @Published private(set) var waitingDays = 90
    @Published private(set) var reducesPriority = false
    @Published private(set) var exceptions = Set<String>()
    @Published private(set) var now = Date()
    @Published private(set) var hasWorkspace = false

    private(set) var profileID: UUID?
    private let defaults: UserDefaults
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private var scheduledRecords: [QSORecordModel]?
    private let worker = LatestSnapshotWorker<UInt64, Input, QSLGraylistIndex>()
    private var clock: AnyCancellable?
    private struct Input: Sendable {
        let records: [QSORecordModel]
        let profileID: UUID?
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect().sink { [weak self] date in
            self?.now = date
            self?.publishPriority()
        }
    }

    func reset(profileID: UUID?) {
        guard self.profileID != profileID || hasWorkspace || scheduledRecords != nil else { return }
        generation &+= 1
        task?.cancel()
        worker.invalidate()
        scheduledRecords = nil
        self.profileID = profileID
        index = .empty
        isLoading = false
        hasWorkspace = false
        waitingDays = min(3650, max(0, defaults.object(forKey: key("waitingDays")) as? Int ?? 90))
        reducesPriority = defaults.bool(forKey: key("reducesPriority"))
        exceptions = Set(defaults.stringArray(forKey: key("exceptions")) ?? [])
        now = Date()
        publishPriority()
    }

    func schedule(records: [QSORecordModel], profileID: UUID?) {
        if self.profileID != profileID { reset(profileID: profileID) }
        // Email enrichment, history stamps and identical sync snapshots do not change
        // graylist evidence. Do not cancel a pending calculation or rebuild the table.
        if let scheduledRecords, Self.sameEvidence(scheduledRecords, records) { return }
        scheduledRecords = records
        generation &+= 1
        let request = generation
        task?.cancel()
        // Keep rows/selection visible while calculating; withdraw penalties immediately.
        // Profile changes still clear everything in reset above.
        isLoading = true
        hasWorkspace = true
        publishPriority()
        let input = Input(records: records, profileID: profileID)
        task = Task { [weak self] in
            guard let self, !Task.isCancelled, generation == request else { return }
            guard let result = await worker.value(for: request, input: input, operation: {
                      QSLGraylistIndex(records: $0.records, profileID: $0.profileID)
                  }), !Task.isCancelled, generation == request, result.key == request else { return }
            if index != result.value { index = result.value }
            isLoading = false
            now = Date()
            publishPriority()
        }
    }

    func setWaitingDays(_ days: Int) {
        waitingDays = min(3650, max(0, days))
        defaults.set(waitingDays, forKey: key("waitingDays"))
        publishPriority()
    }

    func setReducesPriority(_ enabled: Bool) {
        reducesPriority = enabled
        defaults.set(enabled, forKey: key("reducesPriority"))
        publishPriority()
    }

    func setException(_ exempt: Bool, callsign: String) {
        let call = QSLGraylistIndex.clean(callsign)
        if exempt { exceptions.insert(call) } else { exceptions.remove(call) }
        defaults.set(exceptions.sorted(), forKey: key("exceptions"))
        publishPriority()
    }

    func isReduced(_ entry: QSLGraylistEntry) -> Bool {
        !isLoading && reducesPriority && !exceptions.contains(entry.callsign) && entry.isMature(waitingDays: waitingDays, now: now)
    }

    var reducedCallsigns: Set<String> {
        Set(index.entries.filter(isReduced).map(\.callsign))
    }

    private func key(_ suffix: String) -> String {
        "qslGraylist.v1.\(profileID?.uuidString ?? "unscoped").\(suffix)"
    }

    private static func sameEvidence(_ lhs: [QSORecordModel], _ rhs: [QSORecordModel]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let fields = ["APP_YAAM_STATION_PROFILE_ID", "CALL", "COUNTRY", "QSO_DATE",
                      "TIME_ON", "TIME_OFF", "BAND", "FREQ", "MODE", "SUBMODE"]
        return zip(lhs, rhs).allSatisfy { a, b in
            a.id == b.id && fields.allSatisfy { a.fields[$0] == b.fields[$0] } &&
                a.isConfirmed == b.isConfirmed && a.isAnyQSLSent == b.isAnyQSLSent
        }
    }

    private func publishPriority() {
        DigitalCallRosterEngine.shared.updateQSLGraylist(reducedCallsigns)
    }
}
