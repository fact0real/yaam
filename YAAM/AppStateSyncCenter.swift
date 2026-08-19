//
//  AppStateSyncCenter.swift
//  YAAM
//

import Foundation

extension AppState {
    func loadSyncCenterState() {
        if let data = UserDefaults.standard.data(forKey: "syncCenterHistory"),
           let decoded = try? JSONDecoder().decode([SyncHistoryEntry].self, from: data) {
            syncHistory = decoded.sorted { $0.completedAt > $1.completedAt }
        }
        refreshSyncServiceConfiguration()
    }

    func refreshSyncServiceConfiguration() {
        let defaults = UserDefaults.standard
        let externalPath = defaults.string(forKey: "externalADIFLogPath") ?? defaults.string(forKey: "sdrControlLogPath") ?? ""
        let sdrPath = defaults.string(forKey: "sdrControlLogbookPath") ?? ""
        let lotwUsername = (defaults.string(forKey: "lotwUsername") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let qrzUsername = (defaults.string(forKey: "qrzUsername") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQRZKeyHint = activeStationProfileID.map {
            CredentialVault.hasStationQRZAPIKeyHint(profileID: $0)
        } ?? false
        let configured: [SyncSource: Bool] = [
            .externalADIF: !externalPath.isEmpty && FileManager.default.fileExists(atPath: externalPath),
            .sdrControl: (!sdrPath.isEmpty && FileManager.default.fileExists(atPath: sdrPath)) || defaults.data(forKey: "sdrControlLogbookBookmark") != nil,
            .lotw: !lotwUsername.isEmpty,
            .qrz: !qrzUsername.isEmpty || hasQRZKeyHint
        ]

        syncServiceStatuses = SyncSource.allCases.map { source in
            var status = syncServiceStatuses.first(where: { $0.source == source }) ?? SyncServiceStatus(source: source)
            status.configured = configured[source] ?? false
            if status.state == .running { return status }

            let entries = syncHistory.filter { $0.source == source }
            if let latest = entries.first {
                status.lastRun = latest.completedAt
                status.detail = latest.detail
                status.changedRecords = latest.changedRecords
                status.state = latest.state
            }
            status.lastSuccess = entries.first(where: { $0.state == .success })?.completedAt ?? legacyLastSuccess(for: source)
            if !status.configured, status.state != .failure {
                status.state = .idle
                status.detail = "Not configured"
            }
            return status
        }
    }

    func beginSyncStatus(_ source: SyncSource, detail: String = "Synchronizing...") {
        syncStartedAt[source] = Date()
        updateSyncStatus(source) { status in
            status.state = .running
            status.lastRun = Date()
            status.detail = detail
            status.changedRecords = 0
        }
    }

    func completeSyncStatus(_ source: SyncSource, result: Result<MergeSummary, Error>, unchangedText: String) {
        switch result {
        case .success(let summary):
            let detail: String
            if summary.changed == 0 {
                detail = unchangedText
            } else if summary.updated > 0 {
                detail = "\(summary.added) added, \(summary.updated) updated"
            } else {
                detail = "\(summary.added) new QSOs, \(summary.skipped) duplicates skipped"
            }
            finishSyncStatus(source, state: .success, detail: detail, changed: summary.changed)
        case .failure(let error):
            finishSyncStatus(source, state: .failure, detail: error.localizedDescription, changed: 0)
        }
    }

    func finishSyncStatus(_ source: SyncSource, state: SyncRunState, detail: String, changed: Int) {
        let completed = Date()
        let started = syncStartedAt.removeValue(forKey: source) ?? completed
        updateSyncStatus(source) { status in
            status.state = state
            status.lastRun = completed
            if state == .success { status.lastSuccess = completed }
            status.detail = detail
            status.changedRecords = changed
        }

        syncHistory.insert(
            SyncHistoryEntry(
                source: source,
                startedAt: started,
                completedAt: completed,
                state: state,
                detail: detail,
                changedRecords: changed
            ),
            at: 0
        )
        if syncHistory.count > 100 { syncHistory = Array(syncHistory.prefix(100)) }
        persistSyncHistory()
    }

    func runSync(_ source: SyncSource) {
        guard !isUnifiedSyncRunning else { return }
        refreshSyncServiceConfiguration()
        guard syncServiceStatuses.first(where: { $0.source == source })?.configured == true else { return }

        switch source {
        case .externalADIF:
            syncExternalADIFLogIfNeeded()
        case .sdrControl:
            syncSDRControlLogbookIfNeeded()
        case .lotw:
            syncConfirmations(sources: [.lotw])
        case .qrz:
            syncConfirmations(sources: [.qrz])
        }
    }

    func runUnifiedSync() {
        guard !isUnifiedSyncRunning, !isLoading, !isSyncingAPI else { return }
        refreshSyncServiceConfiguration()
        isUnifiedSyncRunning = true

        let externalConfigured = syncServiceStatuses.first(where: { $0.source == .externalADIF })?.configured == true
        let sdrConfigured = syncServiceStatuses.first(where: { $0.source == .sdrControl })?.configured == true
        let confirmationSources = Set(syncServiceStatuses.compactMap { status -> SyncSource? in
            guard status.configured, status.source == .lotw || status.source == .qrz else { return nil }
            return status.source
        })

        runUnifiedExternal(
            enabled: externalConfigured,
            sdrEnabled: sdrConfigured,
            confirmationSources: confirmationSources
        )
    }

    func configureUnifiedSyncSchedule() {
        unifiedSyncTimer?.invalidate()
        unifiedSyncTimer = nil
        guard UserDefaults.standard.bool(forKey: "unifiedSyncEnabled") else { return }

        let saved = UserDefaults.standard.double(forKey: "unifiedSyncIntervalMinutes")
        let minutes = saved > 0 ? saved : 30
        let timer = Timer(timeInterval: max(5, minutes) * 60, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.runUnifiedSync() }
        }
        timer.tolerance = min(60, max(5, minutes * 3))
        RunLoop.main.add(timer, forMode: .common)
        unifiedSyncTimer = timer
    }

    private func runUnifiedExternal(
        enabled: Bool,
        sdrEnabled: Bool,
        confirmationSources: Set<SyncSource>
    ) {
        guard enabled else {
            runUnifiedSDR(enabled: sdrEnabled, confirmationSources: confirmationSources)
            return
        }
        syncExternalADIFLogIfNeeded(isAutomatic: true) { [weak self] _ in
            self?.runUnifiedSDR(enabled: sdrEnabled, confirmationSources: confirmationSources)
        }
    }

    private func runUnifiedSDR(enabled: Bool, confirmationSources: Set<SyncSource>) {
        guard enabled else {
            runUnifiedConfirmations(sources: confirmationSources)
            return
        }
        syncSDRControlLogbookIfNeeded(isAutomatic: true) { [weak self] _ in
            self?.runUnifiedConfirmations(sources: confirmationSources)
        }
    }

    private func runUnifiedConfirmations(sources: Set<SyncSource>) {
        guard !sources.isEmpty, !qsoRecords.isEmpty else {
            isUnifiedSyncRunning = false
            return
        }
        syncConfirmations(sources: sources, showCompletionAlert: false) { [weak self] _ in
            self?.isUnifiedSyncRunning = false
            self?.refreshSyncServiceConfiguration()
        }
    }

    private func updateSyncStatus(_ source: SyncSource, mutation: (inout SyncServiceStatus) -> Void) {
        guard let index = syncServiceStatuses.firstIndex(where: { $0.source == source }) else { return }
        mutation(&syncServiceStatuses[index])
    }

    private func persistSyncHistory() {
        if let data = try? JSONEncoder().encode(syncHistory) {
            UserDefaults.standard.set(data, forKey: "syncCenterHistory")
        }
    }

    private func legacyLastSuccess(for source: SyncSource) -> Date? {
        let key: String
        switch source {
        case .externalADIF: key = "externalADIFLastSyncRunDate"
        case .sdrControl: key = "sdrControlLastSyncRunDate"
        case .lotw: key = "lastLoTWSyncDate"
        case .qrz: key = "lastQRZSyncDate"
        }
        return UserDefaults.standard.object(forKey: key) as? Date
    }
}
