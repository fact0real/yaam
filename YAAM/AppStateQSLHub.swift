//
//  AppStateQSLHub.swift
//  YAAM
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension AppState {
    func loadQSLHubState() {
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

    func enqueueQSL(records: [QSORecordModel], providers: Set<QSLProvider>) {
        guard let profileID = activeStationProfileID, let database = logbookDatabase else {
            qslHubStatus = "Choose an active station first"
            return
        }
        guard !records.isEmpty, !providers.isEmpty else {
            qslHubStatus = "Select at least one QSO and one service"
            return
        }

        var added = 0
        var changedJobs: [QSLQueueJob] = []
        var existingByKey: [String: QSLQueueJob] = [:]
        for job in qslQueueJobs { existingByKey["\(job.qsoID.uuidString)|\(job.provider.rawValue)"] = job }
        for record in records {
            for provider in providers {
                let alreadySent = ["Y", "V", "C", "CONFIRMED"].contains(record[provider.sentField].uppercased())
                let key = "\(record.id.uuidString)|\(provider.rawValue)"
                let existing = existingByKey[key]
                if alreadySent || existing?.state == .succeeded { continue }

                var job = existing ?? QSLQueueJob(
                    stationProfileID: profileID,
                    qsoID: record.id,
                    provider: provider,
                    adif: qslADIFRecord(record.fields)
                )
                job.adif = qslADIFRecord(record.fields)
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
        if added > 0 { playActivitySound(.notice) }
    }

    func enqueueAutomaticQSL(for record: QSORecordModel) {
        guard UserDefaults.standard.bool(forKey: "qslAutoQueueQuickLog") else { return }
        let raw = UserDefaults.standard.string(forKey: "qslAutomaticProviders") ?? ""
        let providers = Set(raw.split(separator: ",").compactMap { QSLProvider(rawValue: String($0)) })
        guard !providers.isEmpty else { return }
        enqueueQSL(records: [record], providers: providers)
        Task { await processQSLQueue() }
    }

    @MainActor
    func processQSLQueue() async {
        guard !isProcessingQSLQueue, let database = logbookDatabase else { return }
        let due = qslQueueJobs.filter {
            ($0.state == .queued || $0.state == .retry) && ($0.nextAttemptAt == nil || $0.nextAttemptAt! <= Date())
        }
        guard !due.isEmpty else {
            qslHubStatus = "No uploads are due"
            return
        }

        isProcessingQSLQueue = true
        qslHubStatus = "Uploading \(due.count) item(s)..."
        let credentials = qslServiceCredentials(for: Set(due.map(\.provider)))
        var didUpdateRecords = false

        for provider in QSLProvider.allCases {
            let providerJobs = due.filter { $0.provider == provider }
            guard !providerJobs.isEmpty else { continue }
            updateQSLJobs(providerJobs, state: .uploading, message: "Contacting \(provider.title)", database: database)

            let batchSize = provider == .qrz ? 1 : 200
            for batchStart in stride(from: 0, to: providerJobs.count, by: batchSize) {
                let end = min(providerJobs.count, batchStart + batchSize)
                let batch = Array(providerJobs[batchStart..<end])
                let result = await qslHubClient.upload(provider: provider, adifRecords: batch.map(\.adif), credentials: credentials)
                if result.accepted {
                    for original in batch {
                        completeQSLJob(original, result: result, database: database)
                        markQSO(original.qsoID, sentTo: provider)
                    }
                    didUpdateRecords = true
                } else {
                    for original in batch { failQSLJob(original, result: result, database: database) }
                }
            }
        }

        if didUpdateRecords { autoSaveActiveWorkspace() }
        isProcessingQSLQueue = false
        let pending = qslQueueJobs.filter { $0.state.isPending }.count
        let blocked = qslQueueJobs.filter { $0.state == .blocked }.count
        qslHubStatus = pending > 0 ? "\(pending) waiting · \(blocked) blocked" : "QSL uploads complete"
        refreshAwardProgress()
        playActivitySound(blocked > 0 ? .notice : .success)
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
            for fields in incoming {
                guard let index = qslConfirmationMatchIndex(fields) else { continue }
                qsoRecords[index].fields = ImportReviewAnalyzer.mergeUpdate(incoming: fields, into: qsoRecords[index].fields)
                qsoRecords[index].fields["EQSL_QSL_RCVD"] = "Y"
                updated += 1
            }
            if updated > 0 { autoSaveActiveWorkspace() }
            UserDefaults.standard.set(Date(), forKey: "eqslLastInboxSync")
            qslHubStatus = "Matched \(updated) eQSL confirmation(s)"
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

    private func qslServiceCredentials(for providers: Set<QSLProvider>) -> QSLServiceCredentials {
        let defaults = UserDefaults.standard
        return QSLServiceCredentials(
            qrzAPIKey: providers.contains(.qrz) ? activeQRZAPIKey : "",
            lotwCallsign: defaults.string(forKey: "lotwUsername") ?? currentStationCallsign,
            lotwPassword: providers.contains(.lotw) ? CredentialVault.value(for: .lotwPassword) : "",
            lotwStationLocation: activeStationProfile?.lotwStationLocation ?? "",
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

    private func updateQSLJobs(_ jobs: [QSLQueueJob], state: QSLQueueState, message: String, database: LogbookDatabase) {
        for job in jobs {
            guard let index = qslQueueJobs.firstIndex(where: { $0.qsoID == job.qsoID && $0.provider == job.provider }) else { continue }
            qslQueueJobs[index].state = state
            qslQueueJobs[index].message = message
            qslQueueJobs[index].updatedAt = Date()
            try? database.saveQSLJob(qslQueueJobs[index])
        }
    }

    private func completeQSLJob(_ job: QSLQueueJob, result: QSLUploadResult, database: LogbookDatabase) {
        guard let index = qslQueueJobs.firstIndex(where: { $0.qsoID == job.qsoID && $0.provider == job.provider }) else { return }
        qslQueueJobs[index].state = .succeeded
        qslQueueJobs[index].attempts += 1
        qslQueueJobs[index].nextAttemptAt = nil
        qslQueueJobs[index].message = result.message
        qslQueueJobs[index].updatedAt = Date()
        try? database.saveQSLJob(qslQueueJobs[index])
    }

    private func failQSLJob(_ job: QSLQueueJob, result: QSLUploadResult, database: LogbookDatabase) {
        guard let index = qslQueueJobs.firstIndex(where: { $0.qsoID == job.qsoID && $0.provider == job.provider }) else { return }
        qslQueueJobs[index].attempts += 1
        if result.authenticationFailure {
            qslQueueJobs[index].state = .blocked
            qslQueueJobs[index].nextAttemptAt = nil
        } else if qslQueueJobs[index].attempts >= 5 {
            qslQueueJobs[index].state = .failed
            qslQueueJobs[index].nextAttemptAt = nil
        } else {
            qslQueueJobs[index].state = .retry
            let delay = min(3_600.0, pow(2.0, Double(qslQueueJobs[index].attempts)) * 30.0)
            qslQueueJobs[index].nextAttemptAt = Date().addingTimeInterval(delay)
        }
        qslQueueJobs[index].message = result.message
        qslQueueJobs[index].updatedAt = Date()
        try? database.saveQSLJob(qslQueueJobs[index])
    }

    private func markQSO(_ id: UUID, sentTo provider: QSLProvider) {
        guard let index = qsoRecords.firstIndex(where: { $0.id == id }) else { return }
        qsoRecords[index].fields[provider.sentField] = "Y"
        let dateField = switch provider {
        case .lotw: "LOTW_QSLSDATE"
        case .qrz: "QRZCOM_QSO_UPLOAD_DATE"
        case .eqsl: "EQSL_QSLSDATE"
        case .clubLog: "APP_YAAM_CLUBLOG_SENT_DATE"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        qsoRecords[index].fields[dateField] = formatter.string(from: Date())
        for header in [provider.sentField, dateField] where !tableHeaders.contains(header) { tableHeaders.append(header) }
    }

    private func qslConfirmationMatchIndex(_ incoming: [String: String]) -> Int? {
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

    private func qslADIFRecord(_ fields: [String: String]) -> String {
        var result = ""
        for key in fields.keys.sorted() {
            guard let value = fields[key], !value.isEmpty else { continue }
            result += "<\(key):\(value.utf8.count)>\(value)"
        }
        return result + "<EOR>"
    }
}
