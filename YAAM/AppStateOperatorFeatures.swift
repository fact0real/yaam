//
//  AppStateOperatorFeatures.swift
//  YAAM
//

import AppKit
import Foundation

private let operatorUTCDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMddHHmmss"
    return formatter
}()

extension AppState {
    func refreshQuickLogAssessment() {
        quickLogAssessment = assessment(for: quickLogDraft)
    }

    func assessment(for draft: QuickLogDraft) -> QuickLogAssessment {
        let callsign = draft.normalizedCallsign
        guard !callsign.isEmpty else { return QuickLogAssessment() }

        let now = draft.startedAt
        let band = draft.band.lowercased()
        let mode = draft.mode.uppercased()
        var result = QuickLogAssessment()

        for record in qsoRecords where record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == callsign {
            result.totalWorked += 1
            if record.isConfirmed { result.confirmed += 1 }
            let sameBand = record["BAND"].lowercased() == band
            if sameBand { result.sameBand += 1 }
            if sameBand, record["MODE"].uppercased() == mode { result.sameBandMode += 1 }

            if let recordDate = operatorQSODate(record), abs(recordDate.timeIntervalSince(now)) <= 30 * 60 {
                if sameBand, record["MODE"].uppercased() == mode {
                    result.recentDuplicateCount += 1
                }
                if result.lastWorkedAt == nil || recordDate > result.lastWorkedAt! {
                    result.lastWorkedAt = recordDate
                }
            } else if let recordDate = operatorQSODate(record), result.lastWorkedAt == nil || recordDate > result.lastWorkedAt! {
                result.lastWorkedAt = recordDate
            }
        }
        result.contestDuplicate = isCurrentContestDuplicate(callsign: callsign, band: draft.band, mode: draft.mode)
        return result
    }

    @MainActor
    func lookupQuickLogCallsign(_ callsign: String) async {
        let normalized = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized == quickLogDraft.normalizedCallsign, isValidOperatorCallsign(normalized) else {
            quickLogLookup = nil
            isLookingUpQuickLogCallsign = false
            return
        }

        isLookingUpQuickLogCallsign = true
        quickLogStatus = "Looking up \(normalized)..."
        let credentials = CallsignLookupCredentials(
            qrzUsername: UserDefaults.standard.string(forKey: "qrzUsername") ?? "",
            qrzPassword: CredentialVault.value(for: .qrzPassword),
            hamqthUsername: UserDefaults.standard.string(forKey: "hamqthUsername") ?? "",
            hamqthPassword: CredentialVault.value(for: .hamqthPassword),
            agent: "YAAM-\(currentVersion)"
        )
        let result = await callsignLookupService.lookup(
            callsign: normalized,
            credentials: credentials,
            localFallback: localCallsignFallback(normalized)
        )
        guard normalized == quickLogDraft.normalizedCallsign else { return }

        quickLogLookup = result
        if result.hasUsefulData {
            applyLookupToQuickLog(result)
            quickLogStatus = "Loaded from \(result.sources.joined(separator: " + "))"
        } else {
            quickLogStatus = result.message
        }
        isLookingUpQuickLogCallsign = false
    }

