//
//  QSLSyncAllRegression.swift
//  YAAM
//
//  Sync All and Sync Selected (patch 43), run with the same logic the app runs: which services are used, when a QSO
//  is already at a service, what the queue plans (enqueueQSL uses QSLSyncAll.plannedUploads), how each job is looked
//  at again before it is sent (QSLSyncAll.review), how each service's batches go (QSLProviderPass, with the answers a
//  service gives), the report, the ADIF that is sent, and the marks a QSO gets when a service accepts it, from the
//  QSL Hub or from the Zero-Click daemon.
//  Run from the repository root:
//    swiftc -parse-as-library Tests/QSLSyncAllRegression.swift YAAM/QSLSyncAll.swift YAAM/QSLHub.swift \
//      YAAM/ADIFParser.swift YAAM/FormURLEncoding.swift YAAM/QSOMetadataFormatter.swift YAAM/OperatorModels.swift \
//      YAAM/AmateurBandSettings.swift YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift \
//      YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift -o qsa && ./qsa
//  No network: nothing is uploaded or downloaded. Where a service would answer, the test gives the answer (a
//  QSLBatchOutcome, or the text of a QRZ reply) and applies acceptedFields as an accepting service would. TQSL and
//  the QSO record are the small stand-ins below. The parts that do not build on their own (AppState, the views, the
//  sync engine and the daemon) are checked in their source.
//

import Foundation

// Stand-in for the QSO record of AppState.swift, which the band plan in OperatorModels.swift reads.
nonisolated struct QSORecordModel {
    var fields: [String: String] = [:]
    var isConfirmed = false
    subscript(key: String) -> String { fields[key] ?? "" }
}

// Stand-in for YAAM/TQSLCoordinator.swift, which runs the TQSL program; this test never uploads.
actor TQSLCoordinator {
    static let shared = TQSLCoordinator()
    func execute(
        adifContent: String? = nil,
        adifFileURL: URL? = nil,
        stationLocation: String? = nil,
        certificatePassword: String? = nil,
        customExecutablePath: String? = nil,
        securityBookmark: Data? = nil,
        timeoutSeconds: TimeInterval = 45.0
    ) async -> (success: Bool, message: String) { (false, "TQSL is not run in this test") }
}

@main
@MainActor
struct QSLSyncAllRegression {
    static var passed = 0
    static var failed = 0

