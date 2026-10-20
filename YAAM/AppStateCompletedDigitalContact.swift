import Foundation

extension AppState {
    @discardableResult func logFT8StationQSO(_ completion: DigitalContactCompletion, radioName: String? = nil) -> Bool {
        guard isOwnStationLogOpen, completion.stationCall.uppercased() == currentStationCallsign.uppercased(),
              !completion.call.isEmpty, !completion.band.isEmpty, ["FT8", "FT4"].contains(completion.protocolName), completion.endedAt >= completion.startedAt else { return false }
        let sessionID = completion.id.uuidString
        if qsoRecords.contains(where: { $0["APP_YAAM_DIGITAL_SESSION_ID"] == sessionID }) { return true }
        var fields = completion.fields
        let entity = DXCCDatabase.resolve(callsign: completion.call)
        fields["COUNTRY"] = entity.entityName; fields["CONT"] = entity.continent
        if entity.cqZone > 0 { fields["CQZ"] = String(entity.cqZone) }
        if entity.ituZone > 0 { fields["ITUZ"] = String(entity.ituZone) }
        fields["APP_YAAM_SOURCE"] = radioName == nil ? "Digital Station" : "Multi-Rig Digital Station"
        if let radioName { fields["RADIO"] = radioName }
        let observedGrid = fields["MY_GRIDSQUARE"]
        fields = stationTaggedFields(fields)
        if let observedGrid, !observedGrid.isEmpty, fields["MY_GRIDSQUARE"] != observedGrid {
            fields["MY_GRIDSQUARE"] = observedGrid
            fields.removeValue(forKey: "MY_LAT"); fields.removeValue(forKey: "MY_LON")
        }
        guard !isSelfContact(fields) else { return false }
        if qsoRecords.contains(where: { QSOIdentity.exactKey(fields: $0.fields) == QSOIdentity.exactKey(fields: fields) }) { return true }
        let record = QSORecordModel(index: qsoRecords.count + 1, fields: fields)
        let oldRecords = qsoRecords, oldHeaders = tableHeaders
        qsoRecords.append(record)
        tableHeaders.append(contentsOf: fields.keys.filter { !tableHeaders.contains($0) }.sorted())
        do { try persistCurrentWorkspace(reason: "Completed \(completion.protocolName) exchange") }
        catch {
            qsoRecords = oldRecords; tableHeaders = oldHeaders
            appendLog("Digital contact could not be saved: \(error.localizedDescription)")
            return false
        }
        enqueueAutomaticQSL(for: record)
        ZeroClickCloudUploadDaemon.shared.dispatch(record: record, stationID: activeStationProfileID?.uuidString,
            stationLocation: activeStationProfile?.lotwStationLocation, qrzKeyOverride: activeQRZAPIKey)
        if !ZeroClickCloudUploadDaemon.shared.ownsWavelogPush { WavelogSyncEngine.shared.autoPushSingleQSO(record: record) }
        if HRDLogClient.shared.autoUploadEnabled { Task { _ = await HRDLogClient.shared.uploadSingleQSO(record: record) } }
        if HamQTHUploadClient.shared.autoUploadEnabled { Task { _ = await HamQTHUploadClient.shared.uploadSingleQSO(record: record) } }
        refreshAwardProgress(); updateMobileCompanionSnapshot(); playActivitySound(.success)
        return true
    }

}
