import Foundation

extension AppState {
    func incomingCandidates(_ request: QRZIncomingConfirmation) -> [QSORecordModel] {
        qsoRecords.filter {
            IncomingContactReview.clean($0["CALL"]) == IncomingContactReview.clean(request.callsign) &&
            (request.qsoDate.isEmpty || QSOIdentity.normalizedDate($0["QSO_DATE"]) == QSOIdentity.normalizedDate(request.qsoDate))
        }
    }

    var isIncomingRecoveryBusy: Bool {
        isProcessingQSLQueue || isLoading || isSyncingAPI || isUnifiedSyncRunning || isCloudSyncRunning ||
        QSLSyncEngine.shared.isSyncing || ZeroClickCloudUploadDaemon.shared.isUploading || ZeroClickCloudUploadDaemon.shared.isFlushingQueue
    }

    /// One durable action: verified local record plus the three service intents. No network or confirmation side effects.
    func saveIncomingReview(_ review: IncomingContactReview, request: QRZIncomingConfirmation) throws -> QSORecordModel {
        func fail(_ message: String) -> NSError { NSError(domain: "IncomingReview", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        if let problem = review.problem { throw fail(problem) }
        guard let profileID = activeStationProfileID else { throw fail("Choose an active station first.") }
        guard !isIncomingRecoveryBusy else { throw fail("Wait for the current sync or upload to finish before recovering a contact.") }
        guard isOwnStationLogOpen, IncomingContactReview.clean(currentStationCallsign) == review.fields["STATION_CALLSIGN"],
              !isSelfContact(review.fields) else { throw fail("Open the matching station's own log before saving.") }
        guard review.fields["CALL"] == IncomingContactReview.clean(request.callsign) else { throw fail("The worked callsign must match this request.") }
        let exact = qsoRecords.filter {
            QSOIdentity.exactKey(fields: $0.fields) == QSOIdentity.exactKey(fields: review.fields) &&
            UploadStationPolicy.matches($0.fields, stationCallsign: currentStationCallsign)
        }
        guard exact.count <= 1 else { throw fail("Multiple local records match. Resolve the duplicate records in the log first.") }
        guard !exact.isEmpty || incomingCandidates(request).isEmpty || review.separateContact else {
            throw fail("A local candidate exists. Correct it in the log editor and review again, or explicitly verify this is a separate contact.")
        }
        let linked = qsoRecords.filter {
            QRZIncomingRecoveryArchive.linkedKeys($0.fields).contains(request.recoveryKey) &&
            UploadStationPolicy.matches($0.fields, stationCallsign: currentStationCallsign)
        }
        guard linked.allSatisfy({ QSOIdentity.exactKey(fields: $0.fields) == QSOIdentity.exactKey(fields: review.fields) }) else {
            throw fail("This request is already linked to another contact. Review that local record instead of creating a duplicate.")
        }
        var fields = exact.first?.fields ?? review.fields
        fields["STATION_CALLSIGN"] = review.fields["STATION_CALLSIGN"]
        if let qrzAlreadyLogged = review.qrzAlreadyLogged {
            fields["APP_YAAM_QRZ_VERIFIED_PRESENT"] = qrzAlreadyLogged ? "Y" : nil
        }
        var requestKeys = QRZIncomingRecoveryArchive.linkedKeys(fields)
        requestKeys.insert(request.recoveryKey)
        fields["APP_YAAM_INCOMING_REQUESTS"] = String(data: try JSONEncoder().encode(requestKeys.sorted()), encoding: .utf8)
        if fields["APP_YAAM_INCOMING_REQUEST"] == nil { fields["APP_YAAM_INCOMING_REQUEST"] = request.recoveryKey }
        fields["APP_YAAM_INCOMING_EVIDENCE"] = review.evidence
        fields["APP_YAAM_INCOMING_VERIFIED_AT"] = ISO8601DateFormatter().string(from: Date())
        var record = exact.first ?? QSORecordModel(index: qsoRecords.count + 1, fields: fields)
        record.fields = fields
        let previous = qsoRecords
        let previousHeaders = tableHeaders
        if let index = qsoRecords.firstIndex(where: { $0.id == record.id }) { qsoRecords[index] = record }
        else { qsoRecords.append(record) }
        tableHeaders.append(contentsOf: fields.keys.filter { !tableHeaders.contains($0) }.sorted())
        let jobs = QSLSyncAll.queueChanges(
            records: [(id: record.id, fields: record.fields)], profileID: profileID,
            providers: QSLSyncAll.incomingRecoveryProviders, existingJobs: qslQueueJobs
        )
        do { try persistIncomingRecovery(jobs: jobs) }
        catch { qsoRecords = previous; tableHeaders = previousHeaders; throw error }
        for job in jobs {
            if let index = qslQueueJobs.firstIndex(where: { $0.qsoID == job.qsoID && $0.provider == job.provider }) {
                qslQueueJobs[index] = job
            } else { qslQueueJobs.append(job) }
        }
        qslHubStatus = "Contact saved locally; service status is available in the QSL Hub"
        retainQRZIncomingRecovery(request)
        refreshAwardProgress()
        updateMobileCompanionSnapshot()
        return record
    }
    func incomingRecoveryRecord(_ request: QRZIncomingConfirmation) -> QSORecordModel? {
        guard isOwnStationLogOpen else { return nil }
        let linked = qsoRecords.filter {
            QRZIncomingRecoveryArchive.linkedKeys($0.fields).contains(request.recoveryKey) &&
            UploadStationPolicy.matches($0.fields, stationCallsign: currentStationCallsign)
        }
        return linked.count == 1 ? linked.first : nil
    }

    func incomingRecoveryStatus(_ record: QSORecordModel, provider: QSLProvider) -> String {
        if provider == .qrz, record["APP_YAAM_QRZ_VERIFIED_PRESENT"] == "Y" { return "Recorded in QRZ · verified by you" }
        if QSLUploadStatus.isSent(record.fields, to: provider) { return "Accepted / already recorded" }
        guard let job = qslQueueJobs.first(where: {
            $0.stationProfileID == activeStationProfileID && $0.qsoID == record.id && $0.provider == provider
        }) else { return "Not queued — review and save to prepare" }
        switch job.state {
        case .succeeded: return "Accepted / already recorded"
        case .queued: return "Queued"
        case .uploading: return "Uploading"
        case .retry: return "Waiting to retry: " + job.message
        case .failed, .blocked: return "Needs attention: " + job.message
        }
    }
}