    @MainActor
    func saveQuickLog() throws -> QSORecordModel {
        guard activeStationProfileID != nil else { throw QuickLogValidationError.noActiveStation }
        if !isMasterMode { loadMasterLogbook() }

        var draft = quickLogDraft
        draft.callsign = draft.normalizedCallsign
        guard isValidOperatorCallsign(draft.callsign) else { throw QuickLogValidationError.invalidCallsign }
        guard let frequency = AmateurBandPlan.normalizedMHz(draft.frequencyMHz) else { throw QuickLogValidationError.invalidFrequency }
        if let detectedBand = AmateurBandPlan.band(forMHz: frequency) { draft.band = detectedBand }
        guard !draft.band.isEmpty else { throw QuickLogValidationError.missingBand }
        guard !draft.mode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw QuickLogValidationError.missingMode }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: draft.startedAt)
        let date = String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        let time = String(format: "%02d%02d%02d", components.hour ?? 0, components.minute ?? 0, components.second ?? 0)

        var fields: [String: String] = [
            "QSO_DATE": date,
            "TIME_ON": time,
            "CALL": draft.callsign,
            "FREQ": AmateurBandPlan.formattedMHz(frequency),
            "BAND": draft.band,
            "MODE": draft.mode.uppercased(),
            "RST_SENT": draft.rstSent.trimmingCharacters(in: .whitespacesAndNewlines),
            "RST_RCVD": draft.rstReceived.trimmingCharacters(in: .whitespacesAndNewlines),
            "QSL_SENT": "N",
            "QSL_RCVD": "N",
            "APP_YAAM_SOURCE": draft.source
        ]
        let optionalFields: [(String, String)] = [
            ("SUBMODE", draft.submode), ("NAME", draft.name), ("QTH", draft.qth),
            ("GRIDSQUARE", draft.grid), ("COUNTRY", draft.country), ("DXCC", draft.dxcc),
            ("CQZ", draft.cqZone), ("ITUZ", draft.ituZone), ("COMMENT", draft.comment)
        ]
        for (key, value) in optionalFields {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { fields[key] = clean }
        }

        let portableFields: [(String, String)] = [
            ("MY_POTA_REF", draft.myPOTAReference), ("POTA_REF", draft.contactedPOTAReference),
            ("MY_SOTA_REF", draft.mySOTAReference), ("SOTA_REF", draft.contactedSOTAReference),
            ("MY_IOTA", draft.myIOTAReference), ("IOTA", draft.contactedIOTAReference),
            ("MY_VUCC_GRIDS", draft.myVUCCGrids), ("VUCC_GRIDS", draft.contactedVUCCGrids)
        ]
        for (key, value) in portableFields {
            let clean = PortableActivityEngine.normalizedReference(value)
            if !clean.isEmpty { fields[key] = clean }
        }
        if draft.portableRole != .none {
            fields["APP_YAAM_PORTABLE_ROLE"] = draft.portableRole.rawValue.uppercased()
        }
        if let reference = fields["MY_POTA_REF"] {
            fields["MY_SIG"] = "POTA"
            fields["MY_SIG_INFO"] = reference
        } else if let reference = fields["MY_SOTA_REF"] {
            fields["MY_SIG"] = "SOTA"
            fields["MY_SIG_INFO"] = reference
        }
        if let reference = fields["POTA_REF"] {
            fields["SIG"] = "POTA"
            fields["SIG_INFO"] = reference
        } else if let reference = fields["SOTA_REF"] {
            fields["SIG"] = "SOTA"
            fields["SIG_INFO"] = reference
        }

        let contestSession = currentContestSession.flatMap { $0.isActive ? $0 : nil }
        if let session = contestSession {
            let serial = ContestWorkspaceLogic.nextSerial(in: session, records: qsoRecords)
            fields["CONTEST_ID"] = session.contestID
            fields["STX"] = String(serial)
            if !session.sentExchange.isEmpty { fields["STX_STRING"] = session.sentExchange }
            let receivedExchange = draft.receivedExchange.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !receivedExchange.isEmpty {
                fields["SRX_STRING"] = receivedExchange
                if receivedExchange.allSatisfy(\.isNumber) { fields["SRX"] = receivedExchange }
            }
        }
        if let lookup = quickLogLookup {
            if !lookup.latitude.isEmpty { fields["LAT"] = lookup.latitude }
            if !lookup.longitude.isEmpty { fields["LON"] = lookup.longitude }
            if !lookup.email.isEmpty { fields["EMAIL"] = lookup.email }
        }

        fields = stationTaggedFields(fields)
        let record = QSORecordModel(index: qsoRecords.count + 1, fields: fields)
        guard !qsoRecords.contains(where: { $0.uniqueKey == record.uniqueKey }) else {
            throw QuickLogValidationError.exactDuplicate
        }

        let preferredHeaders = [
            "QSO_DATE", "TIME_ON", "CALL", "FREQ", "BAND", "MODE", "SUBMODE", "RST_SENT", "RST_RCVD",
            "NAME", "QTH", "GRIDSQUARE", "COUNTRY", "DXCC", "CQZ", "ITUZ", "COMMENT", "QSL_SENT",
            "QSL_RCVD", "STATION_CALLSIGN", "OPERATOR", "APP_YAAM_STATION_PROFILE_ID", "APP_YAAM_SOURCE"
            , "CONTEST_ID", "STX", "STX_STRING", "SRX", "SRX_STRING"
            , "MY_POTA_REF", "POTA_REF", "MY_SOTA_REF", "SOTA_REF", "MY_IOTA", "IOTA",
            "MY_VUCC_GRIDS", "VUCC_GRIDS", "MY_SIG", "MY_SIG_INFO", "SIG", "SIG_INFO"
        ]
        for header in preferredHeaders where fields[header] != nil && !tableHeaders.contains(header) {
            tableHeaders.append(header)
        }
        for header in fields.keys.sorted() where !tableHeaders.contains(header) {
            tableHeaders.append(header)
        }

        qsoRecords.append(record)
        quickLogLastSaved = record
        persistQuickLog(record)
        appendLog("Logged QSO: \(record["CALL"]) · \(record["FREQ"]) MHz · \(record["MODE"]).")
        playActivitySound(.success)
        if contestSession != nil { advanceContestSerial() }

        quickLogDraft.resetForNextQSO()
        quickLogDraft.startedAt = Date()
        quickLogLookup = nil
        quickLogAssessment = QuickLogAssessment()
        quickLogStatus = "Saved \(record["CALL"])"
        enqueueAutomaticQSL(for: record)
        refreshAwardProgress()
        updateMobileCompanionSnapshot()
        return record
    }

    @MainActor
    func prepareQuickLog(from spot: DXSpot) {
        var draft = quickLogDraft
        draft.callsign = spot.callsign
        draft.frequencyMHz = AmateurBandPlan.formattedMHz(spot.frequencyMHz)
        draft.band = spot.band.isEmpty ? (AmateurBandPlan.band(forMHz: spot.frequencyMHz) ?? draft.band) : spot.band
        draft.mode = spot.mode
        draft.submode = spot.submode
        draft.startedAt = Date()
        draft.rstSent = AmateurBandPlan.defaultRST(for: spot.mode)
        draft.rstReceived = AmateurBandPlan.defaultRST(for: spot.mode)
        draft.grid = spot.grid
        draft.comment = spot.comment
        draft.source = "DX Cluster"
        quickLogDraft = draft
        quickLogLookup = nil
        refreshQuickLogAssessment()
        quickLogStatus = "Prepared from spot by \(spot.spotter)"
        operatorDeskSection = 0
    }

    func workIndex() -> LogWorkIndex {
        LogWorkIndex(records: qsoRecords.map(\.fields))
    }

    func isValidOperatorCallsign(_ callsign: String) -> Bool {
        let normalized = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (3...20).contains(normalized.count),
              normalized.contains(where: \.isLetter),
              normalized.contains(where: \.isNumber) else { return false }
        let allowed = CharacterSet.uppercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "/-"))
        return normalized.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func localCallsignFallback(_ callsign: String) -> CallsignLookupResult {
        guard let record = qsoRecords.last(where: {
            $0["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == callsign
        }) else { return CallsignLookupResult(callsign: callsign) }

        return CallsignLookupResult(
            callsign: callsign,
            name: record["NAME"],
            qth: record["QTH"],
            grid: record["GRIDSQUARE"].isEmpty ? record["GRID"] : record["GRIDSQUARE"],
            country: record["COUNTRY"],
            dxcc: record["DXCC"],
            cqZone: record["CQZ"],
            ituZone: record["ITUZ"],
            email: record["EMAIL"],
            latitude: record["LAT"],
            longitude: record["LON"],
            sources: ["Local log"]
        )
    }

    private func applyLookupToQuickLog(_ result: CallsignLookupResult) {
        if quickLogDraft.name.isEmpty { quickLogDraft.name = result.name }
        if quickLogDraft.qth.isEmpty { quickLogDraft.qth = result.qth }
        if quickLogDraft.grid.isEmpty { quickLogDraft.grid = result.grid }
        if quickLogDraft.country.isEmpty { quickLogDraft.country = result.country }
        if quickLogDraft.dxcc.isEmpty { quickLogDraft.dxcc = result.dxcc }
        if quickLogDraft.cqZone.isEmpty { quickLogDraft.cqZone = result.cqZone }
        if quickLogDraft.ituZone.isEmpty { quickLogDraft.ituZone = result.ituZone }
    }

    private func operatorQSODate(_ record: QSORecordModel) -> Date? {
        let date = record["QSO_DATE"].filter(\.isNumber)
        var time = record["TIME_ON"].filter(\.isNumber)
        while time.count < 6 { time.append("0") }
        guard date.count == 8, time.count >= 4 else { return nil }
        return operatorUTCDateFormatter.date(from: date + String(time.prefix(6)))
    }

    private func persistQuickLog(_ record: QSORecordModel) {
        guard isMasterMode,
              let database = logbookDatabase,
              let profileID = activeStationProfileID,
              loadedWorkspaceProfileID == profileID else {
            autoSaveActiveWorkspace()
            return
        }

        let persisted = PersistedQSO(id: record.id, index: record.index, fields: record.fields)
        let headers = tableHeaders
        workspaceSaveQueue.async { [weak self] in
            do {
                try database.appendQSO(profileID: profileID, headers: headers, record: persisted)
            } catch {
                DispatchQueue.main.async {
                    self?.databaseStatus = error.localizedDescription
                    self?.quickLogStatus = "QSO is visible but could not be saved: \(error.localizedDescription)"
                    self?.appendLog("Quick Log database save failed: \(error.localizedDescription)")
                    self?.playActivitySound(.failure)
                }
            }
        }
    }
}
