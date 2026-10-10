//
//  QSLSyncAll.swift
//  YAAM
//
//  Sync All and Sync Selected. Sync All uploads, to each service that is switched on and has its upload credentials,
//  the QSOs never uploaded there, and then downloads confirmations. Sync Selected does the upload part for the
//  selected QSOs only and downloads nothing. The QSL Hub queue and the Zero-Click daemon read and write the same
//  marks, so a QSO is not sent twice to the same service. This file is plain logic with no network, so the test runs
//  it as the app does.
//

import Foundation

nonisolated enum QSLUploadStatus {
    /// Values of a sent field that mean the QSO was uploaded and accepted. Y is the ADIF value; V, C and CONFIRMED
    /// come from the QSL Hub rule of 1.37.34 and are kept, although they are not values of these ADIF fields.
    static let sentValues: Set<String> = ["Y", "V", "C", "CONFIRMED"]

    /// The fields that say a QSO was sent to `provider`. For Club Log, YAAM's own field and the ADIF field
    /// CLUBLOG_QSO_UPLOAD_STATUS, so a QSO uploaded by YAAM and a QSO imported from another program both count.
    static func sentFields(for provider: QSLProvider) -> [String] {
        provider == .clubLog ? [provider.sentField, "CLUBLOG_QSO_UPLOAD_STATUS"] : [provider.sentField]
    }

    /// Whether the QSO is already at the service:
    /// - a sent field says so (a value in `sentValues`);
    /// - or the service has confirmed it: LoTW, LOTW_QSL_RCVD Y or V; QRZ, QRZLOG_QSL_RCVD Y or APP_QRZLOG_STATUS C
    ///   or CONFIRMED. An eQSL confirmation does not count, because the eQSL inbox also receives cards for QSOs never
    ///   uploaded there; Club Log has no confirmation. Nothing is written for these QSOs: the upload date is not
    ///   known;
    /// - or, for QRZ, the QSO is known to be in the QRZ logbook without being confirmed: QRZCOM_QSO_DOWNLOAD_STATUS Y
    ///   (ADIF 3.1.7: "downloaded from the online service") or APP_QRZLOG_STATUS UPLOADED (Lab599 Utility's mark).
    ///   It is not uploaded again, and it is not a confirmation;
    /// - or YAAM added it from that service's own download (`cameFrom`).
    /// Any other value of the sent field (empty, N, R, Q, I or M) is pending.
    static func isSent(_ fields: [String: String], to provider: QSLProvider) -> Bool {
        if cameFrom(fields, provider) { return true }
        if sentFields(for: provider).contains(where: { sentValues.contains(value(fields, $0)) }) { return true }
        switch provider {
        case .lotw:
            return ["Y", "V"].contains(value(fields, "LOTW_QSL_RCVD"))
        case .qrz:
            return value(fields, "QRZLOG_QSL_RCVD") == "Y" ||
                ["C", "CONFIRMED", "UPLOADED"].contains(value(fields, "APP_QRZLOG_STATUS")) ||
                value(fields, "QRZCOM_QSO_DOWNLOAD_STATUS") == "Y"
        case .eqsl, .clubLog:
            return false
        }
    }

    /// A field's value, trimmed and in upper case.
    static func value(_ fields: [String: String], _ key: String) -> String {
        (fields[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// A QSO that YAAM added from a service's own confirmations is already at that service. The LoTW and QRZ
    /// downloads add an unmatched confirmation as a new QSO marked APP_YAAM_REMOTE_CONFIRMATION_IMPORTED = LOTW or QRZ
    /// (importRemoteConfirmationRecords, ConfirmationSync.swift), with no sent field; without this, the next Sync All
    /// would upload it back to the service it came from.
    static func cameFrom(_ fields: [String: String], _ provider: QSLProvider) -> Bool {
        let source = value(fields, "APP_YAAM_REMOTE_CONFIRMATION_IMPORTED")
        switch provider {
        case .lotw: return source == "LOTW"
        case .qrz: return source == "QRZ"
        case .eqsl, .clubLog: return false
        }
    }

    /// What is written on a QSO when `provider` accepts it (`date` is YYYYMMDD), sent field first, then its date.
    /// For Club Log, YAAM's fields and the ADIF fields, so that both YAAM's Club Log count (QRZAwardsView) and
    /// other programs read it.
    static func acceptedFields(for provider: QSLProvider, date: String) -> [(field: String, value: String)] {
        switch provider {
        case .lotw: return [("LOTW_QSL_SENT", "Y"), ("LOTW_QSLSDATE", date)]
        case .qrz: return [("QRZCOM_QSO_UPLOAD_STATUS", "Y"), ("QRZCOM_QSO_UPLOAD_DATE", date)]
        case .eqsl: return [("EQSL_QSL_SENT", "Y"), ("EQSL_QSLSDATE", date)]
        case .clubLog:
            return [("APP_YAAM_CLUBLOG_SENT", "Y"), ("APP_YAAM_CLUBLOG_SENT_DATE", date),
                    ("CLUBLOG_QSO_UPLOAD_STATUS", "Y"), ("CLUBLOG_QSO_UPLOAD_DATE", date)]
        }
    }

    /// The QSL Hub service that a Zero-Click daemon service name stands for; nil for Wavelog, which has none.
    static func provider(zeroClickService service: String) -> QSLProvider? {
        switch service {
        case "QRZ": return .qrz
        case "Club Log": return .clubLog
        case "eQSL": return .eqsl
        case "LoTW": return .lotw
        default: return nil
        }
    }

    /// Fields that stay on this Mac and are never sent to a service: YAAM's own APP_YAAM_ fields, the path of a
    /// downloaded eQSL card image (QSL_MEDIA_PATH, which includes the macOS user name), YAAM's QRZ page link, the
    /// rank enrichment and SDR-Control's import marks. Every ADIF that goes to a service leaves them out: the QSL
    /// Hub, the Zero-Click daemon, Wavelog, HRDLog and HamQTH. A local export keeps them.
    static let localOnlyFields: Set<String> = [
        "QSL_MEDIA_PATH", "QRZ_URL", "RANK_QSO", "RANK_BAND", "RANK_DXCC",
        "APP_SDR_CONTROL_IMPORTED", "APP_SDR_CONTROL_ID", "APP_SDR_CONTROL_CONFIRMED",
    ]

    static func isLocalOnly(_ key: String) -> Bool {
        let upper = key.uppercased()
        return upper.hasPrefix("APP_YAAM_") || localOnlyFields.contains(upper)
    }

    /// A QSO's fields without the local-only ones, for an ADIF that goes to a service.
    static func serviceFields(_ fields: [String: String]) -> [String: String] {
        fields.filter { !isLocalOnly($0.key) }
    }

    /// The ADIF record the QSL Hub uploads, built from the QSO's fields as they are now: the effective mode, the
    /// cleaned comment, and no local-only field. (It was AppState.qslADIFRecord; the comment cleaner runs on the
    /// main actor, as before.)
    @MainActor
    static func uploadADIF(_ fields: [String: String]) -> String {
        var normalizedFields = fields
        let currentMode = normalizedFields["MODE"] ?? ""
        let currentSubmode = normalizedFields["SUBMODE"] ?? ""
        let freq = Double(normalizedFields["FREQ"] ?? "")
        let effective = AmateurBandPlan.effectiveADIFMode(mode: currentMode, submode: currentSubmode, frequencyMHz: freq)
        if !effective.isEmpty {
            normalizedFields["MODE"] = effective
            if effective == "FT8" || effective == "FT4" || effective == "JS8" {
                normalizedFields["SUBMODE"] = effective
            }
        }

        var result = ""
        for key in normalizedFields.keys.sorted() {
            guard let value = normalizedFields[key], !value.isEmpty else { continue }
            if isLocalOnly(key) { continue }
            if key == "COMMENT" {
                let sanitized = QSOMetadataFormatter.cleanComment(value)
                guard !sanitized.isEmpty else { continue }
                result += "<\(key):\(sanitized.utf8.count)>\(sanitized)"
                continue
            }
            result += "<\(key):\(value.utf8.count)>\(value)"
        }
        return result + "<EOR>"
    }

    /// How the QSL Hub and the Zero-Click daemon read a QRZ Logbook reply. A QSO that QRZ already has comes back as
    /// a failure whose reason says duplicate: the QSO is at QRZ, so it counts as accepted and is marked. Only
    /// RESULT=AUTH, or a reason that names the API key or authentication, is a credential rejection (which stops QRZ
    /// for the run); any other failure, such as an invalid band or date, belongs to that QSO.
    static func qrzReply(_ text: String) -> (accepted: Bool, duplicate: Bool, authenticationFailure: Bool) {
        let upper = text.uppercased()
        if upper.contains("RESULT=OK") { return (true, false, false) }
        if upper.contains("DUPLICATE") { return (true, true, false) }
        let credentials = upper.contains("RESULT=AUTH") || upper.contains("API KEY") ||
            upper.contains("AUTHENTICAT") || upper.contains("UNAUTHORIZED")
        return (false, false, credentials)
    }

    /// A QSO that 1.37.34 marked as sent to Club Log only in YAAM's own field also gets the ADIF field
    /// CLUBLOG_QSO_UPLOAD_STATUS=Y (and its date, when YAAM's date is there), so other programs read it after an
    /// export. An ADIF value that already says sent, or M, is left as it is. Returns nil when nothing changes.
    static func withStandardClubLogStatus(_ fields: [String: String]) -> [String: String]? {
        let standard = value(fields, "CLUBLOG_QSO_UPLOAD_STATUS")
        guard sentValues.contains(value(fields, "APP_YAAM_CLUBLOG_SENT")),
              !sentValues.contains(standard), standard != "M" else { return nil }
        var updated = fields
        updated["CLUBLOG_QSO_UPLOAD_STATUS"] = "Y"
        let date = (fields["APP_YAAM_CLUBLOG_SENT_DATE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !date.isEmpty, value(fields, "CLUBLOG_QSO_UPLOAD_DATE").isEmpty {
            updated["CLUBLOG_QSO_UPLOAD_DATE"] = date
        }
        return updated
    }
}

nonisolated enum QSLSyncAll {
    /// The services whose upload credentials are set: the fields QSLHubClient checks before it uploads. LoTW also
    /// needs a station location and the TQSL program (`tqslFound`), as the Zero-Click daemon already asks.
    static func configuredProviders(_ credentials: QSLServiceCredentials, tqslFound: Bool) -> Set<QSLProvider> {
        var providers = Set<QSLProvider>()
        if !credentials.qrzAPIKey.isEmpty { providers.insert(.qrz) }
        if !credentials.eqslUsername.isEmpty, !credentials.eqslPassword.isEmpty { providers.insert(.eqsl) }
        if !credentials.clubLogEmail.isEmpty, !credentials.clubLogPassword.isEmpty,
           !credentials.clubLogCallsign.isEmpty, !credentials.clubLogAPIKey.isEmpty {
            providers.insert(.clubLog)
        }
        if !credentials.lotwCallsign.isEmpty, !credentials.lotwStationLocation.isEmpty, tqslFound {
            providers.insert(.lotw)
        }
        return providers
    }

    /// The services switched on in the Station Workspace (its QSL switches, saved as a comma list under
    /// stationWorkspace.enabledProviders, and only when a switch is touched). While nothing is saved, every service
    /// counts as on, so Sync uses the services with their upload credentials set; that page shows the same.
    static func switchedOn(stored: String?) -> Set<QSLProvider> {
        guard let stored else { return Set(QSLProvider.allCases) }
        return Set(stored.split(separator: ",").compactMap { QSLProvider(rawValue: String($0)) })
    }

    /// Why Sync All or Sync Selected leaves a service out, or nil when it uploads to it. While the credential vault
    /// is locked (Touch ID), the credentials read as empty, so that is said instead of "no upload credentials".
    static func notChecked(
        _ provider: QSLProvider,
        configured: Set<QSLProvider>,
        switchedOn: Set<QSLProvider>,
        vaultLocked: Bool = false
    ) -> String? {
        if vaultLocked { return "credential vault locked (unlock with Touch ID)" }
        if !switchedOn.contains(provider) { return "switched off in the Station Workspace" }
        if !configured.contains(provider) {
            return provider == .lotw ? "no LoTW callsign, station location or TQSL" : "no upload credentials"
        }
        return nil
    }

    /// Whether a QSO goes to the queue for `provider`: it is not at the service yet, and its job, if any, has not
    /// finished and is not being sent now. A stopped job (blocked by rejected credentials, or failed five times) is
    /// queued again only when `retryStopped` is set (a click on the QSO's own Upload button); Sync All and Sync
    /// Selected leave it stopped until Retry Failed Uploads, or until that service's credentials change
    /// (`unblockedJobKeys`).
    static func needsUpload(
        _ fields: [String: String],
        to provider: QSLProvider,
        jobState: QSLQueueState?,
        retryStopped: Bool = false
    ) -> Bool {
        guard !QSLUploadStatus.isSent(fields, to: provider) else { return false }
        switch jobState {
        case .succeeded?, .uploading?: return false
        case .blocked?, .failed?: return retryStopped
        default: return true
        }
    }

    /// The QSOs the queue takes, per service: `needsUpload` over the records, for each provider. enqueueQSL uses it.
    static func plannedUploads(
        records: [(id: UUID, fields: [String: String])],
        providers: Set<QSLProvider>,
        jobStates: [String: QSLQueueState],
        retryStopped: Bool = false
    ) -> [QSLProvider: [UUID]] {
        var plan: [QSLProvider: [UUID]] = [:]
        for provider in QSLProvider.allCases where providers.contains(provider) {
            let ids = records.filter { record in
                needsUpload(record.fields, to: provider, jobState: jobStates[jobKey(record.id, provider)], retryStopped: retryStopped)
            }.map(\.id)
            if !ids.isEmpty { plan[provider] = ids }
        }
        return plan
    }

    /// The key the QSL Hub queue uses for one QSO and one service.
    static func jobKey(_ qsoID: UUID, _ provider: QSLProvider) -> String { "\(qsoID.uuidString)|\(provider.rawValue)" }

    /// R16: Sync works only on the station's own log. A Guest Log replaces the open QSOs while the station stays the
    /// same, so its QSOs must not go to the station's services, and the station's jobs must not be dropped as gone.
    static func isOwnLog(isMasterMode: Bool, loadedProfileID: UUID?, activeProfileID: UUID?) -> Bool {
        isMasterMode && loadedProfileID != nil && loadedProfileID == activeProfileID
    }

    /// R7: the QSOs a Sync takes: all of them for Sync All, only the selected ones for Sync Selected.
    static func recordsToSync(
        all: [(id: UUID, fields: [String: String])],
        selectedIDs: Set<UUID>?
    ) -> [(id: UUID, fields: [String: String])] {
        guard let selectedIDs else { return all }
        return all.filter { selectedIDs.contains($0.id) }
    }

    /// The keys of jobs blocked by rejected credentials whose service's credentials were saved again after the block,
    /// so that Sync queues them again (`credentialsChangedAt` holds, per service, when its credentials were last saved).
    static func unblockedJobKeys(_ jobs: [QSLQueueJob], credentialsChangedAt: [QSLProvider: Date]) -> Set<String> {
        Set(jobs.filter { job in
            job.state == .blocked && (credentialsChangedAt[job.provider].map { $0 > job.updatedAt } ?? false)
        }.map { jobKey($0.qsoID, $0.provider) })
    }

    /// R15: the order of one service's jobs in a run: those that never failed first, then by age. Otherwise two QSOs
    /// that always fail would stop the service at the start of every run (two failures in a row), and the others would
    /// never go.
    static func passOrder(_ jobs: [QSLQueueJob]) -> [QSLQueueJob] {
        jobs.enumerated().sorted { lhs, rhs in
            if lhs.element.attempts != rhs.element.attempts { return lhs.element.attempts < rhs.element.attempts }
            if lhs.element.createdAt != rhs.element.createdAt { return lhs.element.createdAt < rhs.element.createdAt }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// For the report: per service, how many of the QSOs a Sync takes are already there before it starts.
    static func alreadyThereCounts(
        records: [(id: UUID, fields: [String: String])],
        providers: Set<QSLProvider>
    ) -> [QSLProvider: Int] {
        var counts: [QSLProvider: Int] = [:]
        for provider in providers {
            counts[provider] = records.filter { QSLUploadStatus.isSent($0.fields, to: provider) }.count
        }
        return counts
    }

    /// For the report: per service, the jobs of the Sync's QSOs that stay stopped from an earlier run (blocked, or
    /// failed five times) while the QSO is still not at the service.
    static func leftoverStopped(
        jobs: [QSLQueueJob],
        fieldsByID: [UUID: [String: String]],
        providers: Set<QSLProvider>,
        unblocked: Set<String> = []
    ) -> [QSLProvider: (blocked: Int, failed: Int)] {
        var counts: [QSLProvider: (blocked: Int, failed: Int)] = [:]
        for job in jobs where providers.contains(job.provider) && (job.state == .blocked || job.state == .failed) {
            guard let fields = fieldsByID[job.qsoID], !QSLUploadStatus.isSent(fields, to: job.provider),
                  !unblocked.contains(jobKey(job.qsoID, job.provider)) else { continue }
            var count = counts[job.provider] ?? (0, 0)
            if job.state == .blocked { count.blocked += 1 } else { count.failed += 1 }
            counts[job.provider] = count
        }
        return counts
    }

    /// Which of the saved lost marks to write now: a mark whose QSO is in the open log is written, with its upload
    /// date, unless a sent field of that service already says sent (Y, V, C or CONFIRMED: the user, or another sync,
    /// set it), and then it is dropped. An empty or pending value (N, R, Q, I or M) is written over: N is also the
    /// ADIF default of LOTW_QSL_SENT and EQSL_QSL_SENT. A mark whose QSO is not in the open log is kept for later.
    static func sortLostMarks(
        _ marks: [QSLLostMark],
        fieldsByID: [UUID: [String: String]]
    ) -> (write: [QSLLostMark], keep: [QSLLostMark]) {
        var write: [QSLLostMark] = []
        var keep: [QSLLostMark] = []
        for mark in marks {
            guard let fields = fieldsByID[mark.qsoID] else { keep.append(mark); continue }
            let alreadySent = QSLUploadStatus.sentFields(for: mark.provider).contains {
                QSLUploadStatus.sentValues.contains(QSLUploadStatus.value(fields, $0))
            }
            if !alreadySent { write.append(mark) }
        }
        return (write, keep)
    }

    /// The jobs a queue run takes: queued, or waiting to retry and due. Sync All limits them to the services it
    /// uploads to, and Sync Selected also to the selected QSOs; the QSL Hub's own buttons take them all.
    static func dueJobs(
        _ jobs: [QSLQueueJob],
        now: Date,
        providers: Set<QSLProvider>? = nil,
        qsoIDs: Set<UUID>? = nil
    ) -> [QSLQueueJob] {
        jobs.filter { job in
            (job.state == .queued || job.state == .retry) && (job.nextAttemptAt.map { $0 <= now } ?? true) &&
                (providers?.contains(job.provider) ?? true) && (qsoIDs?.contains(job.qsoID) ?? true)
        }
    }

    /// What the queue does with a due job at the start of a run, with the QSO as it is then: a QSO no longer in the
    /// log is dropped, a QSO already at the service is not sent, and the others are sent with their current fields.
    @MainActor
    static func review(_ job: QSLQueueJob, currentFields: [String: String]?) -> QSLJobReview {
        guard let fields = currentFields else { return .qsoGone }
        if QSLUploadStatus.isSent(fields, to: job.provider) { return .alreadyThere }
        return .send(adif: QSLUploadStatus.uploadADIF(fields))
    }
}

/// A sent mark that could not be written because the QSO was not in the open log when the service accepted it (the
/// log changed during the upload). It is saved, and written when the station's own log is open again.
nonisolated struct QSLLostMark: Codable, Equatable, Sendable {
    var qsoID: UUID
    var provider: QSLProvider
    /// YYYYMMDD of the upload.
    var date: String
}

/// Where the lost marks are kept, per station profile, until its own log is open again: in YAAM, UserDefaults.standard
/// under "qslLostMarks.<profile id>", as JSON. The test gives it a dictionary instead.
nonisolated struct QSLLostMarkStore {
    let read: (String) -> Data?
    /// Writes the data under the key, or removes the key when the data is nil.
    let write: (String, Data?) -> Void

    static var standard: QSLLostMarkStore {
        QSLLostMarkStore(read: { UserDefaults.standard.data(forKey: $0) }, write: { key, data in
            if let data { UserDefaults.standard.set(data, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        })
    }

    static func key(_ profileID: UUID) -> String { "qslLostMarks." + profileID.uuidString }

    func load(profileID: UUID) -> [QSLLostMark] {
        guard let data = read(Self.key(profileID)), let marks = try? JSONDecoder().decode([QSLLostMark].self, from: data) else { return [] }
        return marks
    }

    /// Adds marks to the ones already saved for the profile.
    func append(_ marks: [QSLLostMark], profileID: UUID) {
        guard !marks.isEmpty else { return }
        replace(load(profileID: profileID) + marks, profileID: profileID)
    }

    /// Keeps only these marks for the profile; none removes the key.
    func replace(_ marks: [QSLLostMark], profileID: UUID) {
        if marks.isEmpty {
            write(Self.key(profileID), nil)
        } else if let data = try? JSONEncoder().encode(marks) {
            write(Self.key(profileID), data)
        }
    }

    /// The marks to write now, with their saved date (QSLSyncAll.sortLostMarks); only the ones kept for later stay saved.
    func restore(profileID: UUID, fieldsByID: [UUID: [String: String]]) -> [QSLLostMark] {
        let sorted = QSLSyncAll.sortLostMarks(load(profileID: profileID), fieldsByID: fieldsByID)
        replace(sorted.keep, profileID: profileID)
        return sorted.write
    }
}

nonisolated enum QSLJobReview: Equatable, Sendable {
    case qsoGone
    case alreadyThere
    case send(adif: String)
}

/// What one batch upload returned, as the queue needs it.
/// TQSL's exit codes 8, 9 and 14 count as accepted, as in 1.37.34 (a known limit, in 43-ITEM.md).
nonisolated struct QSLBatchOutcome: Sendable {
    var accepted: Bool
    /// True when the service already had the QSO (a QRZ duplicate).
    var alreadyAtService = false
    var authenticationFailure = false
    var message: String
}

extension QSLBatchOutcome {
    nonisolated init(_ result: QSLUploadResult) {
        self.init(
            accepted: result.accepted,
            alreadyAtService: result.alreadyAtService,
            authenticationFailure: result.authenticationFailure,
            message: result.message
        )
    }
}

/// A job after a batch, and whether its QSO is to be marked as sent.
nonisolated struct QSLJobUpdate: Sendable {
    var job: QSLQueueJob
    var markSent: Bool
}

/// The counts of one service's upload run, for the report.
nonisolated struct QSLPassSummary: Sendable, Equatable {
    var provider: QSLProvider
    var sent = 0
    var alreadyThere = 0
    var retry = 0
    var failed = 0
    var blocked = 0
    /// Not sent because the service stopped for this run; they stay pending and go at the next Sync.
    var notSent = 0
    var notSentReason = ""
    var firstProblem = ""
    /// The jobs left stopped by an earlier run, with the way to send them again.
    var stoppedEarlier = ""

    var hasProblems: Bool { retry + failed + blocked + notSent > 0 }
}

/// One service's upload run, request by request.
/// - QRZ takes one QSO per request. LoTW takes up to 200. eQSL.cc and Club Log take up to 200 QSOs that never failed;
///   a QSO that already failed goes on its own, so one bad QSO cannot fail the same 200 at every run (R15).
/// - The service stops for this run after two failed requests in a row, or after one that clearly refused the
///   credentials (R9). The jobs of a refused request are blocked; the jobs not sent because of the stop stay pending
///   and go at the next Sync.
/// The other services, and the downloads of Sync All, go on.
nonisolated struct QSLProviderPass {
    let provider: QSLProvider
    let batchSize: Int
    private let chunks: [[QSLQueueJob]]
    private var next = 0
    private var consecutiveFailures = 0
    private var stopReason: String?
    private(set) var summary: QSLPassSummary

    init(provider: QSLProvider, jobs: [QSLQueueJob], alreadyThere: Int = 0) {
        self.provider = provider
        self.batchSize = provider == .qrz ? 1 : 200
        self.chunks = Self.requests(jobs, provider: provider)
        self.summary = QSLPassSummary(provider: provider, alreadyThere: alreadyThere)
    }

    /// How a service's jobs are split into requests, in their order: QRZ one per request; LoTW up to 200; eQSL.cc and
    /// Club Log up to 200 that never failed, and each one that already failed on its own.
    static func requests(_ jobs: [QSLQueueJob], provider: QSLProvider) -> [[QSLQueueJob]] {
        var requests: [[QSLQueueJob]] = []
        var batch: [QSLQueueJob] = []
        let size = provider == .qrz ? 1 : 200
        let singleAfterFailure = provider == .eqsl || provider == .clubLog
        for job in jobs {
            if singleAfterFailure && job.attempts > 0 {
                if !batch.isEmpty { requests.append(batch); batch = [] }
                requests.append([job])
                continue
            }
            batch.append(job)
            if batch.count == size { requests.append(batch); batch = [] }
        }
        if !batch.isEmpty { requests.append(batch) }
        return requests
    }

    /// The next request to send, or nil when all are sent or the service was stopped.
    mutating func nextBatch() -> [QSLQueueJob]? {
        guard stopReason == nil, next < chunks.count else { return nil }
        defer { next += 1 }
        return chunks[next]
    }

    /// The jobs of `batch` after the service answered `outcome`.
    mutating func record(_ outcome: QSLBatchOutcome, for batch: [QSLQueueJob], now: Date) -> [QSLJobUpdate] {
        var updates: [QSLJobUpdate] = []
        if outcome.accepted {
            consecutiveFailures = 0
            for original in batch {
                var job = original
                job.state = .succeeded
                job.attempts += 1
                job.nextAttemptAt = nil
                job.message = outcome.message
                job.updatedAt = now
                if outcome.alreadyAtService {
                    summary.alreadyThere += 1
                } else {
                    summary.sent += 1
                }
                updates.append(QSLJobUpdate(job: job, markSent: true))
            }
            return updates
        }

        if summary.firstProblem.isEmpty { summary.firstProblem = outcome.message }
        for original in batch {
            updates.append(QSLJobUpdate(job: failed(original, outcome, now: now), markSent: false))
        }
        if outcome.authenticationFailure {
            stopReason = "stopped after the credentials were refused"
        } else {
            consecutiveFailures += 1
            if consecutiveFailures >= 2 { stopReason = "stopped after two failed requests in a row" }
        }
        return updates
    }

    /// After a stop, the jobs that were not sent: they stay pending, with the reason, and go at the next Sync.
    mutating func finish(now: Date) -> [QSLJobUpdate] {
        guard let stopReason, next < chunks.count else { return [] }
        var updates: [QSLJobUpdate] = []
        for original in chunks[next...].joined() {
            var job = original
            job.state = .retry
            job.nextAttemptAt = now.addingTimeInterval(Self.retryDelay(attempts: max(1, job.attempts)))
            job.message = "Not sent: \(provider.title) \(stopReason); it will be tried at the next Sync"
            job.updatedAt = now
            summary.notSent += 1
            updates.append(QSLJobUpdate(job: job, markSent: false))
        }
        summary.notSentReason = stopReason
        next = chunks.count
        return updates
    }

    /// As failQSLJob in 1.37.34: blocked on a credential rejection, failed after five attempts, otherwise a retry
    /// with a growing wait.
    private mutating func failed(_ original: QSLQueueJob, _ outcome: QSLBatchOutcome, now: Date) -> QSLQueueJob {
        var job = original
        job.attempts += 1
        if outcome.authenticationFailure {
            job.state = .blocked
            job.nextAttemptAt = nil
            summary.blocked += 1
        } else if job.attempts >= 5 {
            job.state = .failed
            job.nextAttemptAt = nil
            summary.failed += 1
        } else {
            job.state = .retry
            job.nextAttemptAt = now.addingTimeInterval(Self.retryDelay(attempts: job.attempts))
            summary.retry += 1
        }
        job.message = outcome.message
        job.updatedAt = now
        return job
    }

    static func retryDelay(attempts: Int) -> TimeInterval {
        min(3_600.0, pow(2.0, Double(attempts)) * 30.0)
    }
}

/// The result of the upload part of Sync All or Sync Selected.
nonisolated struct QSLSyncUploadRun: Sendable {
    /// Another upload was running, so nothing was done.
    var busy = false
    var summaries: [QSLPassSummary] = []
    /// The services left out, with the reason.
    var notChecked: [QSLProvider: String] = [:]
}

/// The report of an upload run, one line per service: uploaded, already there, failed, blocked, or not checked
/// (switched off or without credentials). It never says complete or successful when something failed, was
/// blocked, was left waiting, was not checked, or a download failed or did not run.
nonisolated enum QSLSyncReport {
    /// The summaries of a run with what was there before it: the QSOs already at each service, and the jobs left
    /// stopped by an earlier run (blocked, or failed five times), which only Retry Failed Uploads or new credentials
    /// send again.
    static func withPriorState(
        _ summaries: [QSLPassSummary],
        providers: Set<QSLProvider>,
        alreadyThere: [QSLProvider: Int],
        leftover: [QSLProvider: (blocked: Int, failed: Int)]
    ) -> [QSLPassSummary] {
        QSLProvider.allCases.filter { providers.contains($0) }.map { provider in
            var summary = summaries.first(where: { $0.provider == provider }) ?? QSLPassSummary(provider: provider)
            summary.alreadyThere += alreadyThere[provider] ?? 0
            if let stopped = leftover[provider], stopped.blocked + stopped.failed > 0 {
                summary.blocked += stopped.blocked
                summary.failed += stopped.failed
                summary.stoppedEarlier = "\(stopped.blocked + stopped.failed) stopped by an earlier run (\(stopped.blocked) " +
                    "with rejected credentials, \(stopped.failed) failed five times): use Retry Failed Uploads"
            }
            return summary
        }
    }

    static func lines(_ run: QSLSyncUploadRun) -> [(text: String, problem: Bool)] {
        QSLProvider.allCases.map { provider in
            if let reason = run.notChecked[provider] { return ("\(provider.title): not checked (\(reason))", false) }
            guard let summary = run.summaries.first(where: { $0.provider == provider }) else {
                return ("\(provider.title): nothing to upload", false)
            }
            var parts = ["\(summary.sent) uploaded", "\(summary.alreadyThere) already there"]
            if summary.retry > 0 { parts.append("\(summary.retry) failed, to be tried again") }
            if summary.failed > 0 { parts.append("\(summary.failed) failed") }
            if summary.blocked > 0 { parts.append("\(summary.blocked) blocked") }
            if summary.notSent > 0 {
                parts.append("\(summary.notSent) not sent (\(summary.notSentReason)), will be tried at the next Sync")
            }
            var text = "\(provider.title): " + parts.joined(separator: ", ")
            if summary.hasProblems, !summary.firstProblem.isEmpty { text += ". \(summary.firstProblem)" }
            if !summary.stoppedEarlier.isEmpty { text += ". \(summary.stoppedEarlier)" }
            return (text, summary.hasProblems)
        }
    }

    /// One short line for the QSL Hub status.
    static func status(_ run: QSLSyncUploadRun) -> String {
        if run.busy { return "Another upload is running; nothing was done" }
        if run.summaries.isEmpty, !run.notChecked.isEmpty {
            let reasons = Set(run.notChecked.values)
            if run.notChecked.count == QSLProvider.allCases.count, reasons.count == 1, let reason = reasons.first {
                return "Nothing uploaded: \(reason)"
            }
            let names = QSLProvider.allCases.filter { run.notChecked[$0] != nil }.map(\.title).joined(separator: ", ")
            return "Nothing uploaded; not checked: \(names)"
        }
        let sent = run.summaries.reduce(0) { $0 + $1.sent }
        let already = run.summaries.reduce(0) { $0 + $1.alreadyThere }
        if run.summaries.contains(where: \.hasProblems) {
            let names = run.summaries.filter(\.hasProblems).map(\.provider.title).joined(separator: ", ")
            return "Uploads finished with problems (\(names)): \(sent) uploaded, \(already) already there"
        }
        if !run.notChecked.isEmpty {
            let names = QSLProvider.allCases.filter { run.notChecked[$0] != nil }.map(\.title).joined(separator: ", ")
            return "Uploads done: \(sent) uploaded, \(already) already there; not checked: \(names)"
        }
        return "Uploads done: \(sent) uploaded, \(already) already there"
    }

    /// Which downloads can run, with the same tests as each download: LoTW needs its username and web password, QRZ
    /// the station's API key, eQSL.cc its username and password, Club Log its email, password and API key.
    static func downloadReadiness(
        lotwUsername: String,
        lotwPassword: String,
        qrzAPIKey: String,
        eqsl: QSLServiceCredentials,
        clubLog: QSLServiceCredentials
    ) -> (lotw: Bool, qrz: Bool, eqsl: Bool, clubLog: Bool) {
        (lotw: !lotwUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !lotwPassword.isEmpty,
         qrz: !qrzAPIKey.isEmpty,
         eqsl: !eqsl.eqslUsername.isEmpty && !eqsl.eqslPassword.isEmpty,
         clubLog: !clubLog.clubLogEmail.isEmpty && !clubLog.clubLogPassword.isEmpty && !clubLog.clubLogAPIKey.isEmpty)
    }

    /// The downloads Sync All cannot check (see downloadReadiness).
    static func downloadsNotChecked(lotwReady: Bool, qrzReady: Bool, eqslReady: Bool, clubLogReady: Bool) -> [String] {
        var names: [String] = []
        if !lotwReady { names.append("LoTW download (no LoTW username or password)") }
        if !qrzReady { names.append("QRZ download (no QRZ Logbook API key)") }
        if !eqslReady { names.append("eQSL.cc download (no eQSL username or password)") }
        if !clubLogReady { names.append("Club Log download (no email, password or API key)") }
        return names
    }

    /// What went wrong in the downloads: a failed LoTW or QRZ download; a LoTW and QRZ download that did not run at
    /// all although one of them was ready (for example another download or a log import was running, or the log
    /// changed); and the errors the eQSL.cc and Club Log downloads logged.
    static func downloadProblems(lotwQRZ summary: ConfirmationSyncSummary?, lotwOrQRZReady: Bool, otherErrors: Int) -> [String] {
        var problems: [String] = []
        if let summary {
            if summary.lotwFailed { problems.append("LoTW download failed: \(summary.lotwMessage)") }
            if summary.qrzFailed { problems.append("QRZ download failed: \(summary.qrzMessage)") }
            if lotwOrQRZReady, summary == ConfirmationSyncSummary() {
                problems.append("LoTW and QRZ download did not run (see the LoTW / QRZ lines and the app log)")
            }
        } else if lotwOrQRZReady {
            problems.append("LoTW and QRZ download did not report")
        }
        if otherErrors > 0 { problems.append("\(otherErrors) download error(s), see the lines above") }
        return problems
    }

    /// The last line of Sync All. "successfully" only when no upload failed, was blocked or was left waiting, no
    /// download failed, and no service was left out of the uploads or the downloads.
    static func finalLine(
        upload: QSLSyncUploadRun,
        downloadProblems: [String],
        downloadsNotChecked: [String],
        updated: Int
    ) -> (text: String, problems: Bool, complete: Bool) {
        if upload.busy || upload.summaries.contains(where: \.hasProblems) || !downloadProblems.isEmpty {
            return ("Sync finished with problems: see the lines above. \(updated) confirmed QSO(s) updated.", true, false)
        }
        if !upload.notChecked.isEmpty || !downloadsNotChecked.isEmpty {
            return ("Sync finished; not every service was checked (see above). \(updated) confirmed QSO(s) updated.", false, false)
        }
        return ("All services synchronized successfully! \(updated) QSOs updated.", false, true)
    }

    /// The end of Sync All, from what it saw: the upload run, which downloads were ready, the LoTW and QRZ download's own
    /// summary, the errors the other downloads logged, and whether the downloads were skipped because the open log
    /// stopped being the station's own during the uploads (R16). The sync engine logs what this returns.
    static func endOfSync(
        upload: QSLSyncUploadRun,
        readiness: (lotw: Bool, qrz: Bool, eqsl: Bool, clubLog: Bool),
        lotwQRZ: ConfirmationSyncSummary?,
        otherErrors: Int,
        updated: Int,
        downloadsSkipped: String? = nil
    ) -> (downloadProblems: [String], downloadsNotChecked: [String], text: String, problems: Bool, complete: Bool) {
        if let downloadsSkipped {
            let problems = ["Sync stopped after the uploads: \(downloadsSkipped); downloads not run"]
            let end = finalLine(upload: upload, downloadProblems: problems, downloadsNotChecked: [], updated: updated)
            return (problems, [], end.text, end.problems, end.complete)
        }
        let notChecked = downloadsNotChecked(
            lotwReady: readiness.lotw,
            qrzReady: readiness.qrz,
            eqslReady: readiness.eqsl,
            clubLogReady: readiness.clubLog
        )
        let problems = downloadProblems(lotwQRZ: lotwQRZ, lotwOrQRZReady: readiness.lotw || readiness.qrz, otherErrors: otherErrors)
        let end = finalLine(upload: upload, downloadProblems: problems, downloadsNotChecked: notChecked, updated: updated)
        return (problems, notChecked, end.text, end.problems, end.complete)
    }
}
