import Foundation

extension AppState {
    func incomingCandidates(_ request: QRZIncomingConfirmation) -> [QSORecordModel] {
        qsoRecords.filter {
            IncomingContactReview.clean($0["CALL"]) == IncomingContactReview.clean(request.callsign) &&
            (request.qsoDate.isEmpty || QSOIdentity.normalizedDate($0["QSO_DATE"]) == QSOIdentity.normalizedDate(request.qsoDate))
        }
    }

    /// Persist first, without invoking Quick Log's automatic upload or confirmation paths.
    func saveIncomingReview(_ review: IncomingContactReview, request: QRZIncomingConfirmation) throws -> QSORecordModel {
        func fail(_ message: String) -> NSError { NSError(domain: "IncomingReview", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        if let problem = review.problem { throw fail(problem) }
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
        var fields = exact.first?.fields ?? review.fields
        fields["APP_YAAM_INCOMING_REQUEST"] = request.qsoID.isEmpty ? request.id : request.qsoID
        fields["APP_YAAM_INCOMING_EVIDENCE"] = review.evidence
        fields["APP_YAAM_INCOMING_VERIFIED_AT"] = ISO8601DateFormatter().string(from: Date())
        var record = exact.first ?? QSORecordModel(index: qsoRecords.count + 1, fields: fields)
        record.fields = fields
        let previous = qsoRecords
        let previousHeaders = tableHeaders
        if let index = qsoRecords.firstIndex(where: { $0.id == record.id }) { qsoRecords[index] = record }
        else { qsoRecords.append(record) }
        tableHeaders.append(contentsOf: fields.keys.filter { !tableHeaders.contains($0) }.sorted())
        do { try persistCurrentWorkspace(reason: "Verified QRZ Incoming recovery") }
        catch { qsoRecords = previous; tableHeaders = previousHeaders; throw error }
        refreshAwardProgress()
        updateMobileCompanionSnapshot()
        return record
    }
}

