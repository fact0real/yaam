//
//  AppStateRadioContestFeatures.swift
//  YAAM
//

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

private let contestSessionDefaultsKey = "activeContestSession.v1"

extension AppState {
    func configureOperatorFeatureBridges() {
        rigControlClient.$snapshot
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard UserDefaults.standard.bool(forKey: "rigAutoFillQuickLog") else { return }
                self?.applyRigSnapshotToQuickLog(snapshot)
            }
            .store(in: &operatorFeatureCancellables)

        wsjtxListener.$lastStatus
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard UserDefaults.standard.bool(forKey: "wsjtxAutoFillQuickLog") else { return }
                self?.applyWSJTXStatusToQuickLog(status)
            }
            .store(in: &operatorFeatureCancellables)

        wsjtxListener.$loggedEvents
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] events in self?.ingestWSJTXEvents(events) }
            .store(in: &operatorFeatureCancellables)
    }

    func applyRigSnapshotToQuickLog(_ snapshot: RigSnapshot) {
        var draft = quickLogDraft
        draft.applyFrequency(snapshot.frequencyMHz)
        let mapped = mappedADIFMode(snapshot.mode)
        if !mapped.mode.isEmpty {
            draft.mode = mapped.mode
            draft.submode = mapped.submode
        }
        quickLogDraft = draft
        refreshQuickLogAssessment()
    }

    func applyWSJTXStatusToQuickLog(_ status: WSJTXStatusSnapshot) {
        var draft = quickLogDraft
        draft.applyFrequency(status.frequencyMHz)
        let mapped = mappedADIFMode(status.mode)
        draft.mode = mapped.mode
        draft.submode = mapped.submode
        if !status.dxCallsign.isEmpty { draft.callsign = status.dxCallsign }
        if !status.dxGrid.isEmpty { draft.grid = status.dxGrid }
        if !status.report.isEmpty { draft.rstReceived = status.report }
        draft.rstSent = AmateurBandPlan.defaultRST(for: draft.mode)
        draft.startedAt = Date()
        draft.source = status.sourceID.isEmpty ? "WSJT-X" : status.sourceID
        quickLogDraft = draft
        refreshQuickLogAssessment()
    }

    func prepareQuickLog(from pending: WSJTXPendingQSO) {
        quickLogDraft = quickLogDraft(from: pending)
        quickLogLookup = nil
        refreshQuickLogAssessment()
        quickLogStatus = "Reviewing a logged QSO from \(pending.sourceID)"
        operatorDeskSection = 0
    }

    @discardableResult
    func importWSJTXPendingQSO(id: UUID) throws -> QSORecordModel {
        guard let pending = wsjtxPendingQSOs.first(where: { $0.id == id }) else {
            throw QuickLogValidationError.invalidCallsign
        }
        guard !pending.isDuplicate else { throw QuickLogValidationError.exactDuplicate }

        let savedDraft = quickLogDraft
        let savedLookup = quickLogLookup
        quickLogDraft = quickLogDraft(from: pending)
        quickLogLookup = nil
        do {
            let record = try saveQuickLog()
            quickLogDraft = savedDraft
            quickLogLookup = savedLookup
            refreshQuickLogAssessment()
            removeWSJTXPendingQSO(id: id)
            return record
        } catch {
            quickLogDraft = savedDraft
            quickLogLookup = savedLookup
            refreshQuickLogAssessment()
            throw error
        }
    }

    func dismissWSJTXPendingQSO(id: UUID) {
        removeWSJTXPendingQSO(id: id)
    }

    func loadContestSession() {
        guard let data = UserDefaults.standard.data(forKey: contestSessionDefaultsKey),
              let session = try? JSONDecoder().decode(ContestSession.self, from: data) else { return }
        currentContestSession = session
        contestStatus = session.isActive ? "\(session.displayName) is active" : "Last session: \(session.displayName)"
    }

    func startContestSession(_ proposed: ContestSession) {
        var session = proposed
        session.normalize()
        guard !session.contestID.isEmpty else {
            contestStatus = "Contest ID is required"
            return
        }
        session.startedAt = Date()
        session.endedAt = nil
        session.nextSerial = 1
        currentContestSession = session
        persistContestSession()
        contestStatus = "\(session.displayName) started in UTC"
        appendLog("Contest session started: \(session.contestID).")
    }

    func endContestSession() {
        guard var session = currentContestSession, session.isActive else { return }
        session.endedAt = Date()
        currentContestSession = session
        persistContestSession()
        contestStatus = "\(session.displayName) ended"
        appendLog("Contest session ended: \(session.contestID).")
    }

    func resumeContestSession() {
        guard var session = currentContestSession else { return }
        session.endedAt = nil
        session.nextSerial = ContestWorkspaceLogic.nextSerial(in: session, records: qsoRecords)
        currentContestSession = session
        persistContestSession()
        contestStatus = "\(session.displayName) resumed"
    }

    func clearContestSession() {
        currentContestSession = nil
        UserDefaults.standard.removeObject(forKey: contestSessionDefaultsKey)
        contestStatus = "No active contest session"
    }

    func advanceContestSerial() {
        guard var session = currentContestSession, session.isActive else { return }
        session.nextSerial += 1
        currentContestSession = session
        persistContestSession()
    }

    func contestSummary() -> ContestSummary {
        guard let session = currentContestSession else { return ContestSummary() }
        return ContestWorkspaceLogic.summary(in: session, records: qsoRecords)
    }

    func contestRecords() -> [QSORecordModel] {
        guard let session = currentContestSession else { return [] }
        return ContestWorkspaceLogic.records(in: session, from: qsoRecords)
    }

    func isCurrentContestDuplicate(callsign: String, band: String, mode: String) -> Bool {
        guard let session = currentContestSession, session.isActive else { return false }
        return ContestWorkspaceLogic.isDuplicate(
            callsign: callsign,
            band: band,
            mode: mode,
            session: session,
            records: qsoRecords
        )
    }

    func exportCurrentContestCabrillo() {
        guard let session = currentContestSession else {
            contestStatus = "Start or load a contest session before exporting"
            return
        }
        let content = CabrilloExporter.generate(
            session: session,
            station: activeStationProfile,
            records: qsoRecords,
            createdBy: "YAAM \(currentVersion)"
        )
        let panel = NSSavePanel()
        panel.title = "Export Cabrillo 3.0"
        panel.nameFieldStringValue = "\(currentStationCallsign)_\(session.contestID).log"
        panel.allowedContentTypes = [UTType(filenameExtension: "log") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            contestStatus = "Cabrillo exported: \(url.lastPathComponent)"
            appendLog("Exported Cabrillo 3.0 to \(url.lastPathComponent).")
            playActivitySound(.success)
        } catch {
            contestStatus = error.localizedDescription
            playActivitySound(.failure)
        }
    }

    private func ingestWSJTXEvents(_ events: [WSJTXLoggedEvent]) {
        let existing = Dictionary(uniqueKeysWithValues: wsjtxPendingQSOs.map { ($0.id, $0) })
        wsjtxPendingQSOs = events.prefix(50).compactMap { event in
            if var pending = existing[event.id] {
                let candidate = QSORecordModel(index: qsoRecords.count + 1, fields: pending.fields)
                pending.isDuplicate = qsoRecords.contains { $0.uniqueKey == candidate.uniqueKey }
                return pending
            }

            let parsed = parseADIF(content: event.adif)
            guard var fields = parsed.records.first else { return nil }
            fields["APP_YAAM_SOURCE"] = event.sourceID.isEmpty ? "WSJT-X" : event.sourceID
            if (fields["BAND"] ?? "").isEmpty,
               let frequency = fields["FREQ"],
               let band = AmateurBandPlan.band(for: frequency) {
                fields["BAND"] = band
            }
            let candidate = QSORecordModel(index: qsoRecords.count + 1, fields: fields)
            return WSJTXPendingQSO(
                id: event.id,
                sourceID: event.sourceID.isEmpty ? "WSJT-X" : event.sourceID,
                fields: fields,
                receivedAt: event.receivedAt,
                isDuplicate: qsoRecords.contains { $0.uniqueKey == candidate.uniqueKey }
            )
        }
    }

    private func removeWSJTXPendingQSO(id: UUID) {
        wsjtxPendingQSOs.removeAll { $0.id == id }
        wsjtxListener.removeLoggedEvent(id: id)
    }

    private func quickLogDraft(from pending: WSJTXPendingQSO) -> QuickLogDraft {
        let fields = pending.fields
        let rawMode = fields["SUBMODE"].isEmptyOrNil ? (fields["MODE"] ?? "") : (fields["SUBMODE"] ?? "")
        let mapped = mappedADIFMode(rawMode)
        var draft = QuickLogDraft()
        draft.callsign = fields["CALL"] ?? ""
        draft.frequencyMHz = fields["FREQ"] ?? ""
        draft.band = fields["BAND"] ?? AmateurBandPlan.band(for: draft.frequencyMHz) ?? ""
        draft.mode = mapped.mode
        draft.submode = mapped.submode
        draft.startedAt = contestRecordDate(fields) ?? pending.receivedAt
        draft.rstSent = fields["RST_SENT"] ?? AmateurBandPlan.defaultRST(for: mapped.mode)
        draft.rstReceived = fields["RST_RCVD"] ?? AmateurBandPlan.defaultRST(for: mapped.mode)
        draft.name = fields["NAME"] ?? ""
        draft.qth = fields["QTH"] ?? ""
        draft.grid = fields["GRIDSQUARE"] ?? fields["GRID"] ?? ""
        draft.country = fields["COUNTRY"] ?? ""
        draft.dxcc = fields["DXCC"] ?? ""
        draft.cqZone = fields["CQZ"] ?? ""
        draft.ituZone = fields["ITUZ"] ?? ""
        draft.comment = fields["COMMENT"] ?? ""
        draft.receivedExchange = fields["SRX_STRING"] ?? fields["SRX"] ?? ""
        draft.source = pending.sourceID
        return draft
    }

    private func mappedADIFMode(_ rawMode: String) -> (mode: String, submode: String) {
        let mode = rawMode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch mode {
        case "USB", "LSB", "PHONE": return ("SSB", "")
        case "FT8", "FT4", "JT65", "JT9", "Q65": return ("MFSK", mode)
        case "DATA", "DATA-U", "DATA-L", "PKTUSB", "PKTLSB": return ("DIGI", "")
        case "": return ("SSB", "")
        default: return (mode, "")
        }
    }

    private func contestRecordDate(_ fields: [String: String]) -> Date? {
        let date = (fields["QSO_DATE"] ?? "").filter(\.isNumber)
        var time = (fields["TIME_ON"] ?? "").filter(\.isNumber)
        while time.count < 6 { time.append("0") }
        guard date.count == 8 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.date(from: date + String(time.prefix(6)))
    }

    private func persistContestSession() {
        guard let session = currentContestSession,
              let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: contestSessionDefaultsKey)
    }
}

private extension Optional where Wrapped == String {
    var isEmptyOrNil: Bool { self?.isEmpty != false }
}