    static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            passed += 1
            print("PASS \(name)")
        } else {
            failed += 1
            print("FAIL \(name)" + (detail.isEmpty ? "" : "   [\(detail)]"))
        }
    }

    static func source(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }

    static func job(_ qsoID: UUID, _ provider: QSLProvider, _ state: QSLQueueState = .queued, adif: String = "") -> QSLQueueJob {
        QSLQueueJob(stationProfileID: UUID(), qsoID: qsoID, provider: provider, adif: adif, state: state)
    }

    static func main() {
        let now = Date(timeIntervalSince1970: 1_791_590_400) // 2026-10-10 00:00 UTC

        // ---- R6 · the services: switched on in the Station Workspace, and with their upload credentials
        var full = QSLServiceCredentials()
        full.qrzAPIKey = "test-key"
        full.eqslUsername = "EA3JIC"
        full.eqslPassword = "test"
        full.clubLogEmail = "test-login"
        full.clubLogPassword = "test"
        full.clubLogCallsign = "EA3JIC"
        full.clubLogAPIKey = "test"
        full.lotwCallsign = "EA3JIC"
        full.lotwStationLocation = "Home"
        check("with every upload credential and TQSL found, all four services are used",
              QSLSyncAll.configuredProviders(full, tqslFound: true) == Set(QSLProvider.allCases))
        let emptied: [(String, QSLProvider, (inout QSLServiceCredentials) -> Void)] = [
            ("QRZ API key", .qrz, { $0.qrzAPIKey = "" }),
            ("eQSL username", .eqsl, { $0.eqslUsername = "" }),
            ("eQSL password", .eqsl, { $0.eqslPassword = "" }),
            ("Club Log email", .clubLog, { $0.clubLogEmail = "" }),
            ("Club Log password", .clubLog, { $0.clubLogPassword = "" }),
            ("Club Log callsign", .clubLog, { $0.clubLogCallsign = "" }),
            ("Club Log API key", .clubLog, { $0.clubLogAPIKey = "" }),
            ("LoTW callsign", .lotw, { $0.lotwCallsign = "" }),
            ("LoTW station location", .lotw, { $0.lotwStationLocation = "" }),
        ]
        var credentialMisses: [String] = []
        for (name, provider, empty) in emptied {
            var credentials = full
            empty(&credentials)
            let used = QSLSyncAll.configuredProviders(credentials, tqslFound: true)
            if used.contains(provider) || used.count != 3 { credentialMisses.append(name) }
        }
        check("each upload credential, emptied on its own, leaves out its service and only it (9 cases)",
              credentialMisses.isEmpty, credentialMisses.joined(separator: ", "))
        check("LoTW is left out when TQSL is not found",
              QSLSyncAll.configuredProviders(full, tqslFound: false) == [.qrz, .eqsl, .clubLog])
        check("with no credentials, no service is used", QSLSyncAll.configuredProviders(QSLServiceCredentials(), tqslFound: true).isEmpty)
        check("the Station Workspace switches: never saved = all on; a saved list = those; an empty list = none",
              QSLSyncAll.switchedOn(stored: nil) == Set(QSLProvider.allCases) &&
              QSLSyncAll.switchedOn(stored: "qrz,clubLog") == [.qrz, .clubLog] &&
              QSLSyncAll.switchedOn(stored: "").isEmpty)
        let configured = QSLSyncAll.configuredProviders(full, tqslFound: true)
        let switchedOn = QSLSyncAll.switchedOn(stored: "qrz,clubLog,lotw")
        check("a service switched off is not checked, and says why; one with no credentials too",
              QSLSyncAll.notChecked(.eqsl, configured: configured, switchedOn: switchedOn) == "switched off in the Station Workspace" &&
              QSLSyncAll.notChecked(.qrz, configured: [.clubLog], switchedOn: switchedOn) == "no upload credentials" &&
              QSLSyncAll.notChecked(.qrz, configured: configured, switchedOn: switchedOn) == nil)

        // ---- R1, R2 · when a QSO is already at a service, and when it is pending
        var sentMisses: [String] = []
        for provider in QSLProvider.allCases {
            for value in ["Y", "V", "C", "CONFIRMED", " Y ", "y"] where !QSLUploadStatus.isSent([provider.sentField: value], to: provider) {
                sentMisses.append("\(provider.rawValue)=\(value)")
            }
        }
        check("Y, V, C and CONFIRMED in each service's sent field count as sent, also with spaces or in lower case",
              sentMisses.isEmpty, sentMisses.joined(separator: ", "))
        check("for Club Log, the ADIF field CLUBLOG_QSO_UPLOAD_STATUS counts as sent, as YAAM's own field does",
              QSLUploadStatus.isSent(["CLUBLOG_QSO_UPLOAD_STATUS": "Y"], to: .clubLog) &&
              QSLUploadStatus.isSent(["APP_YAAM_CLUBLOG_SENT": "Y"], to: .clubLog))
        check("a LoTW confirmation (LOTW_QSL_RCVD Y or V) means the QSO is at LoTW, and only at LoTW",
              QSLUploadStatus.isSent(["LOTW_QSL_RCVD": "Y"], to: .lotw) && QSLUploadStatus.isSent(["LOTW_QSL_RCVD": "V"], to: .lotw) &&
              !QSLUploadStatus.isSent(["LOTW_QSL_RCVD": "Y"], to: .qrz) && !QSLUploadStatus.isSent(["LOTW_QSL_RCVD": "Y"], to: .clubLog))
        check("a QRZ confirmation (QRZLOG_QSL_RCVD Y, or APP_QRZLOG_STATUS C or CONFIRMED) means the QSO is at QRZ",
              QSLUploadStatus.isSent(["QRZLOG_QSL_RCVD": "Y"], to: .qrz) && QSLUploadStatus.isSent(["APP_QRZLOG_STATUS": "C"], to: .qrz) &&
              QSLUploadStatus.isSent(["APP_QRZLOG_STATUS": "CONFIRMED"], to: .qrz))
        check("downloaded from QRZ (QRZCOM_QSO_DOWNLOAD_STATUS Y) or Lab599's APP_QRZLOG_STATUS UPLOADED: at QRZ, for QRZ only",
              QSLUploadStatus.isSent(["QRZCOM_QSO_DOWNLOAD_STATUS": "Y"], to: .qrz) && QSLUploadStatus.isSent(["APP_QRZLOG_STATUS": "UPLOADED"], to: .qrz) &&
              !QSLUploadStatus.isSent(["QRZCOM_QSO_DOWNLOAD_STATUS": "Y"], to: .clubLog) &&
              !QSLUploadStatus.isSent(["QRZCOM_QSO_DOWNLOAD_STATUS": "N"], to: .qrz))
        check("an eQSL confirmation does not count as sent to eQSL (the inbox also gets cards for QSOs never uploaded)",
              !QSLUploadStatus.isSent(["EQSL_QSL_RCVD": "Y"], to: .eqsl))
        var pendingMisses: [String] = []
        for provider in QSLProvider.allCases {
            for value in ["", "N", "R", "Q", "I", "M"] where !QSLSyncAll.needsUpload([provider.sentField: value], to: provider, jobState: nil) {
                pendingMisses.append("\(provider.rawValue)=\(value.isEmpty ? "empty" : value)")
            }
        }
        check("an empty sent field and N, R, Q, I or M are pending, for every service", pendingMisses.isEmpty, pendingMisses.joined(separator: ", "))
        let fromLoTW = ["CALL": "0E5FG", "QSO_DATE": "20261007", "TIME_ON": "1830", "BAND": "15m", "MODE": "FT8",
                        "QSL_RCVD": "Y", "APP_YAAM_REMOTE_CONFIRMATION_IMPORTED": "LOTW"]
        check("a QSO the LoTW download added is not sent back to LoTW, and still goes to Club Log",
              !QSLSyncAll.needsUpload(fromLoTW, to: .lotw, jobState: nil) && QSLSyncAll.needsUpload(fromLoTW, to: .clubLog, jobState: nil))

        // ---- the queue's own state: finished, being sent, stopped (R9, R15)
        let fresh = ["CALL": "0A1BCD"]
        check("a job finished or being sent is not queued again",
              !QSLSyncAll.needsUpload(fresh, to: .qrz, jobState: .succeeded) && !QSLSyncAll.needsUpload(fresh, to: .qrz, jobState: .uploading))
        check("a stopped job (blocked, or failed five times) is not queued again by Sync, but is by the QSO's own Upload button",
              !QSLSyncAll.needsUpload(fresh, to: .qrz, jobState: .blocked) && !QSLSyncAll.needsUpload(fresh, to: .qrz, jobState: .failed) &&
              QSLSyncAll.needsUpload(fresh, to: .qrz, jobState: .blocked, retryStopped: true) &&
              QSLSyncAll.needsUpload(fresh, to: .qrz, jobState: .failed, retryStopped: true))
        check("a job queued or waiting to retry is queued again",
              [QSLQueueState.queued, .retry].allSatisfy { QSLSyncAll.needsUpload(fresh, to: .qrz, jobState: $0) })
        let blockedOld = QSLQueueJob(stationProfileID: UUID(), qsoID: UUID(), provider: .qrz, adif: "", state: .blocked,
                                     updatedAt: now.addingTimeInterval(-3_600))
        let blockedClubLog = QSLQueueJob(stationProfileID: UUID(), qsoID: UUID(), provider: .clubLog, adif: "", state: .blocked,
                                         updatedAt: now.addingTimeInterval(-3_600))
        let unblocked = QSLSyncAll.unblockedJobKeys([blockedOld, blockedClubLog], credentialsChangedAt: [.qrz: now, .clubLog: now.addingTimeInterval(-7_200)])
        check("a job blocked before its service's credentials were saved again is unblocked; one blocked after, not",
              unblocked == [QSLSyncAll.jobKey(blockedOld.qsoID, .qrz)])

        // ---- the plan of the queue (enqueueQSL), over a log: never sent; sent to QRZ only; imported as sent to
        // Club Log; sent to Club Log by YAAM; a finished QRZ job
        let imported = parseADIF(content: """
            <ADIF_VER:5>3.1.7<EOH>
            <CALL:6>0B2CDE<QSO_DATE:8>20261009<TIME_ON:4>1201<BAND:3>20m<MODE:3>FT8<CLUBLOG_QSO_UPLOAD_STATUS:1>Y<EOR>
            """).records.first ?? [:]
        let q1 = UUID(), q2 = UUID(), q3 = UUID(), q4 = UUID(), q5 = UUID()
        var log: [(id: UUID, fields: [String: String])] = [
            (q1, ["CALL": "EP2AES", "QSO_DATE": "20261009", "TIME_ON": "1200", "BAND": "20m", "MODE": "FT8"]),
            (q2, ["CALL": "0A1BCD", "QSO_DATE": "20261009", "TIME_ON": "1205", "BAND": "20m", "MODE": "FT8",
                  "QRZCOM_QSO_UPLOAD_STATUS": "Y"]),
            (q3, imported),
            (q4, ["CALL": "0C3DE", "QSO_DATE": "20261009", "TIME_ON": "1210", "BAND": "40m", "MODE": "CW",
                  "APP_YAAM_CLUBLOG_SENT": "Y"]),
            (q5, ["CALL": "0D4EF", "QSO_DATE": "20261009", "TIME_ON": "1215", "BAND": "40m", "MODE": "CW"]),
        ]
        let jobStates = [QSLSyncAll.jobKey(q5, .qrz): QSLQueueState.succeeded]
        let plan = QSLSyncAll.plannedUploads(records: log, providers: [.qrz, .clubLog], jobStates: jobStates)
        check("the import keeps CLUBLOG_QSO_UPLOAD_STATUS", imported["CLUBLOG_QSO_UPLOAD_STATUS"] == "Y")
        check("the plan for QRZ has only the QSOs not at QRZ (not the one sent, not the one with a finished job)",
              Set(plan[.qrz] ?? []) == [q1, q3, q4], "\(plan[.qrz]?.count ?? 0) planned")
        check("the plan for Club Log has only the QSOs not at Club Log (not the imported one, not YAAM's)",
              Set(plan[.clubLog] ?? []) == [q1, q2, q5], "\(plan[.clubLog]?.count ?? 0) planned")
        check("nothing is planned for a service that is not used", plan[.eqsl] == nil && plan[.lotw] == nil)
        let allSent = parseADIF(content: """
            <ADIF_VER:5>3.1.7<EOH>
            <CALL:6>EP2AES<QSO_DATE:8>20261008<TIME_ON:4>0900<BAND:3>17m<MODE:3>SSB<LOTW_QSL_SENT:1>Y<QRZCOM_QSO_UPLOAD_STATUS:1>Y<CLUBLOG_QSO_UPLOAD_STATUS:1>Y<EQSL_QSL_SENT:1>Y<EOR>
            """).records.first ?? [:]
        check("the import keeps LOTW_QSL_SENT, QRZCOM_QSO_UPLOAD_STATUS, CLUBLOG_QSO_UPLOAD_STATUS and EQSL_QSL_SENT, and such a QSO is planned for none",
              ["LOTW_QSL_SENT", "QRZCOM_QSO_UPLOAD_STATUS", "CLUBLOG_QSO_UPLOAD_STATUS", "EQSL_QSL_SENT"].allSatisfy { allSent[$0] == "Y" } &&
              QSLProvider.allCases.allSatisfy { !QSLSyncAll.needsUpload(allSent, to: $0, jobState: nil) })

        // ---- R7 · Sync Selected: only the selected QSOs get jobs, and only their jobs are sent
        let selectedRecords = QSLSyncAll.recordsToSync(all: log, selectedIDs: [q1, q5])
        let selectedPlan = QSLSyncAll.plannedUploads(records: selectedRecords, providers: [.qrz, .clubLog], jobStates: jobStates)
        let plannedIDs = Set(selectedPlan.values.flatMap { $0 })
        check("Sync Selected takes the selected QSOs only, and the unselected ones (also not sent) get no job",
              Set(selectedRecords.map(\.id)) == [q1, q5] && plannedIDs == [q1, q5] && !plannedIDs.contains(q2) && !plannedIDs.contains(q3),
              "\(plannedIDs.count) QSOs planned")
        check("Sync All takes every QSO", QSLSyncAll.recordsToSync(all: log, selectedIDs: nil).count == log.count)
        let waiting = [job(q1, .qrz), job(q2, .clubLog), job(q5, .clubLog), job(q4, .eqsl)]
        let selectedDue = QSLSyncAll.dueJobs(waiting, now: now, providers: [.qrz, .clubLog], qsoIDs: [q1, q5])
        check("Sync Selected sends only the selected QSOs' jobs, for the services it uses",
              Set(selectedDue.map(\.qsoID)) == [q1, q5] && !selectedDue.contains { $0.provider == .eqsl })
        check("Sync All sends only the jobs of the services it uses; the QSL Hub's own buttons send them all",
              !QSLSyncAll.dueJobs(waiting, now: now, providers: [.qrz, .clubLog]).contains { $0.provider == .eqsl } &&
              QSLSyncAll.dueJobs(waiting, now: now).count == 4)

        // ---- the job is looked at again just before it is sent, with the QSO as it is now (R11 for the ADIF)
        let stale = job(q1, .qrz, adif: "<CALL:6>EP2AES<BAND:3>40m<EOR>")
        check("a job whose QSO is no longer in the log is dropped", QSLSyncAll.review(stale, currentFields: nil) == .qsoGone)
        check("a job whose QSO is now at the service is not sent",
              QSLSyncAll.review(stale, currentFields: ["CALL": "EP2AES", "QRZLOG_QSL_RCVD": "Y"]) == .alreadyThere)
        let current = ["CALL": "EP2AES", "BAND": "20m", "MODE": "FT8", "QSL_MEDIA_PATH": "/local/eqsl/card.jpg",
                       "QRZ_URL": "https://www.qrz.com/db/EP2AES", "APP_YAAM_STATION_PROFILE_ID": "local", "RANK_QSO": "12",
                       "APP_SDR_CONTROL_ID": "7"]
        var sentADIF = ""
        if case .send(let adif) = QSLSyncAll.review(stale, currentFields: current) { sentADIF = adif }
        check("a job is sent with the QSO's current fields, not the ones it was queued with",
              sentADIF.contains("<BAND:3>20m") && !sentADIF.contains("40m"), sentADIF)
        let builtADIF = QSLUploadStatus.uploadADIF(current, for: .qrz)
        check("the ADIF sent to a service has no local path, QRZ page link or APP_YAAM_ field",
              [sentADIF, builtADIF].allSatisfy { adif in
                  !adif.contains("QSL_MEDIA_PATH") && !adif.contains("/local/") && !adif.contains("QRZ_URL") &&
                      !adif.contains("APP_YAAM_") && !adif.contains("RANK_QSO") && !adif.contains("APP_SDR_CONTROL_ID") &&
                      adif.contains("<CALL:6>EP2AES")
              } && builtADIF.contains("<BAND:3>20m"), builtADIF)
        let localNames = ["QSL_MEDIA_PATH", "QRZ_URL", "RANK_QSO", "RANK_BAND", "RANK_DXCC", "APP_SDR_CONTROL_IMPORTED",
                          "APP_SDR_CONTROL_ID", "APP_SDR_CONTROL_CONFIRMED", "APP_YAAM_CLUBLOG_SENT"]
        let kept = QSLUploadStatus.serviceFields(current.merging(Dictionary(uniqueKeysWithValues: localNames.map { ($0, "x") })) { $1 })
        check("each local-only field is left out of what goes to a service, and the others stay (EMAIL and MY_ fields too)",
              localNames.allSatisfy { QSLUploadStatus.isLocalOnly($0) && kept[$0] == nil } &&
              !QSLUploadStatus.isLocalOnly("CALL") && !QSLUploadStatus.isLocalOnly("EMAIL") && !QSLUploadStatus.isLocalOnly("MY_GRIDSQUARE") &&
              kept["CALL"] == "EP2AES" && kept["BAND"] == "20m")

        // ---- R3 · what a service answers: QRZ duplicates
        let duplicateReplies = ["RESULT=FAIL&REASON=Unable to add QSO to database: duplicate&EXTENDED=",
                                "RESULT=FAIL&REASON=DUPLICATE", "result=fail&reason=Duplicate"]
        check("a QRZ reply that says duplicate, in any case, is an accepted upload",
              duplicateReplies.allSatisfy { QSLUploadStatus.qrzReply($0).accepted && QSLUploadStatus.qrzReply($0).duplicate })
        check("a QRZ reply RESULT=OK is accepted; RESULT=AUTH, or a reason naming the API key, is a credential rejection",
              QSLUploadStatus.qrzReply("RESULT=OK&LOGID=1").accepted &&
              !QSLUploadStatus.qrzReply("RESULT=AUTH&REASON=invalid api key").accepted &&
              QSLUploadStatus.qrzReply("RESULT=AUTH&REASON=invalid api key").authenticationFailure &&
              QSLUploadStatus.qrzReply("RESULT=FAIL&REASON=Invalid API Key").authenticationFailure &&
              QSLUploadStatus.qrzReply("RESULT=FAIL&REASON=authentication failed").authenticationFailure &&
              QSLUploadStatus.qrzReply("RESULT=FAIL&REASON=Unauthorized").authenticationFailure)
        let perQSO = ["RESULT=FAIL&REASON=invalid band", "RESULT=FAIL&REASON=invalid date", "RESULT=FAIL&REASON=missing call"]
        check("a QRZ failure about the QSO (invalid band, invalid date) is neither accepted nor a credential rejection",
              perQSO.allSatisfy { !QSLUploadStatus.qrzReply($0).accepted && !QSLUploadStatus.qrzReply($0).authenticationFailure })
        let duplicate = QSLUploadStatus.qrzReply(duplicateReplies[0])
        var qrzPass = QSLProviderPass(provider: .qrz, jobs: [job(q1, .qrz)])
        let duplicateUpdates = qrzPass.record(
            QSLBatchOutcome(accepted: duplicate.accepted, alreadyAtService: duplicate.duplicate,
                            authenticationFailure: duplicate.authenticationFailure, message: "Already in QRZ Logbook"),
            for: qrzPass.nextBatch() ?? [], now: now)
        check("a QRZ duplicate finishes the job and marks the QSO, counted as already there",
              duplicateUpdates.count == 1 && duplicateUpdates[0].job.state == .succeeded && duplicateUpdates[0].markSent &&
              qrzPass.summary.alreadyThere == 1 && qrzPass.summary.sent == 0)
        // ---- R9 · a service that rejects the credentials is stopped for the run
        let qrzJobs = (0..<5).map { _ in job(UUID(), .qrz) }
        var rejected = QSLProviderPass(provider: .qrz, jobs: qrzJobs)
        var requests = 0
        var rejectedUpdates: [QSLJobUpdate] = []
        while let batch = rejected.nextBatch() {
            requests += 1
            rejectedUpdates += rejected.record(QSLBatchOutcome(accepted: false, authenticationFailure: true, message: "QRZ rejected the API key"),
                                               for: batch, now: now)
        }
        rejectedUpdates += rejected.finish(now: now)
        check("a refused key costs one request: that job is blocked, the other four are not sent and stay pending for the next Sync",
              requests == 1 && rejectedUpdates.count == 5 && rejectedUpdates[0].job.state == .blocked &&
              rejectedUpdates.dropFirst().allSatisfy { $0.job.state == .retry && !$0.markSent } &&
              rejected.summary.blocked == 1 && rejected.summary.notSent == 4 &&
              rejected.summary.notSentReason == "stopped after the credentials were refused" &&
              rejectedUpdates.last?.job.message.contains("tried at the next Sync") == true,
              "\(requests) request(s), \(rejected.summary.blocked) blocked, \(rejected.summary.notSent) not sent")
        var flaky = QSLProviderPass(provider: .qrz, jobs: qrzJobs)
        var flakyRequests = 0
        while let batch = flaky.nextBatch() {
            flakyRequests += 1
            _ = flaky.record(QSLBatchOutcome(accepted: false, message: "HTTP 503"), for: batch, now: now)
        }
        let flakyRest = flaky.finish(now: now)
        check("after two failed requests in a row the service stops for the run, and the rest are not sent and stay pending",
              flakyRequests == 2 && flakyRest.count == 3 && flakyRest.allSatisfy { $0.job.state == .retry && $0.job.nextAttemptAt != nil } &&
              flaky.summary.notSent == 3 && flaky.summary.notSentReason == "stopped after two failed requests in a row",
              "\(flakyRequests) request(s)")
        var mixed = QSLProviderPass(provider: .qrz, jobs: qrzJobs)
        var mixedRequests = 0
        while let batch = mixed.nextBatch() {
            mixedRequests += 1
            _ = mixed.record(QSLBatchOutcome(accepted: mixedRequests % 2 == 0, message: "answer"), for: batch, now: now)
        }
        check("one failure between successes does not stop the service", mixedRequests == 5 && mixed.summary.sent == 2)

        // ---- R15 · the QSOs that never failed go first, so two that always fail cannot stop the others for good
        let bad1 = UUID(), bad2 = UUID()
        let healthy = (0..<3).map { _ in UUID() }
        var queue: [QSLQueueJob] = ([bad1, bad2] + healthy).enumerated().map { offset, id in
            QSLQueueJob(stationProfileID: UUID(), qsoID: id, provider: .qrz, adif: "", createdAt: now.addingTimeInterval(Double(offset)))
        }
        var sentHealthy = Set<UUID>()
        var afterFirstRun = Set<UUID>()
        var healthyPendingAfterFirstRun = false
        for run in 0..<2 {
            var pass = QSLProviderPass(provider: .qrz, jobs: QSLSyncAll.passOrder(queue.filter { $0.state == .queued || $0.state == .retry }))
            var updates: [QSLJobUpdate] = []
            while let batch = pass.nextBatch() {
                let good = batch.allSatisfy { healthy.contains($0.qsoID) }
                updates += pass.record(QSLBatchOutcome(accepted: good, message: good ? "OK" : "RESULT=FAIL&REASON=invalid band"), for: batch, now: now)
            }
            updates += pass.finish(now: now)
            for update in updates {
                if let index = queue.firstIndex(where: { $0.qsoID == update.job.qsoID }) { queue[index] = update.job }
                if update.markSent { sentHealthy.insert(update.job.qsoID) }
            }
            if run == 0 {
                afterFirstRun = sentHealthy
                healthyPendingAfterFirstRun = queue.filter { healthy.contains($0.qsoID) }.allSatisfy { $0.state == .retry }
            }
        }
        check("two QSOs that always fail, in front: the first run stops after them and sends none, the second sends all the others",
              afterFirstRun.isEmpty && healthyPendingAfterFirstRun && sentHealthy == Set(healthy), "\(sentHealthy.count) of \(healthy.count) sent")
        // eQSL.cc and Club Log: one bad QSO among 200 fails the whole request; at the next run the QSOs that already
        // failed go one by one, so the 199 good ones are sent.
        let badClubLog = UUID()
        var clubLogQueue = ([badClubLog] + (0..<199).map { _ in UUID() }).map { job($0, .clubLog) }
        var clubLogSent = Set<UUID>()
        var clubLogRequests: [[Int]] = []
        for _ in 0..<2 {
            var pass = QSLProviderPass(provider: .clubLog, jobs: QSLSyncAll.passOrder(clubLogQueue.filter { $0.state == .queued || $0.state == .retry }))
            var sizes: [Int] = []
            var updates: [QSLJobUpdate] = []
            while let batch = pass.nextBatch() {
                sizes.append(batch.count)
                let good = !batch.contains { $0.qsoID == badClubLog }
                updates += pass.record(QSLBatchOutcome(accepted: good, message: good ? "Accepted" : "Club Log returned HTTP 400"), for: batch, now: now)
            }
            updates += pass.finish(now: now)
            for update in updates {
                if let index = clubLogQueue.firstIndex(where: { $0.qsoID == update.job.qsoID }) { clubLogQueue[index] = update.job }
                if update.markSent { clubLogSent.insert(update.job.qsoID) }
            }
            clubLogRequests.append(sizes)
        }
        check("Club Log: one bad QSO fails the first request of 200; the second run sends them one by one and the 199 good ones go",
              clubLogRequests.first == [200] && clubLogRequests.last?.allSatisfy { $0 == 1 } == true &&
              clubLogSent.count == 199 && !clubLogSent.contains(badClubLog), "\(clubLogSent.count) sent")
        let mixedAttempts = [QSLQueueJob(stationProfileID: UUID(), qsoID: UUID(), provider: .eqsl, adif: ""),
                             QSLQueueJob(stationProfileID: UUID(), qsoID: UUID(), provider: .eqsl, adif: ""),
                             QSLQueueJob(stationProfileID: UUID(), qsoID: UUID(), provider: .eqsl, adif: "", attempts: 1)]
        let credentialRetries = ["Missing Club Log application password.",
                                 "Not sent: Club Log stopped after the credentials were refused; it will be tried at the next Sync",
                                 "Club Log rejected the credentials. Create and use an application password.",
                                 "The request timed out."].map { message in
            QSLQueueJob(stationProfileID: UUID(), qsoID: UUID(), provider: .clubLog,
                        adif: "", state: .retry, attempts: 2, message: message)
        }
        check("Club Log credential and transport retries remain one batch, preserving attempt history",
              QSLProviderPass.requests(credentialRetries, provider: .clubLog).map(\.count) == [4] &&
              credentialRetries.allSatisfy { $0.attempts == 2 })
        check("requests: QRZ one QSO each, LoTW up to 200, eQSL.cc and Club Log up to 200 that never failed and the others one each",
              QSLProviderPass.requests(mixedAttempts, provider: .eqsl).map(\.count) == [2, 1] &&
              QSLProviderPass.requests(mixedAttempts.map { var j = $0; j.provider = .lotw; return j }, provider: .lotw).map(\.count) == [3] &&
              QSLProviderPass.requests(mixedAttempts, provider: .qrz).map(\.count) == [1, 1, 1])
        check("the order puts the jobs that never failed first, then the oldest",
              QSLSyncAll.passOrder([QSLQueueJob(stationProfileID: UUID(), qsoID: bad1, provider: .qrz, adif: "", attempts: 2, createdAt: now),
                                    QSLQueueJob(stationProfileID: UUID(), qsoID: bad2, provider: .qrz, adif: "", createdAt: now.addingTimeInterval(5)),
                                    QSLQueueJob(stationProfileID: UUID(), qsoID: healthy[0], provider: .qrz, adif: "", createdAt: now.addingTimeInterval(1))])
                .map(\.qsoID) == [healthy[0], bad2, bad1])
        var bigPass = QSLProviderPass(provider: .clubLog, jobs: (0..<450).map { _ in job(UUID(), .clubLog) })
        var bigBatches: [Int] = []
        var bigUpdates: [QSLJobUpdate] = []
        while let batch = bigPass.nextBatch() {
            bigBatches.append(batch.count)
            bigUpdates += bigPass.record(QSLBatchOutcome(accepted: true, message: "Accepted"), for: batch, now: now)
        }
        check("services other than QRZ take 200 QSOs per request", bigBatches == [200, 200, 50], "\(bigBatches)")
        check("an accepted batch finishes every job of it and marks every QSO of it",
              bigUpdates.count == 450 && bigUpdates.allSatisfy { $0.job.state == .succeeded && $0.markSent } && bigPass.summary.sent == 450)

        // ---- R10 · the report and the last line of Sync All (QSLSyncReport.finalLine, which the sync engine calls)
        let clean = QSLSyncUploadRun(summaries: [QSLPassSummary(provider: .qrz, sent: 3)])
        let cleanEnd = QSLSyncReport.finalLine(upload: clean, downloadProblems: [], downloadsNotChecked: [], updated: 2)
        check("a run with nothing wrong says done, and the last line says successfully",
              QSLSyncReport.status(clean).hasPrefix("Uploads done") && cleanEnd.complete && !cleanEnd.problems &&
              cleanEnd.text.contains("successfully") && QSLSyncReport.lines(clean).contains { $0.text.hasPrefix("QRZ Logbook: 3 uploaded") })
        let blockedRun = QSLSyncUploadRun(summaries: [rejected.summary])
        let blockedEnd = QSLSyncReport.finalLine(upload: blockedRun, downloadProblems: [], downloadsNotChecked: [], updated: 0)
        check("a run with blocked jobs says problems, names the reason, and never says successfully",
              QSLSyncReport.status(blockedRun).contains("problems") && blockedEnd.problems && !blockedEnd.text.contains("successfully") &&
              QSLSyncReport.lines(blockedRun).contains { $0.problem && $0.text.contains("1 blocked") && $0.text.contains("API key") &&
                  $0.text.contains("4 not sent (stopped after the credentials were refused), will be tried at the next Sync") })
        let partial = QSLSyncUploadRun(summaries: [QSLPassSummary(provider: .qrz, sent: 3)], notChecked: [.eqsl: "switched off in the Station Workspace"])
        let partialEnd = QSLSyncReport.finalLine(upload: partial, downloadProblems: [], downloadsNotChecked: [], updated: 0)
        check("a run that left a service out names it, and the last line says not every service was checked",
              QSLSyncReport.lines(partial).contains { $0.text == "eQSL: not checked (switched off in the Station Workspace)" } &&
              !partialEnd.complete && !partialEnd.problems && partialEnd.text.contains("not every service was checked"))
        let busyEnd = QSLSyncReport.finalLine(upload: QSLSyncUploadRun(busy: true), downloadProblems: [], downloadsNotChecked: [], updated: 0)
        check("a run that found the queue busy did nothing and says so",
              QSLSyncReport.status(QSLSyncUploadRun(busy: true)).contains("nothing was done") && busyEnd.problems)
        var failedDownload = ConfirmationSyncSummary()
        failedDownload.lotwFailed = true
        failedDownload.lotwMessage = "LoTW synchronization failed"
        let downloadFailed = QSLSyncReport.downloadProblems(lotwQRZ: failedDownload, lotwOrQRZReady: true, otherErrors: 0)
        let downloadFailedEnd = QSLSyncReport.finalLine(upload: clean, downloadProblems: downloadFailed, downloadsNotChecked: [], updated: 0)
        check("a failed LoTW download is a problem, and the last line does not say successfully",
              downloadFailed.contains { $0.hasPrefix("LoTW download failed") } && downloadFailedEnd.problems && !downloadFailedEnd.text.contains("successfully"))
        check("a LoTW and QRZ download that did not run although ready (or did not report) is a problem; when neither is ready, it is not",
              !QSLSyncReport.downloadProblems(lotwQRZ: ConfirmationSyncSummary(), lotwOrQRZReady: true, otherErrors: 0).isEmpty &&
              !QSLSyncReport.downloadProblems(lotwQRZ: nil, lotwOrQRZReady: true, otherErrors: 0).isEmpty &&
              QSLSyncReport.downloadProblems(lotwQRZ: ConfirmationSyncSummary(), lotwOrQRZReady: false, otherErrors: 0).isEmpty &&
              !QSLSyncReport.downloadProblems(lotwQRZ: nil, lotwOrQRZReady: false, otherErrors: 1).isEmpty)
        let skipped = QSLSyncReport.downloadsNotChecked(lotwReady: true, qrzReady: true, eqslReady: false, clubLogReady: true)
        let skippedEnd = QSLSyncReport.finalLine(upload: clean, downloadProblems: [], downloadsNotChecked: skipped, updated: 0)
        check("a download that cannot run (eQSL.cc without credentials) is named, and the last line is not successfully",
              skipped.count == 1 && skipped[0].hasPrefix("eQSL.cc download") && !skippedEnd.complete && !skippedEnd.text.contains("successfully"))
        let qOld = UUID(), qSent = UUID(), qFailed = UUID()
        let earlier = [QSLQueueJob(stationProfileID: UUID(), qsoID: qOld, provider: .qrz, adif: "", state: .blocked),
                       QSLQueueJob(stationProfileID: UUID(), qsoID: qSent, provider: .qrz, adif: "", state: .blocked),
                       QSLQueueJob(stationProfileID: UUID(), qsoID: qFailed, provider: .clubLog, adif: "", state: .failed)]
        let earlierFields: [UUID: [String: String]] = [qOld: ["CALL": "0A1BCD"], qSent: ["CALL": "0C3DE", "QRZCOM_QSO_UPLOAD_STATUS": "Y"],
                                                       qFailed: ["CALL": "0D4EF"]]
        let leftover = QSLSyncAll.leftoverStopped(jobs: earlier, fieldsByID: earlierFields, providers: [.qrz, .clubLog])
        let withEarlier = QSLSyncReport.withPriorState([], providers: [.qrz, .clubLog], alreadyThere: [.qrz: 995], leftover: leftover)
        let earlierRun = QSLSyncUploadRun(summaries: withEarlier)
        let earlierEnd = QSLSyncReport.finalLine(upload: earlierRun, downloadProblems: [], downloadsNotChecked: [], updated: 0)
        check("jobs stopped by an earlier run are reported with the way out, and the run is not successful",
              leftover[.qrz]?.blocked == 1 && leftover[.clubLog]?.failed == 1 &&
              QSLSyncReport.lines(earlierRun).contains { $0.problem && $0.text.contains("995 already there") && $0.text.contains("1 blocked") &&
                  $0.text.contains("Retry Failed Uploads") } && earlierEnd.problems)
        var thisRun = QSLPassSummary(provider: .qrz, retry: 1, firstProblem: "HTTP 503")
        thisRun.alreadyThere = 0
        let combined = QSLSyncReport.withPriorState([thisRun], providers: [.qrz], alreadyThere: [:], leftover: leftover)
        check("with a problem in this run too, the line keeps both the run's message and the way out for the earlier ones",
              QSLSyncReport.lines(QSLSyncUploadRun(summaries: combined)).contains {
                  $0.text.contains("HTTP 503") && $0.text.contains("Retry Failed Uploads") && $0.text.contains("1 blocked")
              })
        let refused = QSLSyncUploadRun(notChecked: Dictionary(uniqueKeysWithValues: QSLProvider.allCases.map { ($0, "a Guest Log is open; open the master log") }))
        check("a Sync refused for every service says nothing was uploaded, and why, never \"Uploads done\"",
              QSLSyncReport.status(refused) == "Nothing uploaded: a Guest Log is open; open the master log" &&
              QSLSyncReport.status(QSLSyncUploadRun(notChecked: [.eqsl: "switched off in the Station Workspace"])).hasPrefix("Nothing uploaded; not checked"))
        check("a job unblocked by new credentials is not reported as stopped",
              QSLSyncAll.leftoverStopped(jobs: earlier, fieldsByID: earlierFields, providers: [.qrz],
                                         unblocked: [QSLSyncAll.jobKey(qOld, .qrz)])[.qrz] == nil)
        check("the QSOs already at a service are counted, so the line says how many were already there",
              QSLSyncAll.alreadyThereCounts(records: log, providers: [.qrz, .clubLog]) == [.qrz: 1, .clubLog: 2])

        // ---- R10 · the end of Sync All as the sync engine computes it (QSLSyncReport.downloadReadiness and endOfSync)
        var eqslSet = QSLServiceCredentials()
        eqslSet.eqslUsername = "EA3JIC"
        eqslSet.eqslPassword = "test"
        var clubLogSet = QSLServiceCredentials()
        clubLogSet.clubLogEmail = "test-login"
        clubLogSet.clubLogPassword = "test"
        clubLogSet.clubLogAPIKey = "test"
        let allReady = QSLSyncReport.downloadReadiness(lotwUsername: "EA3JIC", lotwPassword: "test", qrzAPIKey: "test-key",
                                                       eqsl: eqslSet, clubLog: clubLogSet)
        let noneReady = QSLSyncReport.downloadReadiness(lotwUsername: "  ", lotwPassword: "test", qrzAPIKey: "",
                                                        eqsl: QSLServiceCredentials(), clubLog: eqslSet)
        // Each credential a download needs, emptied on its own, leaves out that download and only it (as the uploads, R6).
        var readinessCases: [(String, Bool)] = []
        for (name, service) in [("LoTW username", "lotw"), ("LoTW password", "lotw"), ("QRZ key", "qrz"), ("eQSL user", "eqsl"),
                                ("eQSL password", "eqsl"), ("Club Log email", "clubLog"), ("Club Log password", "clubLog"),
                                ("Club Log API key", "clubLog")] {
            var eqsl = eqslSet, clubLog = clubLogSet
            if name == "eQSL user" { eqsl.eqslUsername = "" }
            if name == "eQSL password" { eqsl.eqslPassword = "" }
            if name == "Club Log email" { clubLog.clubLogEmail = "" }
            if name == "Club Log password" { clubLog.clubLogPassword = "" }
            if name == "Club Log API key" { clubLog.clubLogAPIKey = "" }
            let ready = QSLSyncReport.downloadReadiness(lotwUsername: name == "LoTW username" ? "" : "EA3JIC",
                                                        lotwPassword: name == "LoTW password" ? "" : "test",
                                                        qrzAPIKey: name == "QRZ key" ? "" : "test-key", eqsl: eqsl, clubLog: clubLog)
            readinessCases.append((name, ready.lotw == (service != "lotw") && ready.qrz == (service != "qrz") &&
                                         ready.eqsl == (service != "eqsl") && ready.clubLog == (service != "clubLog")))
        }
        check("download readiness: LoTW needs username and web password, QRZ its key, eQSL.cc user and password, Club Log email, password and key (each emptied on its own: 8 cases)",
              allReady.lotw && allReady.qrz && allReady.eqsl && allReady.clubLog &&
              !noneReady.lotw && !noneReady.qrz && !noneReady.eqsl && !noneReady.clubLog && readinessCases.allSatisfy(\.1),
              readinessCases.filter { !$0.1 }.map(\.0).joined(separator: ", "))
        var ranDownload = ConfirmationSyncSummary()
        ranDownload.lotwFetched = 3
        ranDownload.lotwMessage = "3 downloaded"
        ranDownload.qrzMessage = "0 downloaded"
        let goodEnd = QSLSyncReport.endOfSync(upload: clean, readiness: allReady, lotwQRZ: ranDownload, otherErrors: 0, updated: 1)
        check("Sync All with every upload and download done says successfully",
              goodEnd.complete && !goodEnd.problems && goodEnd.downloadProblems.isEmpty && goodEnd.downloadsNotChecked.isEmpty)
        let skippedRun = QSLSyncReport.endOfSync(upload: clean, readiness: allReady, lotwQRZ: nil, otherErrors: 0, updated: 0,
                                                 downloadsSkipped: "a Guest Log is open; open the master log")
        check("R16 during the run: with a Guest Log opened during the uploads, the downloads are not run and that is a problem",
              skippedRun.problems && !skippedRun.complete && skippedRun.downloadProblems.first?.contains("downloads not run") == true)
        let failedEnd = QSLSyncReport.endOfSync(upload: clean, readiness: allReady, lotwQRZ: failedDownload, otherErrors: 0, updated: 0)
        let notRunEnd = QSLSyncReport.endOfSync(upload: clean, readiness: allReady, lotwQRZ: ConfirmationSyncSummary(), otherErrors: 0, updated: 0)
        let errorsEnd = QSLSyncReport.endOfSync(upload: clean, readiness: allReady, lotwQRZ: ranDownload, otherErrors: 1, updated: 0)
        let eqslMissingEnd = QSLSyncReport.endOfSync(
            upload: clean, readiness: QSLSyncReport.downloadReadiness(lotwUsername: "EA3JIC", lotwPassword: "test", qrzAPIKey: "test-key",
                                                                      eqsl: QSLServiceCredentials(), clubLog: clubLogSet),
            lotwQRZ: ranDownload, otherErrors: 0, updated: 0)
        check("Sync All is not successful with a failed LoTW download, a LoTW/QRZ download that did not run, or an error in another download",
              failedEnd.problems && notRunEnd.problems && errorsEnd.problems && !failedEnd.complete && !notRunEnd.complete && !errorsEnd.complete)
        let qrzOnlyNotRun = QSLSyncReport.endOfSync(
            upload: clean, readiness: QSLSyncReport.downloadReadiness(lotwUsername: "", lotwPassword: "", qrzAPIKey: "test-key",
                                                                      eqsl: eqslSet, clubLog: clubLogSet),
            lotwQRZ: ConfirmationSyncSummary(), otherErrors: 0, updated: 0)
        check("with only the QRZ key set (no LoTW login), a LoTW/QRZ download that did not run is still a problem",
              qrzOnlyNotRun.problems && !qrzOnlyNotRun.complete &&
              qrzOnlyNotRun.downloadProblems.contains { $0.hasPrefix("LoTW and QRZ download did not run") })
        let onlyNotSent = QSLPassSummary(provider: .eqsl, notSent: 3, notSentReason: "stopped after two failed requests in a row")
        let notSentRun = QSLSyncUploadRun(summaries: [onlyNotSent])
        check("QSOs not sent because the service stopped are a problem: in the line, the status and the end of Sync All",
              onlyNotSent.hasProblems && QSLSyncReport.lines(notSentRun).first { $0.text.hasPrefix("eQSL:") }?.problem == true &&
              QSLSyncReport.status(notSentRun).hasPrefix("Uploads finished with problems") &&
              !QSLSyncReport.endOfSync(upload: notSentRun, readiness: allReady, lotwQRZ: ranDownload, otherErrors: 0, updated: 0).complete)
        check("Sync All without eQSL.cc credentials names that download as not checked and is not successful",
              !eqslMissingEnd.complete && !eqslMissingEnd.problems && eqslMissingEnd.downloadsNotChecked.count == 1 &&
              eqslMissingEnd.downloadsNotChecked[0].hasPrefix("eQSL.cc download"))

        // ---- R16 · Sync only on the station's own log
        let station = UUID()
        check("the station's own log is open only in master mode with the station's log loaded; a Guest Log is not",
              QSLSyncAll.isOwnLog(isMasterMode: true, loadedProfileID: station, activeProfileID: station) &&
              !QSLSyncAll.isOwnLog(isMasterMode: false, loadedProfileID: station, activeProfileID: station) &&
              !QSLSyncAll.isOwnLog(isMasterMode: true, loadedProfileID: UUID(), activeProfileID: station) &&
              !QSLSyncAll.isOwnLog(isMasterMode: true, loadedProfileID: nil, activeProfileID: station))
        check("with the credential vault locked, every service says so instead of \"no upload credentials\"",
              QSLSyncAll.notChecked(.qrz, configured: [], switchedOn: Set(QSLProvider.allCases), vaultLocked: true) ==
                "credential vault locked (unlock with Touch ID)")
        let lostID = UUID(), pendingID = UUID(), sentID = UUID(), elsewhereID = UUID()
        let lostMarks = [QSLLostMark(qsoID: lostID, provider: .clubLog, date: "20261009"),
                         QSLLostMark(qsoID: pendingID, provider: .lotw, date: "20261008"),
                         QSLLostMark(qsoID: sentID, provider: .qrz, date: "20261009"),
                         QSLLostMark(qsoID: elsewhereID, provider: .eqsl, date: "20261007")]
        let lostFields: [UUID: [String: String]] = [lostID: ["CALL": "0B2CDE"],
                                                    pendingID: ["CALL": "0D4EF", "LOTW_QSL_SENT": "N"],
                                                    sentID: ["CALL": "0C3DE", "QRZCOM_QSO_UPLOAD_STATUS": "Y"]]
        let sortedMarks = QSLSyncAll.sortLostMarks(lostMarks, fieldsByID: lostFields)
        check("a lost mark is written with its upload date when the service's sent fields are empty or pending (N, LoTW's default); dropped when one says sent; kept when the QSO is not in the open log",
              sortedMarks.write == [lostMarks[0], lostMarks[1]] && sortedMarks.write.map(\.date) == ["20261009", "20261008"] &&
              sortedMarks.keep == [lostMarks[3]])
        final class SavedMarks { var data: [String: Data] = [:] }
        let saved = SavedMarks()
        let store = QSLLostMarkStore(read: { saved.data[$0] }, write: { key, value in saved.data[key] = value })
        let stationA = UUID(), stationB = UUID()
        store.append([lostMarks[0]], profileID: stationA)
        store.append([lostMarks[1], lostMarks[2], lostMarks[3]], profileID: stationA)
        let savedBefore = store.load(profileID: stationA)
        check("lost marks: saving twice keeps every mark with its date, under the station's own key; another station reads none",
              savedBefore == lostMarks && store.load(profileID: stationB).isEmpty &&
              Array(saved.data.keys) == ["qslLostMarks." + stationA.uuidString] && QSLLostMarkStore.key(stationA) == "qslLostMarks." + stationA.uuidString)
        let restoredMarks = store.restore(profileID: stationA, fieldsByID: lostFields)
        let keptAfterRestore = store.load(profileID: stationA)
        let restoredLater = store.restore(profileID: stationA, fieldsByID: lostFields.merging([elsewhereID: ["CALL": "0E5FG"]]) { $1 })
        check("lost marks: restoring gives the marks to write with their saved dates and keeps saved only the QSO not in the log; once written, the key is removed",
              restoredMarks == [lostMarks[0], lostMarks[1]] && restoredMarks.map(\.date) == ["20261009", "20261008"] &&
              keptAfterRestore == [lostMarks[3]] && restoredLater == [lostMarks[3]] && restoredLater.first?.date == "20261007" &&
              saved.data.isEmpty)

        // ---- R4 · marks: an accepted upload, from the QSL Hub or the Zero-Click daemon, makes the QSO sent there
        for (provider, ids) in plan {
            for id in ids {
                guard let index = log.firstIndex(where: { $0.id == id }) else { continue }
                for (field, value) in QSLUploadStatus.acceptedFields(for: provider, date: "20261010") { log[index].fields[field] = value }
            }
        }
        let marked = log.first { $0.id == q1 }?.fields ?? [:]
        check("an accepted Club Log upload writes YAAM's field and the ADIF field, each with its date",
              marked["APP_YAAM_CLUBLOG_SENT"] == "Y" && marked["CLUBLOG_QSO_UPLOAD_STATUS"] == "Y" &&
              marked["APP_YAAM_CLUBLOG_SENT_DATE"] == "20261010" && marked["CLUBLOG_QSO_UPLOAD_DATE"] == "20261010")
        check("a second Sync queues nothing: no QSO goes twice to the same service",
              QSLSyncAll.plannedUploads(records: log, providers: [.qrz, .clubLog], jobStates: jobStates).isEmpty)
        let dateField13734: [QSLProvider: String] = [.lotw: "LOTW_QSLSDATE", .qrz: "QRZCOM_QSO_UPLOAD_DATE",
                                                     .eqsl: "EQSL_QSLSDATE", .clubLog: "APP_YAAM_CLUBLOG_SENT_DATE"]
        check("for each service, an accepted upload still writes what 1.37.34 wrote (its sent field and date), and the QSO then counts as sent",
              QSLProvider.allCases.allSatisfy { provider in
                  var fields: [String: String] = [:]
                  for (field, value) in QSLUploadStatus.acceptedFields(for: provider, date: "20261010") { fields[field] = value }
                  return fields[provider.sentField] == "Y" && fields[dateField13734[provider] ?? ""] == "20261010" &&
                      !QSLSyncAll.needsUpload(fields, to: provider, jobState: nil)
              })
        let daemonNames = ["QRZ": QSLProvider.qrz, "Club Log": .clubLog, "eQSL": .eqsl, "LoTW": .lotw]
        check("the Zero-Click daemon's services map to the QSL Hub's, and Wavelog to none",
              daemonNames.allSatisfy { QSLUploadStatus.provider(zeroClickService: $0.key) == $0.value } &&
              QSLUploadStatus.provider(zeroClickService: "Wavelog") == nil)
        var daemonQSO = ["CALL": "0A1BCD", "QSO_DATE": "20261010", "TIME_ON": "0800", "BAND": "20m", "MODE": "FT8"]
        for service in ["QRZ", "Club Log", "eQSL", "LoTW"] {
            guard let provider = QSLUploadStatus.provider(zeroClickService: service) else { continue }
            for (field, value) in QSLUploadStatus.acceptedFields(for: provider, date: "20261010") { daemonQSO[field] = value }
        }
        check("a QSO the daemon uploaded to all four services is then planned for none",
              QSLSyncAll.plannedUploads(records: [(UUID(), daemonQSO)], providers: Set(QSLProvider.allCases), jobStates: [:]).isEmpty)

        // ---- R13 · Club Log uploads marked by 1.37.34 get the ADIF field
        let old = ["CALL": "0C3DE", "APP_YAAM_CLUBLOG_SENT": "Y", "APP_YAAM_CLUBLOG_SENT_DATE": "20260920"]
        let backfilled = QSLUploadStatus.withStandardClubLogStatus(old)
        check("a 1.37.34 Club Log mark gets CLUBLOG_QSO_UPLOAD_STATUS=Y and the date; M, a Y already there or no mark are left alone",
              backfilled?["CLUBLOG_QSO_UPLOAD_STATUS"] == "Y" && backfilled?["CLUBLOG_QSO_UPLOAD_DATE"] == "20260920" &&
              QSLUploadStatus.withStandardClubLogStatus(old.merging(["CLUBLOG_QSO_UPLOAD_STATUS": "M"]) { $1 }) == nil &&
              QSLUploadStatus.withStandardClubLogStatus(old.merging(["CLUBLOG_QSO_UPLOAD_STATUS": "Y"]) { $1 }) == nil &&
              QSLUploadStatus.withStandardClubLogStatus(["CALL": "0C3DE"]) == nil)

        // ---- in the app (source): the parts that do not build on their own, pinned with the values they pass
        let hub = source("YAAM/AppStateQSLHub.swift")
        let engine = source("YAAM/QSLSyncEngine.swift")
        let client = source("YAAM/QSLHub.swift")
        let daemon = source("YAAM/ZeroClickCloudUploadDaemon.swift")
        let awards = source("YAAM/QRZAwardsView.swift")
        let studio = source("YAAM/QSLHubStudioView.swift")
        let workspace = source("YAAM/StationWorkspaceView.swift")
        let table = source("YAAM/LogTableView.swift")
        let confirmations = source("YAAM/ConfirmationSync.swift")
        let columns = source("YAAM/TableColumnPolicy.swift")
        let vault = source("YAAM/KeychainStore.swift")
        let wavelog = source("YAAM/WavelogClient.swift")
        let wavelogSync = source("YAAM/WavelogSyncEngine.swift")
        let appState = source("YAAM/AppState.swift")
        func slice(_ text: String, from start: String, to end: String) -> String {
            guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { return "" }
            return String(text[a.lowerBound..<b.lowerBound])
        }
        let upload = slice(hub, from: "func uploadNeverSentQSOs(", to: "func syncSelectedQSOs(")
        let selectedSync = slice(hub, from: "func syncSelectedQSOs(", to: "/// Sends the due jobs")
        let queueRun = slice(hub, from: "func processQSLQueue(", to: "func retryQSLFailures(")
        let syncAll = slice(engine, from: "func syncAllServices(", to: "// MARK: - Service 1")
        let markZeroClick = slice(hub, from: "func markZeroClickUploads(", to: "func isZeroClickQSOAlreadyAtService(")
        let alreadyAtService = slice(hub, from: "func isZeroClickQSOAlreadyAtService(", to: "private func zeroClickRecordIndex(")
        let recordIndex = slice(hub, from: "private func zeroClickRecordIndex(", to: "func restoreLostQSLMarks(")
        let loadState = slice(hub, from: "func loadQSLHubState() {", to: "func refreshAwardProgress()")
        let applyUpdates = slice(hub, from: "private func applyQSLJobUpdates(", to: "static func qslDateString(")
        let restoreMarks = slice(hub, from: "func restoreLostQSLMarks() {", to: "func addStandardClubLogStatus()")
        let queueUnblocked = QSLSyncAll.queueChanges(
            records: [(id: blockedOld.qsoID, fields: fresh)], profileID: blockedOld.stationProfileID,
            providers: [.qrz], existingJobs: [blockedOld], unblockedKeys: unblocked
        )
        let queueStillBlocked = QSLSyncAll.queueChanges(
            records: [(id: blockedOld.qsoID, fields: fresh)], profileID: blockedOld.stationProfileID,
            providers: [.qrz], existingJobs: [blockedOld]
        )
        check("the shared queue builder filters ADIF and only unblocks stopped jobs after changed credentials",
              hub.contains("let changedJobs = QSLSyncAll.queueChanges(") && queueStillBlocked.isEmpty &&
              queueUnblocked.count == 1 && queueUnblocked[0].id == blockedOld.id &&
              queueUnblocked[0].adif == QSLUploadStatus.uploadADIF(fresh, for: .qrz) &&
              queueUnblocked[0].state == .queued && !hub.contains("func qslADIFRecord"))
        check("Sync reads the Station Workspace switches under the key the page saves, and only a touched switch saves it",
              upload.contains("QSLSyncAll.switchedOn(stored: UserDefaults.standard.string(forKey: \"stationWorkspace.enabledProviders\"))") &&
              workspace.components(separatedBy: "\"stationWorkspace.enabledProviders\"").count == 3 &&
              workspace.contains("forKey: \"stationWorkspace.enabledProviders\"\n                            )") &&
              !workspace.contains(".onChange(of: enabledProviders)") &&
              workspace.contains("let configured = appState.qslConfiguredProvidersForSync()"))
        check("Sync looks TQSL up for LoTW and takes switched-on services with credentials, none while the vault is locked",
              hub.contains("if let resolved = TQSLCoordinator.resolveBinaryPath(") &&
              hub.contains("return QSLSyncAll.configuredProviders(credentials, tqslFound: tqslFound)") &&
              upload.contains("let vaultLocked = !CredentialVault.isVaultSessionUnlocked") &&
              upload.contains("let providers = vaultLocked ? Set<QSLProvider>() : configured.intersection(switchedOn)"))
        check("Sync takes the QSOs with recordsToSync, queues them without stopped jobs, and reports what was there before",
              upload.contains("let chosenFields = QSLSyncAll.recordsToSync(all: selectedFields, selectedIDs: nil, stationCallsign: currentStationCallsign)") &&
              upload.contains("enqueueQSL(records: qsoRecords.filter { chosenIDs.contains($0.id) }, providers: providers, retryStopped: false, unblockedKeys: unblocked)") &&
              upload.contains("let unblocked = QSLSyncAll.unblockedJobKeys(qslQueueJobs, credentialsChangedAt: qslCredentialsChangedAt())") &&
              upload.contains("let summaries = await processQSLQueue(providers: providers, qsoIDs: selectedIDs == nil ? nil : chosenIDs, countAlreadyThere: false)") &&
              upload.contains("run.summaries = QSLSyncReport.withPriorState(summaries, providers: providers, alreadyThere: alreadyThere, leftover: leftover)"))
        check("Sync Selected passes the table's selection and downloads nothing",
              selectedSync.contains("let selectedIDs = selectedRecordIDs") &&
              selectedSync.contains("let run = await uploadNeverSentQSOs(selectedIDs: selectedIDs)") &&
              !["syncConfirmations", "runSync", "downloadEQSLConfirmations", "syncAllServices", "downloadLoTWAndQRZ"].contains { selectedSync.contains($0) } &&
              table.contains("Task { await appState.syncSelectedQSOs() }"))
        check("R16: with a Guest Log open, Sync uploads nothing and the queue sends, drops and saves nothing",
              upload.contains("if let problem = qslOwnLogProblem {") && queueRun.contains("if let problem = qslOwnLogProblem {") &&
              selectedSync.contains("qslHubStatus = \"Sync Selected did nothing: \\(problem)\"") &&
              queueRun.contains("if isOwnStationLogOpen { autoSaveActiveWorkspace() }") &&
              queueRun.contains("if markedSinceSave > 0, isOwnStationLogOpen { autoSaveActiveWorkspace() }") &&
              syncAll.contains("let downloadsSkipped = appState.qslOwnLogProblem ??\n            (appState.activeStationProfileID == startProfileID ? nil : \"the active station changed\")") &&
              syncAll.contains("let startProfileID = appState.activeStationProfileID") && syncAll.contains("if downloadsSkipped == nil {") &&
              syncAll.contains("if totalUpdatedCount > 0, appState.isOwnStationLogOpen { appState.autoSaveActiveWorkspace() }") &&
              syncAll.contains("if let problem = appState.qslOwnLogProblem {") &&
              hub.contains("QSLSyncAll.isOwnLog(isMasterMode: isMasterMode, loadedProfileID: loadedWorkspaceProfileID, activeProfileID: activeStationProfileID)"))
        check("the queue run takes due jobs, looks again at each with review, and runs each service in passOrder",
              queueRun.contains("QSLSyncAll.dueJobs(qslQueueJobs, now: Date(), providers: providers, qsoIDs: qsoIDs)") &&
              queueRun.contains("switch QSLSyncAll.review(job, currentFields: fieldsByID[job.qsoID]) {") &&
              queueRun.contains("let jobs = QSLSyncAll.passOrder(toSend.filter { $0.provider == provider })") &&
              queueRun.contains("pass.record(QSLBatchOutcome(result), for: batch, now: Date())") && queueRun.contains("pass.finish(now: Date())"))
        let uploadAt = engine.range(of: "await appState.uploadNeverSentQSOs()")?.lowerBound
        let downloadAt = engine.range(of: "await withTaskGroup(of: Void.self)")?.lowerBound
        func at(_ text: String) -> String.Index? { syncAll.range(of: text)?.lowerBound }
        let order = [at("let startProfileID = appState.activeStationProfileID"), at("await appState.uploadNeverSentQSOs()"),
                     at("let downloadsSkipped = appState.qslOwnLogProblem"), at("let errorsBeforeDownloads = errorsLogged"),
                     at("await withTaskGroup(of: Void.self)"), at("let end = QSLSyncReport.endOfSync(")]
        check("Sync All in this order: the station noted, the uploads, the second R16 look and the error count, the downloads, then endOfSync",
              order.allSatisfy { $0 != nil } && zip(order, order.dropFirst()).allSatisfy { $0! < $1! })
        check("Sync All uploads first, runs one at a time (the daemon and a loading log included), and its last line comes from finalLine",
              uploadAt != nil && downloadAt != nil && uploadAt! < downloadAt! &&
              syncAll.contains("!appState.isSyncingAPI, !appState.isProcessingQSLQueue,") &&
              syncAll.contains("!appState.isLoading, !daemon.isUploading, !daemon.isFlushingQueue else {") &&
              engine.contains("self.lastLoTWQRZSummary = summary // R10 report") && syncAll.contains("lastRunSummary = end.text"))
        check("Sync All gives endOfSync exactly what it saw, and the readiness the same credentials each download tests",
              ["let readiness = QSLSyncReport.downloadReadiness(",
               "lotwUsername: UserDefaults.standard.string(forKey: \"lotwUsername\") ?? \"\",",
               "lotwPassword: CredentialVault.value(for: .lotwPassword),", "qrzAPIKey: appState.activeQRZAPIKey,",
               "eqsl: appState.qslServiceCredentials(for: [.eqsl]),", "clubLog: appState.qslServiceCredentials(for: [.clubLog])",
               "let errorsBeforeDownloads = errorsLogged", "let end = QSLSyncReport.endOfSync(", "upload: upload,", "readiness: readiness,",
               "lotwQRZ: lastLoTWQRZSummary,", "otherErrors: errorsLogged - errorsBeforeDownloads,", "updated: totalUpdatedCount,",
               "downloadsSkipped: downloadsSkipped", "appState.playActivitySound(end.complete ? .success : .notice)"].allSatisfy { syncAll.contains($0) })
        check("the downloads are still the same three (eQSL, LoTW and QRZ, Club Log)",
              ["await self.syncEQSL(appState: appState)", "await self.syncLoTWAndQRZ(appState: appState)",
               "await self.syncClubLog(appState: appState)"].allSatisfy { engine.contains($0) })
        check("the Zero-Click daemon reports each accepted service, and its outbox asks first whether the QSO is already there",
              daemon.contains("if !successfulServices.isEmpty { onServiceAccepted?(record, successfulServices) }") &&
              daemon.contains("if !acceptedServices.isEmpty { onServiceAccepted?(record, acceptedServices) }") &&
              daemon.contains("if isAlreadyAtService?(record, service) == true {") &&
              loadState.contains("daemon.onServiceAccepted = { [weak self] record, services in") &&
              loadState.contains("self?.markZeroClickUploads(record, services: services)") &&
              loadState.contains("daemon.isAlreadyAtService = { [weak self] record, service in") &&
              loadState.contains("self?.isZeroClickQSOAlreadyAtService(record, service: service) ?? false"))
        check("the daemon chain in AppState: the QSO is found (by id, or by a non-empty key from the end), marked for each service, and saved",
              markZeroClick.contains("guard !providers.isEmpty, isOwnStationLogOpen, let index = zeroClickRecordIndex(record) else { return }") &&
              markZeroClick.contains("for provider in providers { markQSO(id, sentTo: provider) }") && markZeroClick.contains("autoSaveActiveWorkspace()") &&
              alreadyAtService.contains("guard isOwnStationLogOpen, let provider = QSLUploadStatus.provider(zeroClickService: service),") &&
              alreadyAtService.contains("return QSLUploadStatus.isSent(qsoRecords[index].fields, to: provider)") &&
              recordIndex.contains("if let index = qsoRecords.lastIndex(where: { $0.id == record.id }) { return index }") &&
              recordIndex.contains("guard !key.isEmpty else { return nil }") && recordIndex.contains("return qsoRecords.lastIndex(where: {"))
        check("the daemon counts its uploads in flight, so Sync waits while any is running",
              daemon.contains("public var isUploading: Bool { activeUploads > 0 }") && daemon.contains("activeUploads += 1") &&
              daemon.contains("defer { activeUploads -= 1 }") && !daemon.contains("isUploading = true"))
        check("the queue sends current fields, writes no mark for jobs already there, drops gone ones, and Upload and Retry queue stopped jobs",
              queueRun.contains("job.adif = adif") &&
              queueRun.contains("_ = applyQSLJobUpdates((alreadyThere + toSend).map { QSLJobUpdate(job: $0, markSent: false) }") &&
              queueRun.contains("try? database.deleteQSLJobs(gone)") &&
              hub.contains("retryStopped: Bool = true,") && hub.contains("retryStopped: retryStopped") &&
              studio.contains("appState.retryQSLFailures()\n                    Task { await appState.processQSLQueue() }"))
        check("lost marks are saved with their upload date and written when the station's own log loads; the Club Log field is added at load and at Sync",
              applyUpdates.contains("QSLLostMark(qsoID: update.job.qsoID, provider: update.job.provider, date: Self.qslDateString(update.job.updatedAt))") &&
              applyUpdates.contains("for (profileID, marks) in lost { QSLLostMarkStore.standard.append(marks, profileID: profileID) }") &&
              restoreMarks.contains("let write = store.restore(profileID: profileID, fieldsByID: fieldsByID)") &&
              restoreMarks.contains("for mark in write { markQSO(mark.qsoID, sentTo: mark.provider, date: mark.date) }") &&
              hub.contains("QSLUploadStatus.acceptedFields(for: provider, date: date ?? Self.qslDateString(Date()))") &&
              source("YAAM/QSLSyncAll.swift").contains("QSLLostMarkStore(read: { UserDefaults.standard.data(forKey: $0) }, write: { key, data in") &&
              loadState.contains("restoreLostQSLMarks()") && loadState.contains("addStandardClubLogStatus()") &&
              appState.contains("// Sent marks saved while another log was open (QSLLostMark) are written now.\n                restoreLostQSLMarks()") &&
              upload.contains("if addStandardClubLogStatus() > 0 { autoSaveActiveWorkspace() }"))
        let guestLog = slice(appState, from: "func loadGuestLog(from url: URL) {", to: "excludingSelfContacts(")
        check("opening a Guest Log saves the station's log first, so the marks written since the last save are kept",
              guestLog.contains("if isOwnStationLogOpen { autoSaveActiveWorkspace() }\n                isMasterMode = false"))
        check("the daemon and the QSL Hub read QRZ replies the same way",
              daemon.contains("let reply = QSLUploadStatus.qrzReply(responseText)") && client.contains("let reply = QSLUploadStatus.qrzReply(text)") &&
              client.contains("if reply.duplicate { duplicates += 1 }"))
        check("R11: the daemon, Wavelog (one QSO and the full sync), HRDLog and HamQTH leave the local fields out",
              daemon.contains("var normalizedFields = QSLUploadStatus.uploadFields(record.fields, for: destination)") &&
              wavelog.contains("var normalizedFields = QSLUploadStatus.uploadFields(record.fields, for: .wavelog)") &&
              wavelogSync.contains("let dicts = uploadRecords.map { QSLUploadStatus.uploadFields($0.fields, for: .wavelog) }") &&
              appState.contains("var exportFields = QSLUploadStatus.uploadFields(fields, for: destination)"))
        check("new credentials: every save records its time, and Sync reads it per service",
              vault.components(separatedBy: "markChanged(account:").count == 8 &&
              hub.contains("CredentialVault.changedAt(.qrzAPIKey)") && hub.contains("CredentialVault.changedAt(.clubLogAPIKey)"))
        check("the Station Workspace reads the same rule",
              workspace.components(separatedBy: "QSLUploadStatus.isSent(record.fields, to: provider)").count == 3 &&
              !workspace.contains("[\"Y\", \"V\", \"C\", \"CONFIRMED\"].contains(record[provider.sentField]"))
        check("the awards pill runs the same Sync All, shows it is running, and the Club Log count uses the same rule",
              awards.contains("Task { await QSLSyncEngine.shared.syncAllServices(appState: appState) }") &&
              awards.contains("label: syncEngine.isSyncing ? \"Syncing…\" : \"Sync All\"") &&
              awards.contains("QSLUploadStatus.isSent($0.fields, to: .clubLog)"))
        let isConfirmed = slice(appState, from: "var isConfirmed: Bool {", to: "\n    }\n")
        check("the QRZ download writes QRZCOM_QSO_DOWNLOAD_STATUS=Y without counting it as a change or a confirmation",
              confirmations.contains("let markedDownloaded = set(\"QRZCOM_QSO_DOWNLOAD_STATUS\", to: \"Y\", in: &output[target])") &&
              confirmations.contains("} else if markedDownloaded {") && confirmations.contains("|| !mergeResult.fieldOnlyRecordIDs.isEmpty") &&
              !confirmations.contains("changed = set(\"QRZCOM_QSO_DOWNLOAD_STATUS\"") &&
              confirmations.contains("fields[\"QRZCOM_QSO_DOWNLOAD_STATUS\"] = \"Y\"") &&
              !isConfirmed.isEmpty && !isConfirmed.contains("QRZCOM_QSO_DOWNLOAD_STATUS"))
        check("the QSL Hub button is called Sync All, shows the run's last line, and the menu has Retry Failed Uploads",
              studio.contains("Text(syncEngine.isSyncing ? \"Syncing...\" : \"Sync All\")") &&
              studio.contains("showToast(syncEngine.lastRunSummary)") && studio.contains("Button(\"Retry Failed Uploads\")"))
        check("the new CLUBLOG_ columns stay out of the log table, as the other services' columns do",
              columns.contains("field.hasPrefix(\"CLUBLOG_\")"))

        print("\(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
