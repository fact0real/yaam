import Foundation

@main
struct QSLGraylistRegression {
    static func qso(_ call: String = "DL1TEST", date: String = "20260101", time: String = "120000",
                    extra: [String: String] = [:]) -> QSORecordModel {
        QSORecordModel(fields: ["CALL": call, "QSO_DATE": date, "TIME_ON": time,
                               "BAND": "20M", "MODE": "FT8", "COUNTRY": "Testland"].merging(extra) { _, new in new })
    }
    static let profile = UUID()
    static func index(_ records: [QSORecordModel]) -> QSLGraylistIndex {
        QSLGraylistIndex(records: records, profileID: profile)
    }
    static func history(_ call: String = "DL1TEST") -> [QSORecordModel] {
        [qso(call), qso(call, time: "120100"), qso(call, time: "120200")]
    }

    @MainActor static func main() async throws {
        let old = history()
        precondition(index(Array(old.prefix(2))).entries.isEmpty)
        precondition(index(old).entries.count == 1)
        precondition(index([old[0], old[0], qso()]).entries.isEmpty)
        precondition(index(old + old).entries[0].contactCount == 3)
        let shortTime = qso(time: "1200")
        precondition(index(old + [shortTime]).entries[0].contactCount == 3)
        let normalized = [qso(" dl1test "), old[1], old[2]]
        precondition(index(normalized).entry(for: " Dl1Test ")?.contactCount == 3)
        precondition(index(old + history("DL1TEST/P")).entries.count == 2)

        for field in ["LOTW_QSL_RCVD", "QRZLOG_QSL_RCVD", "QRZCOM_QSL_RCVD", "APP_QRZLOG_STATUS", "EQSL_QSL_RCVD", "QSL_RCVD"] {
            for value in ["Y", "v", " C ", "CONFIRMED", "verified"] {
                precondition(index(old + [qso(extra: [field: value])]).entries.isEmpty, "Missed received QSL \(field)=\(value)")
            }
        }
        // A confirmation with incomplete identity still disproves zero confirmations.
        precondition(index(old + [qso(time: "", extra: ["QSL_RCVD": "Y"])]).entries.isEmpty)
        let sent = old.enumerated().map { i, _ in qso(time: "120\(i)00", extra: ["LOTW_QSL_SENT": "Y"]) }
        precondition(index(sent).entries[0].sentCount == 3)
        precondition(index(old + [qso(extra: ["QSL_SENT": "Y"])]).entries[0].sentCount == 1)
        precondition(index(old + [qso(extra: ["QSL_RCVD": "R"])]).entries.count == 1)
        let foreign = history().map { record in
            var record = record; record.fields["APP_YAAM_STATION_PROFILE_ID"] = UUID().uuidString; return record
        }
        precondition(index(foreign).entries.isEmpty)
        precondition(index(old + foreign).entries[0].contactCount == 3)
        let foreignConfirmed = qso(extra: ["APP_YAAM_STATION_PROFILE_ID": UUID().uuidString, "QSL_RCVD": "Y"])
        precondition(index(old + [foreignConfirmed]).entries.count == 1)

        let start = ISO8601DateFormatter().date(from: "2026-01-01T12:02:00Z")!
        let boundary = start.addingTimeInterval(90 * 86400)
        let entry = index(old).entries[0]
        precondition(entry.dates.count == 3)
        precondition(!entry.isMature(waitingDays: 90, now: boundary.addingTimeInterval(-1)))
        precondition(entry.isMature(waitingDays: 90, now: boundary))
        precondition(index(old + [qso(date: "20261024")]).entries[0].isMature(waitingDays: 90, now: boundary))
        precondition(!entry.isMature(waitingDays: 0, now: start.addingTimeInterval(-86400)))
        let invalid = [qso(date: "20260230"), qso(date: "20260230", time: "120100"), qso(date: "20260230", time: "120200")]
        precondition(index(invalid).entries[0].dates.isEmpty)
        precondition(!index(invalid).entries[0].isMature(waitingDays: 0, now: boundary))
        precondition(index([qso(time: ""), qso(time: ""), qso(time: "")]).entries.isEmpty)
        precondition(index(old + [qso(time: "")]).entries[0].unresolvedCount == 1)
        precondition(index(Array(old.dropLast())).entries.isEmpty, "Deletion must remove qualification")

        // One very frequently worked call must not cause quadratic dictionary/set copying.
        let large = (0..<30_000).map { second in
            qso("G1LOAD", time: String(format: "%02d%02d%02d", second / 3600, second % 3600 / 60, second % 60))
        }
        let started = Date()
        precondition(index(large).entries.first?.contactCount == 30_000)
        print("Aggregated 30,000 distinct contacts for one callsign in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")

        let suite = "QSLGraylistRegression.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QSLGraylistStore(defaults: defaults)
        store.reset(profileID: profile)
        precondition(store.waitingDays == 90 && !store.reducesPriority)
        store.schedule(records: old, profileID: profile)
        try await wait(store)
        precondition(store.index.entries.count == 1)
        let stableIndex = store.index
        var metadataOnly = old
        metadataOnly[0].fields["EMAIL"] = "operator@example.org"
        metadataOnly[0].fields["APP_YAAM_LAST_EMAIL"] = "Updated in background"
        store.schedule(records: metadataOnly, profileID: profile)
        precondition(!store.isLoading && store.index == stableIndex,
                     "Email enrichment/history must not empty or rebuild the graylist")
        store.schedule(records: old, profileID: profile)
        precondition(!store.isLoading, "Identical evidence must not restart the worker")
        store.setWaitingDays(0)
        store.setReducesPriority(true)
        precondition(store.reducedCallsigns == ["DL1TEST"])
        store.setException(true, callsign: " dl1test ")
        precondition(store.reducedCallsigns.isEmpty)
        store.setException(false, callsign: "DL1TEST")
        precondition(store.reducedCallsigns == ["DL1TEST"])

        // Real roster ordering, existing entries and Apex update immediately on policy changes.
        let roster = DigitalCallRosterEngine.shared
        roster.clearRoster()
        roster.updateStationContext(callsign: "MY1CALL", grid: "")
        roster.processDecodes([WSJTXLiveDecode(callerCallsign: "DL1TEST", snr: 20),
                               WSJTXLiveDecode(callerCallsign: "OK1TEST", snr: -20)], activeBand: "20M", isSimulation: true)
        precondition(roster.entries.first?.callsign == "OK1TEST")
        precondition(roster.apexTarget?.callsign == "OK1TEST")
        precondition(roster.entries.first { $0.callsign == "DL1TEST" }?.isQSLPriorityReduced == true)
        store.setReducesPriority(false)
        precondition(roster.entries.first?.callsign == "DL1TEST")
        store.setReducesPriority(true)
        roster.processDecodes([WSJTXLiveDecode(callerCallsign: "DL1TEST", targetCallsign: "MY1CALL", message: "MY1CALL DL1TEST", isCQ: false)], activeBand: "20M", isSimulation: true)
        precondition(roster.entries.first?.callsign == "DL1TEST" && roster.entries.first?.isQSLPriorityReduced == false)
        precondition(roster.apexTarget?.callsign == "DL1TEST")

        // Invalidating evidence clears the old penalty immediately, before the worker completes.
        store.schedule(records: old + [qso(extra: ["QSL_RCVD": "Y"])], profileID: profile)
        precondition(store.reducedCallsigns.isEmpty)
        precondition(store.index == stableIndex && store.isLoading,
                     "Keep table rows stable during an update while suspending stale penalties")
        try await wait(store)
        precondition(store.index.entries.isEmpty)
        store.schedule(records: old, profileID: profile)
        store.setException(true, callsign: "DL1TEST")
        store.reset(profileID: UUID())
        try await Task.sleep(for: .milliseconds(400))
        precondition(store.index.entries.isEmpty && !store.hasWorkspace && !store.reducesPriority)
        store.reset(profileID: profile)
        precondition(store.waitingDays == 0 && store.reducesPriority && store.exceptions.contains("DL1TEST"))
        store.setException(false, callsign: "DL1TEST")
        store.schedule(records: old, profileID: profile)
        store.schedule(records: [], profileID: profile)
        try await wait(store)
        precondition(store.index.entries.isEmpty, "Superseded worker must not republish old history")

        // A background metadata change during a pending update must not supersede it.
        store.schedule(records: old, profileID: profile)
        store.schedule(records: metadataOnly, profileID: profile)
        try await wait(store)
        precondition(store.index == stableIndex)

        // Email batches preserve visible scope, exact callsigns, profile ownership and
        // all distinct QSOs even when only one duplicate contains an email address.
        var emailCopy = old[0]
        emailCopy.fields["EMAIL"] = "operator@example.org"
        let mailRecords = old + [emailCopy] + history("DL1TEST/P") + foreign + history("OTHER1")
        let mailIndex = index(mailRecords)
        let visible = [mailIndex.entry(for: "DL1TEST")!, mailIndex.entry(for: "DL1TEST/P")!]
        let recipients = QSLGraylistMail.recipients(entries: visible + visible, records: mailRecords, profileID: profile)
        precondition(recipients.count == 2)
        precondition(recipients[0].id == "DL1TEST" && recipients[0].records.count == 3)
        precondition(recipients[0].email == "operator@example.org")
        precondition(recipients[1].id == "DL1TEST/P" && recipients[1].email.isEmpty,
                     "Missing email remains visible for lookup/manual entry")
        precondition(recipients.allSatisfy { $0.records.allSatisfy { $0.fields["APP_YAAM_STATION_PROFILE_ID"] == nil } })
        let confirmedMail = old.map { record in
            var record = record; record.fields["QSL_RCVD"] = "Y"; return record
        }
        precondition(QSLGraylistMail.recipients(entries: visible, records: confirmedMail, profileID: profile).isEmpty)
        precondition(QSLGraylistMail.isUsableEmail(" operator@example.org "))
        for invalid in ["", "bad", "a@.org", "a@b.org\nBcc: hidden@example.org", "a@b.org,c@d.org", "-a@b.org"] {
            precondition(!QSLGraylistMail.isUsableEmail(invalid))
        }

        let app = AppState(defaults: defaults)
        app.activeStationProfileID = profile
        app.loadedWorkspaceProfileID = profile
        app.qsoRecords = old
        app.refreshQSLGraylist()
        try await wait(app.qslGraylist)
        let inspected = app.qslGraylist.index.entries[0]
        app.openQSLGraylistContacts(inspected)
        precondition(app.searchText == "DL1TEST" && app.logSearchMode == .callsign && app.selectedTab == 0)
        precondition(app.selectedRecordIDs == Set(old.map(\.id)))
        app.isMasterMode = false
        app.refreshQSLGraylist()
        precondition(!app.qslGraylist.hasWorkspace && app.qslGraylist.index.entries.isEmpty)
        app.selectedTab = 5
        app.openQSLGraylistContacts(inspected)
        precondition(app.selectedTab == 5, "A stale row from another workspace must not open contacts")
        app.isMasterMode = true
        app.activeStationProfileID = UUID()
        app.refreshQSLGraylist()
        precondition(!app.qslGraylist.hasWorkspace, "A failed/incomplete profile load must not classify old records")
        roster.clearRoster()
        precondition(roster.apexTarget == nil)
        print("PASS QSL graylist: distinct identity, all received-QSL sources, sent-only, profile scoping, UTC wait boundaries, invalid dates, lifecycle races, preferences, exceptions, actual roster/Apex priority and direct calls")
    }

    @MainActor static func wait(_ store: QSLGraylistStore) async throws {
        for _ in 0..<200 {
            if !store.isLoading { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        fatalError("Graylist worker did not finish")
    }
}
