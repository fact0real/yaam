//
//  AppStateQSLHub.swift
//  YAAM
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension AppState {
    func loadQSLHubState() {
        let daemon = ZeroClickCloudUploadDaemon.shared
        daemon.onServiceAccepted = { [weak self] record, services in
            self?.markZeroClickUploads(record, services: services)
        }
        daemon.isAlreadyAtService = { [weak self] record, service in
            self?.isZeroClickQSOAlreadyAtService(record, service: service) ?? false
        }
        addStandardClubLogStatus()
        guard let profileID = activeStationProfileID, let database = logbookDatabase else {
            qslQueueJobs = []
            awardClaims = []
            awardProgress = []
            return
        }
        do {
            qslQueueJobs = try database.loadQSLJobs(profileID: profileID)
            var recovered: [QSLQueueJob] = []
            for index in qslQueueJobs.indices where qslQueueJobs[index].state == .uploading {
                qslQueueJobs[index].state = .retry
                qslQueueJobs[index].nextAttemptAt = Date()
                qslQueueJobs[index].message = "Recovered after an interrupted upload"
                qslQueueJobs[index].updatedAt = Date()
                recovered.append(qslQueueJobs[index])
            }
            try database.saveQSLJobs(recovered)
            restoreLostQSLMarks()
            awardClaims = try database.loadAwardClaims(profileID: profileID)
            refreshAwardProgress()
            qslHubStatus = qslQueueJobs.contains(where: { $0.state.isPending })
                ? "\(qslQueueJobs.filter { $0.state.isPending }.count) queued upload(s)"
                : "QSL queue is up to date"
        } catch {
            qslHubStatus = error.localizedDescription
            appendLog("QSL Hub state failed to load: \(error.localizedDescription)")
        }
    }

    func refreshAwardProgress() {
        awardProgress = AwardEngine.evaluate(records: qsoRecords, claims: awardClaims)
        portableActivitySummaries = PortableActivityEngine.summaries(records: qsoRecords)
        let knownTargets = awardProgress.filter { $0.target != nil }
        let ready = knownTargets.filter(\.earnedLocally).count
        awardEngineStatus = "\(ready) locally complete · \(knownTargets.count) tracked milestones"
        updateMobileCompanionSnapshot()
    }

    func saveAwardStage(awardID: String, stage: AwardLifecycleStage, note: String = "") {
        guard let profileID = activeStationProfileID, let database = logbookDatabase else { return }
        let previous = awardClaims.first { $0.awardID == awardID }
        let now = Date()
        var claim = AwardClaim(
            stationProfileID: profileID,
            awardID: awardID,
            stage: stage,
            submittedAt: previous?.submittedAt,
            grantedAt: previous?.grantedAt,
            note: note.isEmpty ? (previous?.note ?? "") : note,
            updatedAt: now
        )
        if stage == .submitted, claim.submittedAt == nil { claim.submittedAt = now }
        if stage == .granted, claim.grantedAt == nil { claim.grantedAt = now }
        if stage.rank < AwardLifecycleStage.submitted.rank { claim.submittedAt = nil }
        if stage.rank < AwardLifecycleStage.granted.rank { claim.grantedAt = nil }
        do {
            try database.saveAwardClaim(claim)
            if let index = awardClaims.firstIndex(where: { $0.awardID == awardID }) {
                awardClaims[index] = claim
            } else {
                awardClaims.append(claim)
            }
            refreshAwardProgress()
            playActivitySound(.success)
        } catch {
            awardEngineStatus = error.localizedDescription
            playActivitySound(.failure)
        }
    }

    /// Queues the QSOs that are not at each service yet (QSLSyncAll.plannedUploads). `retryStopped` lets a click on a
    /// QSO's own Upload button queue again a stopped job (blocked, or failed five times); Sync All and Sync Selected
    /// do not, except for the blocked jobs in `unblockedKeys`, whose service's credentials changed since.
    func enqueueQSL(
        records: [QSORecordModel],
        providers: Set<QSLProvider>,
        retryStopped: Bool = true,
        unblockedKeys: Set<String> = []
    ) {
        guard let profileID = activeStationProfileID, let database = logbookDatabase else {
            qslHubStatus = "Choose an active station first"
            return
        }
        guard !records.isEmpty, !providers.isEmpty else {
            qslHubStatus = "Select at least one QSO and one service"
            return
        }

        guard isOwnStationLogOpen else {
            qslHubStatus = "Nothing queued: " + (qslOwnLogProblem ?? "open the station’s own log")
            return
        }
        let eligible = records.filter { UploadStationPolicy.matches($0.fields, stationCallsign: currentStationCallsign) }
        let skipped = records.count - eligible.count
        var added = 0
        var changedJobs: [QSLQueueJob] = []
        var existingByKey: [String: QSLQueueJob] = [:]
        for job in qslQueueJobs { existingByKey[QSLSyncAll.jobKey(job.qsoID, job.provider)] = job }
        var jobStates = existingByKey.mapValues(\.state)
        for key in unblockedKeys where jobStates[key] == .blocked { jobStates[key] = .retry }
        let plan = QSLSyncAll.plannedUploads(
            records: eligible.map { (id: $0.id, fields: $0.fields) },
            providers: providers,
            jobStates: jobStates,
            retryStopped: retryStopped
        )
        let fieldsByID = Dictionary(records.map { ($0.id, $0.fields) }, uniquingKeysWith: { first, _ in first })
        for provider in QSLProvider.allCases {
            for qsoID in plan[provider] ?? [] {
                guard let fields = fieldsByID[qsoID] else { continue }
                let key = QSLSyncAll.jobKey(qsoID, provider)
                let adif = QSLUploadStatus.uploadADIF(fields, for: provider)
                var job = existingByKey[key] ?? QSLQueueJob(
                    stationProfileID: profileID,
                    qsoID: qsoID,
                    provider: provider,
                    adif: adif
                )
                job.adif = adif
                job.state = .queued
                job.nextAttemptAt = nil
                job.message = "Waiting"
                job.updatedAt = Date()
                changedJobs.append(job)
                existingByKey[key] = job
                added += 1
            }
        }
        do {
            try database.saveQSLJobs(changedJobs)
            qslQueueJobs = try database.loadQSLJobs(profileID: profileID)
        } catch {
            qslHubStatus = "Could not queue uploads: \(error.localizedDescription)"
            appendLog(qslHubStatus)
            playActivitySound(.failure)
            return
        }
        qslHubStatus = added == 0 ? "All selected QSOs were already sent or queued" : "Queued \(added) upload(s)"
        if skipped > 0 { qslHubStatus += "; \(skipped) other-station QSO(s) skipped" }
        if added > 0 { playActivitySound(.notice) }
    }

    func enqueueAutomaticQSL(for record: QSORecordModel) {
        guard UserDefaults.standard.bool(forKey: "qslAutoQueueQuickLog") else { return }
        let raw = UserDefaults.standard.string(forKey: "qslAutomaticProviders") ?? ""
        let providers = Set(raw.split(separator: ",").compactMap { QSLProvider(rawValue: String($0)) })
        guard !providers.isEmpty else { return }
        enqueueQSL(records: [record], providers: providers)
        Task { @MainActor in await self.processQSLQueue() }
    }

    /// R16: why the upload part of a Sync cannot work on the open log, or nil when the station's own log is open.
    var qslOwnLogProblem: String? {
        if QSLSyncAll.isOwnLog(isMasterMode: isMasterMode, loadedProfileID: loadedWorkspaceProfileID, activeProfileID: activeStationProfileID) {
            return nil
        }
        return isMasterMode ? "the station's log is not loaded from its database" : "a Guest Log is open; open the master log"
    }

    var isOwnStationLogOpen: Bool { qslOwnLogProblem == nil }

    /// The services whose upload credentials are set, with TQSL looked up for LoTW (QSLSyncAll.configuredProviders).
    func qslConfiguredProvidersForSync() -> Set<QSLProvider> {
        let credentials = qslServiceCredentials(for: Set(QSLProvider.allCases))
        var tqslFound = false
        if let resolved = TQSLCoordinator.resolveBinaryPath(
            customPath: credentials.tqslExecutablePath,
            securityBookmark: credentials.tqslBookmarkData
        ) {
            resolved.scopedURL?.stopAccessingSecurityScopedResource()
            tqslFound = true
        }
        return QSLSyncAll.configuredProviders(credentials, tqslFound: tqslFound)
    }

    /// When each service's secret credentials were last saved (CredentialVault.changedAt), so that Sync queues again
    /// the jobs they blocked. LoTW jobs are never blocked: a TQSL failure is not a credential rejection.
    func qslCredentialsChangedAt() -> [QSLProvider: Date] {
        var dates: [QSLProvider: Date] = [:]
        let qrz = [CredentialVault.changedAt(.qrzAPIKey),
                   activeStationProfileID.flatMap { CredentialVault.stationQRZAPIKeyChangedAt(profileID: $0) }]
        if let latest = qrz.compactMap({ $0 }).max() { dates[.qrz] = latest }
        if let date = CredentialVault.changedAt(.eqslPassword) { dates[.eqsl] = date }
        let clubLog = [CredentialVault.changedAt(.clubLogPassword), CredentialVault.changedAt(.clubLogAPIKey)]
        if let latest = clubLog.compactMap({ $0 }).max() { dates[.clubLog] = latest }
        return dates
    }

    /// The upload part of Sync All (every QSO) and of Sync Selected (`selectedIDs`), on the station's own log only.
    /// The services are those switched on in the Station Workspace with their upload credentials set; for each, the
    /// QSOs not at the service yet go to the queue, and the queue sends them, those services and QSOs only. The
    /// summaries also count the QSOs already there and the jobs left stopped by an earlier run. One upload at a time:
    /// when the queue is already busy, nothing is done and the result says so.
    @MainActor
    func uploadNeverSentQSOs(selectedIDs: Set<UUID>? = nil) async -> QSLSyncUploadRun {
        guard !isProcessingQSLQueue else { return QSLSyncUploadRun(busy: true) }
        var run = QSLSyncUploadRun()
        if let problem = qslOwnLogProblem {
            for provider in QSLProvider.allCases { run.notChecked[provider] = problem }
            return run
        }
        if addStandardClubLogStatus() > 0 { autoSaveActiveWorkspace() }
        let vaultLocked = !CredentialVault.isVaultSessionUnlocked
        let configured = qslConfiguredProvidersForSync()
        let switchedOn = QSLSyncAll.switchedOn(stored: UserDefaults.standard.string(forKey: "stationWorkspace.enabledProviders"))
        for provider in QSLProvider.allCases {
            if let reason = QSLSyncAll.notChecked(provider, configured: configured, switchedOn: switchedOn, vaultLocked: vaultLocked) {
                run.notChecked[provider] = reason
            }
        }
        let providers = vaultLocked ? Set<QSLProvider>() : configured.intersection(switchedOn)
        let selectedFields = QSLSyncAll.recordsToSync(all: qsoRecords.map { (id: $0.id, fields: $0.fields) }, selectedIDs: selectedIDs)
        let chosenFields = QSLSyncAll.recordsToSync(all: selectedFields, selectedIDs: nil, stationCallsign: currentStationCallsign)
        run.skippedStationCount = selectedFields.count - chosenFields.count
        guard !providers.isEmpty, !chosenFields.isEmpty else { return run }
        let chosenIDs = Set(chosenFields.map(\.id))
        let fieldsByID = Dictionary(chosenFields.map { ($0.id, $0.fields) }, uniquingKeysWith: { first, _ in first })
        let alreadyThere = QSLSyncAll.alreadyThereCounts(records: chosenFields, providers: providers)
        let unblocked = QSLSyncAll.unblockedJobKeys(qslQueueJobs, credentialsChangedAt: qslCredentialsChangedAt())
        let leftover = QSLSyncAll.leftoverStopped(jobs: qslQueueJobs, fieldsByID: fieldsByID, providers: providers, unblocked: unblocked)
        enqueueQSL(records: qsoRecords.filter { chosenIDs.contains($0.id) }, providers: providers, retryStopped: false, unblockedKeys: unblocked)
        let summaries = await processQSLQueue(providers: providers, qsoIDs: selectedIDs == nil ? nil : chosenIDs, countAlreadyThere: false)
        run.summaries = QSLSyncReport.withPriorState(summaries, providers: providers, alreadyThere: alreadyThere, leftover: leftover)
        return run
    }

    /// Sync Selected, from the log table's selection menu: the upload part of Sync All for the selected QSOs only,
    /// with the same rule and services. Nothing is downloaded. When another sync or upload is running (the Zero-Click
    /// daemon's included), or a log is loading, nothing is done and the QSL Hub status says so.
    @MainActor
    func syncSelectedQSOs() async {
        let engine = QSLSyncEngine.shared
        let daemon = ZeroClickCloudUploadDaemon.shared
        guard !engine.isSyncing, !isUnifiedSyncRunning, !isSyncingAPI, !isProcessingQSLQueue, !isLoading,
              !daemon.isUploading, !daemon.isFlushingQueue else {
            qslHubStatus = "Another sync or upload is running; Sync Selected did nothing"
            engine.appendLog(level: .warning, service: "Sync Selected", message: "⚠️ \(qslHubStatus)")
            playActivitySound(.notice)
            return
        }
        if let problem = qslOwnLogProblem {
            qslHubStatus = "Sync Selected did nothing: \(problem)"
            engine.appendLog(level: .warning, service: "Sync Selected", message: "⚠️ \(qslHubStatus)")
            playActivitySound(.notice)
            return
        }
        let selectedIDs = selectedRecordIDs
        guard !selectedIDs.isEmpty else { return }
        let run = await uploadNeverSentQSOs(selectedIDs: selectedIDs)
        for line in QSLSyncReport.lines(run) {
            engine.appendLog(level: line.problem ? .warning : .info, service: "Sync Selected", message: line.text)
        }
        qslHubStatus = "Sync Selected (\(selectedIDs.count)): " + QSLSyncReport.status(run)
        appendLog(qslHubStatus)
    }

    /// Sends the due jobs, all of them or only those of some services and QSOs. At the start of the run each job is
    /// looked at again with its QSO as it is then (QSLSyncAll.review); each service runs as one QSLProviderPass, with
    /// the jobs that never failed first (QSLSyncAll.passOrder), and stops after two failures in a row or one clear
    /// credential rejection. Returns one summary per service, for the report.
    @MainActor
    @discardableResult
    func processQSLQueue(
        providers: Set<QSLProvider>? = nil,
        qsoIDs: Set<UUID>? = nil,
        countAlreadyThere: Bool = true
    ) async -> [QSLPassSummary] {
        guard !isProcessingQSLQueue, let database = logbookDatabase else { return [] }
        // R16: with a Guest Log open, the station's jobs are not for these QSOs: nothing is sent and nothing dropped.
        if let problem = qslOwnLogProblem {
            qslHubStatus = "Nothing uploaded: \(problem)"
            return []
        }
        let uploadProfileID = activeStationProfileID
        let uploadStationCallsign = currentStationCallsign
        let eligibleIDs = Set(qsoRecords.filter {
            UploadStationPolicy.matches($0.fields, stationCallsign: uploadStationCallsign)
        }.map(\.id))
        let existingIDs = Set(qsoRecords.map(\.id))
        let due = QSLSyncAll.dueJobs(qslQueueJobs, now: Date(), providers: providers, qsoIDs: qsoIDs).filter {
            $0.stationProfileID == uploadProfileID && (!existingIDs.contains($0.qsoID) || eligibleIDs.contains($0.qsoID))
        }
        guard !due.isEmpty else {
            qslHubStatus = "No uploads are due"
            return []
        }

        isProcessingQSLQueue = true
        let now = Date()
        let fieldsByID = Dictionary(qsoRecords.map { ($0.id, $0.fields) }, uniquingKeysWith: { first, _ in first })
        var gone: [QSLQueueJob] = []
        var alreadyThere: [QSLQueueJob] = []
        var toSend: [QSLQueueJob] = []
        for original in due {
            var job = original
            job.updatedAt = now
            switch QSLSyncAll.review(job, currentFields: fieldsByID[job.qsoID]) {
            case .qsoGone:
                gone.append(job)
            case .alreadyThere:
                job.state = .succeeded
                job.nextAttemptAt = nil
                job.message = "Already at the service"
                alreadyThere.append(job)
            case .send(let adif):
                job.adif = adif
                job.state = .uploading
                job.message = "Contacting \(job.provider.title)"
                toSend.append(job)
            }
        }
        if !gone.isEmpty {
            try? database.deleteQSLJobs(gone)
            let goneIDs = Set(gone.map(\.id))
            qslQueueJobs.removeAll { goneIDs.contains($0.id) }
        }
        var positions = QSLRunPositions(jobs: qslQueueJobs, records: qsoRecords)
        _ = applyQSLJobUpdates((alreadyThere + toSend).map { QSLJobUpdate(job: $0, markSent: false) }, positions: &positions, database: database)

        qslHubStatus = "Uploading \(toSend.count) item(s)..."
        let credentials = qslServiceCredentials(for: Set(toSend.map(\.provider)))
        var summaries: [QSLPassSummary] = []
        var markedSinceSave = 0
        for provider in QSLProvider.allCases {
            let jobs = QSLSyncAll.passOrder(toSend.filter { $0.provider == provider })
            let already = countAlreadyThere ? alreadyThere.filter { $0.provider == provider }.count : 0
            guard !jobs.isEmpty || already > 0 else { continue }
            var pass = QSLProviderPass(provider: provider, jobs: jobs, alreadyThere: already)
            while let batch = pass.nextBatch() {
                // Recheck after each network suspension. A profile, workspace, QSO or privacy switch can change.
                guard isOwnStationLogOpen, activeStationProfileID == uploadProfileID,
                      currentStationCallsign == uploadStationCallsign else {
                    pass.stopBeforeSending(reason: "the active station or log changed")
                    break
                }
                let currentByID = Dictionary(qsoRecords.map { ($0.id, $0.fields) }, uniquingKeysWith: { first, _ in first })
                guard batch.allSatisfy({ job in
                    currentByID[job.qsoID].map { UploadStationPolicy.matches($0, stationCallsign: uploadStationCallsign) } ?? false
                }) else {
                    pass.stopBeforeSending(reason: "a QSO was removed or its station callsign changed")
                    break
                }
                let adif = batch.compactMap { job in currentByID[job.qsoID].map { QSLUploadStatus.uploadADIF($0, for: provider) } }
                let result = await qslHubClient.upload(provider: provider, adifRecords: adif, credentials: credentials)
                let updates = pass.record(QSLBatchOutcome(result), for: batch, now: Date())
                markedSinceSave += applyQSLJobUpdates(updates, positions: &positions, database: database)
                // Long runs (QRZ takes one QSO per request) save the marks as they go, into the station's own log only.
                if markedSinceSave >= 200 {
                    if isOwnStationLogOpen { autoSaveActiveWorkspace() }
                    markedSinceSave = 0
                }
            }
            _ = applyQSLJobUpdates(pass.finish(now: Date()), positions: &positions, database: database)
            summaries.append(pass.summary)
        }

        if markedSinceSave > 0, isOwnStationLogOpen { autoSaveActiveWorkspace() }
        isProcessingQSLQueue = false
        qslHubStatus = QSLSyncReport.status(QSLSyncUploadRun(summaries: summaries))
        refreshAwardProgress()
        playActivitySound(summaries.contains(where: \.hasProblems) ? .notice : .success)
        return summaries
    }

    func retryQSLFailures() {
        guard let database = logbookDatabase else { return }
        for index in qslQueueJobs.indices where [.failed, .blocked, .retry].contains(qslQueueJobs[index].state) {
            qslQueueJobs[index].state = .queued
            qslQueueJobs[index].nextAttemptAt = nil
            qslQueueJobs[index].message = "Retry requested"
            qslQueueJobs[index].updatedAt = Date()
            try? database.saveQSLJob(qslQueueJobs[index])
        }
        qslHubStatus = "Failed and blocked items are queued for retry"
    }

    func clearCompletedQSLJobs() {
        guard let profileID = activeStationProfileID, let database = logbookDatabase else { return }
        do {
            try database.deleteQSLJobs(profileID: profileID, states: [.succeeded])
            qslQueueJobs.removeAll { $0.state == .succeeded }
            qslHubStatus = "Completed queue history cleared"
        } catch {
            qslHubStatus = error.localizedDescription
        }
    }

    @MainActor
    func downloadEQSLConfirmations() async {
        guard !isProcessingQSLQueue else { return }
        isProcessingQSLQueue = true
        qslHubStatus = "Downloading eQSL Inbox..."
        do {
            let lastSync = UserDefaults.standard.object(forKey: "eqslLastInboxSync") as? Date
            let incoming = try await qslHubClient.downloadEQSLConfirmations(
                credentials: qslServiceCredentials(for: [.eqsl]),
                since: lastSync
            )
            var updated = 0
            var unmatched = 0
            var claimed = Set<Int>()
            let candidates = qsoRecords.map(\.fields)
            for fields in incoming {
                guard let index = eqslConfirmationMatchIndex(fields, candidates: candidates, claimed: &claimed) else {
                    unmatched += 1
                    continue
                }
                qsoRecords[index].fields = ImportReviewAnalyzer.mergeUpdate(incoming: fields, into: qsoRecords[index].fields)
                qsoRecords[index].fields["EQSL_QSL_RCVD"] = "Y"
                newlyConfirmedRecordIDs.insert(qsoRecords[index].id)
                updated += 1
            }
            if updated > 0 { autoSaveActiveWorkspace() }
            UserDefaults.standard.set(Date(), forKey: "eqslLastInboxSync")
            qslHubStatus = unmatched == 0
                ? "Matched \(updated) eQSL confirmation(s)"
                : "Matched \(updated) eQSL confirmation(s); \(unmatched) not found in the log"
            refreshAwardProgress()
            playActivitySound(.success)
        } catch {
            qslHubStatus = error.localizedDescription
            playActivitySound(.failure)
        }
        isProcessingQSLQueue = false
    }

    func downloadLoTWAndQRZConfirmations() {
        guard !isProcessingQSLQueue, !isSyncingAPI else { return }
        qslHubStatus = "Downloading LoTW and QRZ confirmations..."
        syncConfirmations(sources: [.lotw, .qrz], showCompletionAlert: false) { [weak self] summary in
            guard let self else { return }
            self.qslHubStatus = "LoTW + QRZ: \(summary.changed) updated from \(summary.fetched) checked"
            self.refreshAwardProgress()
        }
    }

    @MainActor
    func downloadClubLogLoTWState() async {
        guard !isProcessingQSLQueue, !isSyncingAPI else { return }
        isProcessingQSLQueue = true
        qslHubStatus = "Downloading Club Log LoTW state..."
        do {
            let earliestDate = qsoRecords
                .map { $0["QSO_DATE"].filter(\.isNumber) }
                .filter { $0.count == 8 }
                .min()
            let incoming = try await qslHubClient.downloadClubLogLoTWState(
                credentials: qslServiceCredentials(for: [.clubLog]),
                earliestQSODate: earliestDate
            )
            var matched = 0
            var updated = 0
            for fields in incoming {
                guard let index = qslConfirmationMatchIndex(fields) else { continue }
                matched += 1
                var changed = false
                for key in ["LOTW_QSL_SENT", "LOTW_QSL_RCVD", "QSL_RCVD", "APP_YAAM_CLUBLOG_LOTW_STATE"] {
                    guard let value = fields[key], !value.isEmpty, qsoRecords[index][key] != value else { continue }
                    qsoRecords[index].fields[key] = value
                    if !tableHeaders.contains(key) { tableHeaders.append(key) }
                    changed = true
                }
                if changed { updated += 1 }
            }
            if updated > 0 { autoSaveActiveWorkspace() }
            UserDefaults.standard.set(Date(), forKey: "clubLogLoTWStateLastSync")
            qslHubStatus = "Club Log LoTW state: \(updated) updated · \(matched) matched"
            refreshAwardProgress()
            playActivitySound(.success)
        } catch {
            qslHubStatus = error.localizedDescription
            playActivitySound(.failure)
        }
        isProcessingQSLQueue = false
    }

    func exportPortableActivity(_ summary: PortableActivitySummary) {
        let records = PortableActivityEngine.records(for: summary, from: qsoRecords)
        guard !records.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "adi")].compactMap { $0 }
        panel.nameFieldStringValue = "\(summary.program.rawValue)-\(summary.reference)-\(summary.date).adi"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let content = generateADIF(originalContent: "", records: records.map(\.fields))
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                self.qslHubStatus = "Exported \(records.count) portable QSO(s)"
                self.playActivitySound(.success)
            } catch {
                self.qslHubStatus = error.localizedDescription
                self.playActivitySound(.failure)
            }
        }
    }

    func qslServiceCredentials(for providers: Set<QSLProvider>) -> QSLServiceCredentials {
        let defaults = UserDefaults.standard
        return QSLServiceCredentials(
            qrzAPIKey: providers.contains(.qrz) ? activeQRZAPIKey : "",
            lotwCallsign: defaults.string(forKey: "lotwUsername") ?? currentStationCallsign,
            lotwPassword: providers.contains(.lotw) ? CredentialVault.value(for: .lotwPassword) : "",
            lotwStationLocation: {
                let profLoc = (activeStationProfile?.lotwStationLocation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !profLoc.isEmpty { return profLoc }
                return (defaults.string(forKey: "lotwStationLocation") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }(),
            lotwCertificatePassword: providers.contains(.lotw) ? CredentialVault.value(for: .lotwCertificatePassword) : "",
            tqslExecutablePath: defaults.string(forKey: "tqslExecutablePath") ?? "",
            tqslBookmarkData: defaults.data(forKey: "tqslExecutableBookmark"),
            eqslUsername: defaults.string(forKey: "eqslUsername") ?? currentStationCallsign,
            eqslPassword: providers.contains(.eqsl) ? CredentialVault.value(for: .eqslPassword) : "",
            eqslQTHNickname: activeStationProfile?.eqslQTHNickname ?? "",
            clubLogEmail: defaults.string(forKey: "clubLogEmail") ?? "",
            clubLogPassword: providers.contains(.clubLog) ? CredentialVault.value(for: .clubLogPassword) : "",
            clubLogAPIKey: providers.contains(.clubLog) ? CredentialVault.value(for: .clubLogAPIKey) : "",
            clubLogCallsign: defaults.string(forKey: "clubLogCallsign") ?? currentStationCallsign
        )
    }

    /// Writes a batch of job updates (one database transaction) and marks the accepted QSOs, changing qsoRecords
    /// once per batch. Returns how many QSOs were marked.
    @MainActor
    private func applyQSLJobUpdates(_ updates: [QSLJobUpdate], positions: inout QSLRunPositions, database: LogbookDatabase) -> Int {
        guard !updates.isEmpty else { return 0 }
        var jobs = qslQueueJobs
        for update in updates {
            if let index = positions.job(update.job.id, in: jobs) { jobs[index] = update.job }
        }
        qslQueueJobs = jobs
        try? database.saveQSLJobs(updates.map(\.job))

        let marked = updates.filter(\.markSent)
        guard !marked.isEmpty else { return 0 }
        let date = Self.qslDateString(Date())
        var records = qsoRecords
        var count = 0
        var lost: [UUID: [QSLLostMark]] = [:]
        for update in marked {
            // The QSO is not in the open log (it changed during the upload): the mark is saved for later.
            guard let index = positions.record(update.job.qsoID, in: records) else {
                lost[update.job.stationProfileID, default: []].append(
                    QSLLostMark(qsoID: update.job.qsoID, provider: update.job.provider, date: Self.qslDateString(update.job.updatedAt))
                )
                continue
            }
            for (field, value) in QSLUploadStatus.acceptedFields(for: update.job.provider, date: date) {
                records[index].fields[field] = value
                if !tableHeaders.contains(field) { tableHeaders.append(field) }
            }
            count += 1
        }
        if count > 0 { qsoRecords = records }
        for (profileID, marks) in lost { QSLLostMarkStore.standard.append(marks, profileID: profileID) }
        return count
    }

    static func qslDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    /// The Zero-Click daemon uploads each new QSO by itself and reports the services that accepted it; the QSO is
    /// then marked as the QSL Hub marks it, so Sync All does not upload it again. The daemon's outbox rebuilds the
    /// record with a new id, so the QSO is looked up by id and then by its QSO key.
    func markZeroClickUploads(_ record: QSORecordModel, services: [String]) {
        let providers = services.compactMap { QSLUploadStatus.provider(zeroClickService: $0) }
        guard !providers.isEmpty, isOwnStationLogOpen, let index = zeroClickRecordIndex(record) else { return }
        let id = qsoRecords[index].id
        for provider in providers { markQSO(id, sentTo: provider) }
        autoSaveActiveWorkspace()
    }

    /// For the Zero-Click daemon's outbox (R8): whether a QSO it is about to send again is already at that service,
    /// for example because a Sync sent it meanwhile. Only the station's own log is looked at.
    func isZeroClickQSOAlreadyAtService(_ record: QSORecordModel, service: String) -> Bool {
        guard isOwnStationLogOpen, let provider = QSLUploadStatus.provider(zeroClickService: service),
              let index = zeroClickRecordIndex(record) else { return false }
        return QSLUploadStatus.isSent(qsoRecords[index].fields, to: provider)
    }

    /// The daemon's QSO in the open log: by id, or, because the outbox rebuilds the record with a new id, by its QSO
    /// key, never an empty one. The search goes from the end, where new QSOs are, and compares the callsign first.
    private func zeroClickRecordIndex(_ record: QSORecordModel) -> Int? {
        if let index = qsoRecords.lastIndex(where: { $0.id == record.id }) { return index }
        let key = record.uniqueKey
        guard !key.isEmpty else { return nil }
        let call = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return qsoRecords.lastIndex(where: {
            $0["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == call && $0.uniqueKey == key
        })
    }

    /// Marks saved because the QSO was not in the open log when its service accepted it (QSLLostMark) are written
    /// with their upload date when the station's own log is open, unless the QSO's fields for that service have a
    /// value by then (QSLSyncAll.sortLostMarks). Called when the QSL Hub state loads and when the master log loads.
    func restoreLostQSLMarks() {
        guard isOwnStationLogOpen, let profileID = activeStationProfileID else { return }
        let store = QSLLostMarkStore.standard
        guard !store.load(profileID: profileID).isEmpty else { return }
        let fieldsByID = Dictionary(qsoRecords.map { ($0.id, $0.fields) }, uniquingKeysWith: { first, _ in first })
        let write = store.restore(profileID: profileID, fieldsByID: fieldsByID)
        for mark in write { markQSO(mark.qsoID, sentTo: mark.provider, date: mark.date) }
        if !write.isEmpty { autoSaveActiveWorkspace() }
    }

    /// QSOs that 1.37.34 marked as sent to Club Log only in YAAM's own field also get the ADIF field
    /// (QSLUploadStatus.withStandardClubLogStatus), so the next save and every export carry it. Returns the count.
    @discardableResult
    func addStandardClubLogStatus() -> Int {
        var records = qsoRecords
        var count = 0
        for index in records.indices {
            guard let updated = QSLUploadStatus.withStandardClubLogStatus(records[index].fields) else { continue }
            records[index].fields = updated
            count += 1
        }
        guard count > 0 else { return 0 }
        qsoRecords = records
        for field in ["CLUBLOG_QSO_UPLOAD_STATUS", "CLUBLOG_QSO_UPLOAD_DATE"] where !tableHeaders.contains(field) {
            tableHeaders.append(field)
        }
        return count
    }

    private func markQSO(_ id: UUID, sentTo provider: QSLProvider, date: String? = nil) {
        guard let index = qsoRecords.firstIndex(where: { $0.id == id }) else { return }
        for (field, value) in QSLUploadStatus.acceptedFields(for: provider, date: date ?? Self.qslDateString(Date())) {
            qsoRecords[index].fields[field] = value
            if !tableHeaders.contains(field) { tableHeaders.append(field) }
        }
    }

    /// eQSL confirmation -> local QSO, with eQSL's own one-hour window. `candidates` is a snapshot of
    /// qsoRecords' fields taken before the loop; a matched QSO is claimed so it takes one confirmation per download.
    func eqslConfirmationMatchIndex(_ incoming: [String: String], candidates: [[String: String]], claimed: inout Set<Int>) -> Int? {
        guard let index = QSOIdentity.bestToleranceMatch(
            incoming: incoming,
            candidates: candidates,
            claimed: claimed,
            toleranceSeconds: QSOIdentity.eqslTimeToleranceSeconds
        ) else { return nil }
        claimed.insert(index)
        return index
    }

    func qslConfirmationMatchIndex(_ incoming: [String: String]) -> Int? {
        let candidate = QSORecordModel(index: 0, fields: incoming)
        if let exact = qsoRecords.firstIndex(where: { $0.uniqueKey == candidate.uniqueKey }) { return exact }
        let call = incoming["CALL"]?.uppercased() ?? ""
        let date = (incoming["QSO_DATE"] ?? "").filter(\.isNumber)
        let time = (incoming["TIME_ON"] ?? "").filter(\.isNumber)
        let band = (incoming["BAND"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let mode = (incoming["MODE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return qsoRecords.firstIndex {
            let localTime = $0["TIME_ON"].filter(\.isNumber)
            let timeMatches = time.isEmpty || localTime.isEmpty || String(localTime.prefix(4)) == String(time.prefix(4))
            let localBand = $0["BAND"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let bandMatches = band.isEmpty || localBand.isEmpty || band == localBand
            let localMode = $0["MODE"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let modeMatches = mode.isEmpty || localMode.isEmpty || mode == localMode
            return $0["CALL"].uppercased() == call && $0["QSO_DATE"].filter(\.isNumber) == date && timeMatches && bandMatches && modeMatches
        }
    }
}

/// Where the jobs and QSOs of one queue run were found, so that each lookup is not a search of the whole list. A
/// position is used only after checking the id at it, because the lists can change while the run waits for a service.
struct QSLRunPositions {
    private var jobIndex: [UUID: Int]
    private var recordIndex: [UUID: Int]

    init(jobs: [QSLQueueJob], records: [QSORecordModel]) {
        jobIndex = Dictionary(jobs.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        recordIndex = Dictionary(records.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    mutating func job(_ id: UUID, in jobs: [QSLQueueJob]) -> Int? {
        if let index = jobIndex[id], index < jobs.count, jobs[index].id == id { return index }
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return nil }
        jobIndex[id] = index
        return index
    }

    mutating func record(_ id: UUID, in records: [QSORecordModel]) -> Int? {
        if let index = recordIndex[id], index < records.count, records[index].id == id { return index }
        guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        recordIndex[id] = index
        return index
    }
}
