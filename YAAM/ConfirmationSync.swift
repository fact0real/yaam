//
//  ConfirmationSync.swift
//  YAAM
//

import Foundation

nonisolated struct ConfirmationSyncCheckpoint: Codable, Equatable, Sendable {
    var baselineCompleted = false
    var lotwCursor: String?
    var lastSuccess: Date?
}

nonisolated enum ConfirmationSyncCheckpointStore {
    // v3 invalidates baselines created before QRZ ADIF payloads were parsed atomically.
    private static let schema = "v3"

    static func load(profileID: UUID, source: SyncSource) -> ConfirmationSyncCheckpoint {
        guard let data = UserDefaults.standard.data(forKey: key(profileID: profileID, source: source)),
              let checkpoint = try? JSONDecoder().decode(ConfirmationSyncCheckpoint.self, from: data) else {
            return ConfirmationSyncCheckpoint()
        }
        return checkpoint
    }

    static func save(_ checkpoint: ConfirmationSyncCheckpoint, profileID: UUID, source: SyncSource) {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        UserDefaults.standard.set(data, forKey: key(profileID: profileID, source: source))
    }

    private static func key(profileID: UUID, source: SyncSource) -> String {
        "confirmationSync.\(schema).\(profileID.uuidString).\(source.rawValue)"
    }
}

nonisolated struct ConfirmationFetchOutcome: Sendable {
    let source: SyncSource
    let records: [[String: String]]
    let nextCursor: String?
    let reportedCount: Int?
    let pageCount: Int
    let detail: String

    init(
        source: SyncSource,
        records: [[String: String]],
        nextCursor: String?,
        reportedCount: Int? = nil,
        pageCount: Int = 1,
        detail: String
    ) {
        self.source = source
        self.records = records
        self.nextCursor = nextCursor
        self.reportedCount = reportedCount
        self.pageCount = pageCount
        self.detail = detail
    }
}

nonisolated struct ConfirmationFetchAttempt: Sendable {
    let outcome: ConfirmationFetchOutcome?
    let errorMessage: String?

    static let skipped = ConfirmationFetchAttempt(outcome: nil, errorMessage: nil)
}

nonisolated enum ConfirmationDownloadError: LocalizedError, Sendable {
    case invalidEndpoint
    case invalidResponse(String)
    case service(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The confirmation service address is invalid."
        case .invalidResponse(let message), .service(let message):
            return message
        }
    }
}

nonisolated enum ConfirmationDownloadService {
    private static let qrzPageSize = 250

    static func attemptLoTW(
        enabled: Bool,
        username: String,
        password: String,
        cursor: String?,
        ownCallsign: String,
        userAgent: String
    ) async -> ConfirmationFetchAttempt {
        guard enabled else { return .skipped }
        do {
            return ConfirmationFetchAttempt(
                outcome: try await fetchLoTW(
                    username: username,
                    password: password,
                    cursor: cursor,
                    ownCallsign: ownCallsign,
                    userAgent: userAgent
                ),
                errorMessage: nil
            )
        } catch {
            return ConfirmationFetchAttempt(outcome: nil, errorMessage: error.localizedDescription)
        }
    }

    static func attemptQRZ(
        enabled: Bool,
        apiKey: String,
        modifiedSince: Date?,
        userAgent: String
    ) async -> ConfirmationFetchAttempt {
        guard enabled else { return .skipped }
        do {
            return ConfirmationFetchAttempt(
                outcome: try await fetchQRZ(
                    apiKey: apiKey,
                    modifiedSince: modifiedSince,
                    userAgent: userAgent
                ),
                errorMessage: nil
            )
        } catch {
            return ConfirmationFetchAttempt(outcome: nil, errorMessage: error.localizedDescription)
        }
    }

    static func fetchLoTW(
        username: String,
        password: String,
        cursor: String?,
        ownCallsign: String,
        userAgent: String
    ) async throws -> ConfirmationFetchOutcome {
        guard var components = URLComponents(string: "https://lotw.arrl.org/lotwuser/lotwreport.adi") else {
            throw ConfirmationDownloadError.invalidEndpoint
        }
        var queryItems = [
            URLQueryItem(name: "login", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "qso_query", value: "1"),
            URLQueryItem(name: "qso_qsl", value: "yes"),
            URLQueryItem(name: "qso_qslsince", value: cursor ?? "1900-01-01"),
            URLQueryItem(name: "qso_qsldetail", value: "yes"),
            URLQueryItem(name: "qso_withown", value: "yes")
        ]
        let normalizedOwnCallsign = ownCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !normalizedOwnCallsign.isEmpty {
            queryItems.append(URLQueryItem(name: "qso_owncall", value: normalizedOwnCallsign))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw ConfirmationDownloadError.invalidEndpoint }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 90)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)

        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ConfirmationDownloadError.invalidResponse("LoTW returned an unreadable response.")
        }
        let lower = text.lowercased()
        if lower.contains("invalid password") || lower.contains("access denied") || lower.contains("password incorrect") {
            throw ConfirmationDownloadError.service("LoTW rejected the saved username or password.")
        }
        guard lower.contains("<eoh") else {
            throw ConfirmationDownloadError.invalidResponse("LoTW did not return a valid ADIF report.")
        }

        let (_, records) = parseADIF(content: text)
        let nextCursor = adifHeaderValue(named: "APP_LOTW_LASTQSL", in: text)
            ?? adifHeaderValue(named: "APP_LoTW_LASTQSL", in: text)
        let reportedCount = adifHeaderValue(named: "APP_LOTW_NUMREC", in: text).flatMap(Int.init)
        if let reportedCount, records.count < reportedCount {
            throw ConfirmationDownloadError.invalidResponse(
                "LoTW reported \(reportedCount) confirmation record(s), but only \(records.count) were decoded. The baseline was not saved as complete."
            )
        }
        return ConfirmationFetchOutcome(
            source: .lotw,
            records: records,
            nextCursor: nextCursor,
            reportedCount: reportedCount,
            detail: "LoTW returned \(records.count) confirmed QSL record(s) for \(normalizedOwnCallsign.isEmpty ? "the account" : normalizedOwnCallsign)."
        )
    }

    static func fetchQRZ(
        apiKey: String,
        modifiedSince: Date?,
        userAgent: String
    ) async throws -> ConfirmationFetchOutcome {
        guard let endpoint = URL(string: "https://logbook.qrz.com/api") else {
            throw ConfirmationDownloadError.invalidEndpoint
        }

        var allRecords: [[String: String]] = []
        var afterLogID = 0
        var page = 0
        var totalReportedCount: Int?
        let modifiedSinceValue = modifiedSince.map(qrzDateFormatter.string(from:))

        while page < 2_000 {
            page += 1
            var options = [
                "TYPE:ADIF",
                "STATUS:CONFIRMED",
                "MAX:\(qrzPageSize)",
                "AFTERLOGID:\(afterLogID)"
            ]
            if let modifiedSinceValue { options.append("MODSINCE:\(modifiedSinceValue)") }

            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 90)
            request.httpMethod = "POST"
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formBody([
                URLQueryItem(name: "KEY", value: apiKey),
                URLQueryItem(name: "ACTION", value: "FETCH"),
                URLQueryItem(name: "OPTION", value: options.joined(separator: ","))
            ])

            let (data, httpResponse) = try await URLSession.shared.data(for: request)
            try validateHTTP(httpResponse)
            guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw ConfirmationDownloadError.invalidResponse("QRZ returned an unreadable response.")
            }
            let parsedResponse = parseQRZResponse(raw)
            let result = parsedResponse.result
            let count = parsedResponse.count
            let reason = parsedResponse.reason
            if totalReportedCount == nil, result == "OK" {
                totalReportedCount = count
            }

            if result != "OK" {
                let noRecords = count == 0 && (
                    reason.localizedCaseInsensitiveContains("no record") ||
                    reason.localizedCaseInsensitiveContains("not found") ||
                    (reason.isEmpty && parsedResponse.adif.isEmpty)
                )
                if noRecords { break }
                throw ConfirmationDownloadError.service(
                    reason.isEmpty ? "QRZ Logbook returned RESULT=\(result)." : "QRZ Logbook: \(reason)"
                )
            }

            let (_, pageRecords) = parseADIF(content: parsedResponse.adif)
            if pageRecords.isEmpty {
                if count == 0 { break }
                throw ConfirmationDownloadError.invalidResponse(
                    "QRZ reported \(count) matching record(s), but the ADIF payload on page \(page) could not be decoded."
                )
            }
            allRecords.append(contentsOf: pageRecords)

            if let totalReportedCount, allRecords.count >= totalReportedCount {
                break
            }

            let logIDs = pageRecords.compactMap { record -> Int? in
                let rawValue = record["APP_QRZLOG_LOGID"] ?? record["APP_QRZ_LOGID"] ?? record["LOGID"]
                return rawValue.flatMap { Int($0.filter(\.isNumber)) }
            }
            guard pageRecords.count >= qrzPageSize else {
                break
            }
            guard let highestLogID = logIDs.max(), highestLogID >= afterLogID else {
                throw ConfirmationDownloadError.invalidResponse(
                    "QRZ returned a full page without APP_QRZLOG_LOGID, so the remaining confirmation history could not be paged safely."
                )
            }
            afterLogID = highestLogID + 1
        }

        if page >= 2_000 {
            throw ConfirmationDownloadError.invalidResponse("QRZ confirmation paging exceeded the safety limit.")
        }
        if let totalReportedCount, allRecords.count < totalReportedCount {
            throw ConfirmationDownloadError.invalidResponse(
                "QRZ reported \(totalReportedCount) matching record(s), but only \(allRecords.count) were downloaded. The baseline was not saved as complete."
            )
        }

        return ConfirmationFetchOutcome(
            source: .qrz,
            records: allRecords,
            nextCursor: nil,
            reportedCount: totalReportedCount,
            pageCount: page,
            detail: "QRZ returned \(allRecords.count) confirmed logbook record(s) in \(page) page(s)."
        )
    }

    private static let qrzDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw ConfirmationDownloadError.service("The service returned HTTP \(http.statusCode).")
        }
    }

    private static func formBody(_ items: [URLQueryItem]) -> Data? {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private static func formValues(_ raw: String) -> [String: String] {
        var values: [String: String] = [:]
        for component in raw.split(separator: "&", omittingEmptySubsequences: false) {
            let pair = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = pair.first else { continue }
            let rawValue = pair.count > 1 ? String(pair[1]) : ""
            let key = decodeFormComponent(String(rawKey)).uppercased()
            values[key] = decodeFormComponent(rawValue)
        }
        return values
    }

    static func parseQRZResponse(_ raw: String) -> (result: String, count: Int, reason: String, adif: String) {
        let adifMarker = raw.range(of: "ADIF=", options: .caseInsensitive)
        let metadataText = adifMarker.map { String(raw[..<$0.lowerBound]) } ?? raw
        let values = formValues(metadataText)
        let rawADIF = adifMarker.map { String(raw[$0.upperBound...]) } ?? ""
        let decodedADIF = decodeHTMLEntities(decodeFormComponent(rawADIF))
        return (
            result: (values["RESULT"] ?? "").uppercased(),
            count: Int(values["COUNT"] ?? "0") ?? 0,
            reason: values["REASON"] ?? values["MESSAGE"] ?? "",
            adif: decodedADIF
        )
    }

    private static func decodeFormComponent(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
    }

    private static func adifHeaderValue(named name: String, in text: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "<\\s*\(escapedName)\\s*:\\s*(\\d+)(?:[^>]*)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let searchRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: searchRange),
              let tagRange = Range(match.range(at: 0), in: text),
              let lengthRange = Range(match.range(at: 1), in: text),
              let length = Int(text[lengthRange]) else { return nil }
        let valueStart = tagRange.upperBound
        guard let valueEnd = text.index(valueStart, offsetBy: length, limitedBy: text.endIndex) else { return nil }
        return String(text[valueStart..<valueEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated struct ConfirmationMergeResult: Sendable {
    let records: [QSORecordModel]
    let lotwChanged: Int
    let qrzChanged: Int
    let lotwMatched: Int
    let qrzMatched: Int
    let lotwUnmatched: Int
    let qrzUnmatched: Int
    let lotwUnmatchedRecords: [[String: String]]
    let qrzUnmatchedRecords: [[String: String]]
    let changedRecordIDs: Set<UUID>
}

nonisolated enum ConfirmationMergeEngine {
    // LoTW itself accepts QSO start times within 30 minutes of each other.
    private static let maximumTimeDifference = 30 * 60

    static func merge(
        localRecords: [QSORecordModel],
        lotwRecords: [[String: String]],
        qrzRecords: [[String: String]]
    ) -> ConfirmationMergeResult {
        var output = localRecords
        let index = Dictionary(grouping: output.indices, by: { baseKey(output[$0].fields) })
        var changedIDs = Set<UUID>()
        var lotwChanged = 0
        var qrzChanged = 0
        var lotwMatched = 0
        var qrzMatched = 0
        var lotwClaimed = Set<Int>()
        var qrzClaimed = Set<Int>()
        var lotwUnmatchedRecords: [[String: String]] = []
        var qrzUnmatchedRecords: [[String: String]] = []

        for incoming in lotwRecords {
            guard let target = bestMatch(incoming, in: output, index: index, excluding: lotwClaimed) else {
                lotwUnmatchedRecords.append(incoming)
                continue
            }
            lotwClaimed.insert(target)
            lotwMatched += 1
            var changed = false
            changed = set("LOTW_QSL_RCVD", to: "Y", in: &output[target]) || changed
            changed = set("QSL_RCVD", to: "Y", in: &output[target]) || changed
            if let date = confirmationDate(incoming, provider: .lotw) {
                changed = set("LOTW_QSLRDATE", to: date, in: &output[target]) || changed
            }
            if changed {
                lotwChanged += 1
                changedIDs.insert(output[target].id)
            }
        }

        for incoming in qrzRecords {
            guard let target = bestMatch(incoming, in: output, index: index, excluding: qrzClaimed) else {
                qrzUnmatchedRecords.append(incoming)
                continue
            }
            qrzClaimed.insert(target)
            qrzMatched += 1
            var changed = false
            changed = set("QRZLOG_QSL_RCVD", to: "Y", in: &output[target]) || changed
            changed = set("QSL_RCVD", to: "Y", in: &output[target]) || changed
            changed = set("APP_QRZLOG_STATUS", to: "C", in: &output[target]) || changed
            if let date = confirmationDate(incoming, provider: .qrz) {
                changed = set("APP_QRZLOG_QSLDATE", to: date, in: &output[target]) || changed
            }
            if changed {
                qrzChanged += 1
                changedIDs.insert(output[target].id)
            }
        }

        return ConfirmationMergeResult(
            records: output,
            lotwChanged: lotwChanged,
            qrzChanged: qrzChanged,
            lotwMatched: lotwMatched,
            qrzMatched: qrzMatched,
            lotwUnmatched: lotwUnmatchedRecords.count,
            qrzUnmatched: qrzUnmatchedRecords.count,
            lotwUnmatchedRecords: lotwUnmatchedRecords,
            qrzUnmatchedRecords: qrzUnmatchedRecords,
            changedRecordIDs: changedIDs
        )
    }

    private static func bestMatch(
        _ incoming: [String: String],
        in local: [QSORecordModel],
        index: [String: [Int]],
        excluding claimed: Set<Int>
    ) -> Int? {
        let base = baseKey(incoming)
        let baseParts = base.split(separator: "|", omittingEmptySubsequences: false)
        guard baseParts.count == 2,
            !baseParts[0].isEmpty,
              baseParts[1].count == 8 else { return nil }

        var candidates = index[base]?.filter { !claimed.contains($0) } ?? []
        if candidates.isEmpty, let date = date(baseParts[1]) {
            // Some exports use local time near midnight. Preserve strict matching first,
            // then consider the adjacent UTC day only when the time and radio fields agree.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
            let adjacentKeys = [-1, 1].compactMap { offset -> String? in
                guard let adjusted = calendar.date(byAdding: .day, value: offset, to: date) else { return nil }
                return "\(baseParts[0])|\(adifDate(adjusted))"
            }
            candidates = adjacentKeys.flatMap { index[$0] ?? [] }.filter { !claimed.contains($0) }
        }
        guard !candidates.isEmpty else { return nil }

        let incomingBand = resolvedBand(incoming)
        if !incomingBand.isEmpty {
            let bandMatches = candidates.filter { resolvedBand(local[$0].fields) == incomingBand }
            if !bandMatches.isEmpty {
                candidates = bandMatches
            } else {
                let missingLocalBand = candidates.filter { resolvedBand(local[$0].fields).isEmpty }
                guard !missingLocalBand.isEmpty else { return nil }
                candidates = missingLocalBand
            }
        }

        if let incomingSeconds = seconds(incoming["TIME_ON"] ?? incoming["TIME_OFF"] ?? "") {
            let timed = candidates.compactMap { candidate -> (Int, Int)? in
                guard let localSeconds = seconds(local[candidate]["TIME_ON"].isEmpty ? local[candidate]["TIME_OFF"] : local[candidate]["TIME_ON"]) else {
                    return nil
                }
                return (candidate, abs(localSeconds - incomingSeconds))
            }
            let nearby = timed.filter { $0.1 <= maximumTimeDifference }
            guard let minimum = nearby.map(\.1).min() else { return nil }
            candidates = nearby.filter { $0.1 == minimum }.map(\.0)
        }

        let incomingModes = modeTokens(incoming)
        if candidates.count > 1, !incomingModes.isEmpty {
            let modeMatches = candidates.filter { !modeTokens(local[$0].fields).isDisjoint(with: incomingModes) }
            if !modeMatches.isEmpty { candidates = modeMatches }
        }

        if candidates.count > 1,
           seconds(incoming["TIME_ON"] ?? incoming["TIME_OFF"] ?? "") == nil {
            let identities = Set(candidates.map { exactIdentity(local[$0].fields) })
            guard identities.count == 1 else { return nil }
        }

        return candidates.min { lhs, rhs in
            if local[lhs].index != local[rhs].index { return local[lhs].index < local[rhs].index }
            return lhs < rhs
        }
    }

    private static func set(_ field: String, to value: String, in record: inout QSORecordModel) -> Bool {
        guard record[field].uppercased() != value.uppercased() else { return false }
        record.fields[field] = value
        return true
    }

    private static func baseKey(_ fields: [String: String]) -> String {
        let call = clean(fields["CALL"] ?? "")
        let date = (fields["QSO_DATE"] ?? "").filter(\.isNumber)
        return "\(call)|\(date)"
    }

    private static func exactIdentity(_ fields: [String: String]) -> String {
        "\(baseKey(fields))|\(normalizeTime(fields["TIME_ON"] ?? fields["TIME_OFF"] ?? ""))|\(resolvedBand(fields))|\(modeTokens(fields).sorted().joined(separator: ","))"
    }

    private static func resolvedBand(_ fields: [String: String]) -> String {
        ADIFConversionFilter.resolvedBand(for: fields).uppercased()
    }

    private static func modeTokens(_ fields: [String: String]) -> Set<String> {
        var values = Set([fields["MODE"], fields["SUBMODE"], fields["APP_LOTW_MODE"]]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty })
        for value in Array(values) {
            if ["FT8", "FT4", "JS8"].contains(value) { values.insert("MFSK") }
            if ["USB", "LSB"].contains(value) { values.insert("SSB") }
            if value.hasPrefix("PSK") { values.insert("PSK") }
        }
        return values
    }

    private static func seconds(_ raw: String) -> Int? {
        let value = normalizeTime(raw)
        guard value.count == 6,
              let hour = Int(value.prefix(2)),
              let minute = Int(value.dropFirst(2).prefix(2)),
              let second = Int(value.suffix(2)),
              hour < 24, minute < 60, second < 60 else { return nil }
        return hour * 3_600 + minute * 60 + second
    }

    private static func confirmationDate(_ record: [String: String], provider: SyncSource) -> String? {
        let candidates: [String?]
        if provider == .lotw {
            candidates = [record["LOTW_QSLRDATE"], record["APP_LOTW_QSLRDATE"], record["QSLRDATE"]]
        } else {
            candidates = [record["APP_QRZLOG_QSLDATE"], record["QRZLOG_QSLRDATE"], record["APP_QRZLOG_QSLRDATE"], record["QSLRDATE"]]
        }
        return candidates.compactMap { value -> String? in
            let clean = (value ?? "").filter(\.isNumber)
            return clean.count >= 8 ? String(clean.prefix(8)) : nil
        }.first
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func date(_ raw: Substring) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: String(raw))
    }

    private static func adifDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}

extension AppState {
    func syncConfirmations(
        forceFullSync: Bool = false,
        sources: Set<SyncSource> = [.lotw, .qrz],
        showCompletionAlert: Bool = true,
        completion: ((ConfirmationSyncSummary) -> Void)? = nil
    ) {
        guard !qsoRecords.isEmpty else {
            appendLog("Confirmation sync needs a loaded logbook.")
            completion?(ConfirmationSyncSummary())
            return
        }
        guard !isSyncingAPI else {
            appendLog("Confirmation sync is already running.")
            completion?(ConfirmationSyncSummary())
            return
        }
        guard let profileID = activeStationProfileID else {
            alertTitle = "Station Required"
            alertMessage = "Choose an active station profile before syncing confirmations."
            showAlert = true
            completion?(ConfirmationSyncSummary())
            return
        }

        let lotwUsername = UserDefaults.standard.string(forKey: "lotwUsername")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lotwPassword = CredentialVault.value(for: .lotwPassword)
        let qrzAPIKey = activeQRZAPIKey
        let requestedLoTW = sources.contains(.lotw)
        let requestedQRZ = sources.contains(.qrz)
        let syncLoTW = requestedLoTW && !lotwUsername.isEmpty && !lotwPassword.isEmpty
        let syncQRZ = requestedQRZ && !qrzAPIKey.isEmpty

        guard syncLoTW || syncQRZ else {
            alertTitle = "Credentials Required"
            alertMessage = "Configure LoTW or QRZ Logbook credentials for the selected source in Settings."
            showAlert = true
            playActivitySound(.failure)
            completion?(ConfirmationSyncSummary())
            return
        }

        for header in [
            "LOTW_QSL_RCVD", "LOTW_QSLRDATE", "QRZLOG_QSL_RCVD",
            "APP_QRZLOG_QSLDATE", "APP_QRZLOG_STATUS", "QSL_RCVD"
        ] where !tableHeaders.contains(header) {
            tableHeaders.append(header)
        }

        let lotwCheckpoint = ConfirmationSyncCheckpointStore.load(profileID: profileID, source: .lotw)
        let qrzCheckpoint = ConfirmationSyncCheckpointStore.load(profileID: profileID, source: .qrz)
        let fullLoTW = forceFullSync || !lotwCheckpoint.baselineCompleted
        let fullQRZ = forceFullSync || !qrzCheckpoint.baselineCompleted
        let lotwCursor = fullLoTW ? nil : lotwCheckpoint.lotwCursor
        let qrzModifiedSince = fullQRZ ? nil : qrzCheckpoint.lastSuccess
        let ownCallsign = currentStationCallsign
        let userAgent = "YAAM-macOS/\(currentVersion)"

        if requestedLoTW, !syncLoTW {
            appendLog("LoTW confirmation sync skipped: add the LoTW username and password in Settings.")
        }
        if requestedQRZ, !syncQRZ {
            appendLog("QRZ confirmation sync skipped: add the QRZ Logbook API key to the active station profile.")
        }

        isSyncingAPI = true
        if syncLoTW {
            beginSyncStatus(.lotw, detail: fullLoTW ? "Building the full LoTW confirmation baseline..." : "Downloading new LoTW confirmations...")
        }
        if syncQRZ {
            beginSyncStatus(.qrz, detail: fullQRZ ? "Building the full QRZ confirmation baseline..." : "Downloading new QRZ confirmations...")
        }
        let scope = forceFullSync || fullLoTW || fullQRZ ? "full baseline" : "incremental"
        appendLog("Starting \(scope) confirmation sync for \(currentStationCallsign).")

        Task { @MainActor [weak self] in
            guard let self else { return }
            async let lotwAttempt = ConfirmationDownloadService.attemptLoTW(
                enabled: syncLoTW,
                username: lotwUsername,
                password: lotwPassword,
                cursor: lotwCursor,
                ownCallsign: ownCallsign,
                userAgent: userAgent
            )
            async let qrzAttempt = ConfirmationDownloadService.attemptQRZ(
                enabled: syncQRZ,
                apiKey: qrzAPIKey,
                modifiedSince: qrzModifiedSince,
                userAgent: userAgent
            )
            let (lotw, qrz) = await (lotwAttempt, qrzAttempt)

            guard self.activeStationProfileID == profileID else {
                self.isSyncingAPI = false
                self.appendLog("Confirmation sync stopped because the active station changed.")
                completion?(ConfirmationSyncSummary())
                return
            }

            let recordsToMerge = self.qsoRecords
            let mergeResult = await Task.detached(priority: .userInitiated) {
                ConfirmationMergeEngine.merge(
                    localRecords: recordsToMerge,
                    lotwRecords: lotw.outcome?.records ?? [],
                    qrzRecords: qrz.outcome?.records ?? []
                )
            }.value

            let now = Date()
            let lotwFailed = syncLoTW && lotw.errorMessage != nil
            let qrzFailed = syncQRZ && qrz.errorMessage != nil
            let lotwFetched = lotw.outcome?.records.count ?? 0
            let qrzFetched = qrz.outcome?.records.count ?? 0
            let lotwReported = lotw.outcome?.reportedCount ?? lotwFetched
            let qrzReported = qrz.outcome?.reportedCount ?? qrzFetched

            if let outcome = lotw.outcome {
                var checkpoint = lotwCheckpoint
                checkpoint.baselineCompleted = true
                checkpoint.lastSuccess = now
                checkpoint.lotwCursor = outcome.nextCursor ?? Self.lotwFallbackCursor(now)
                ConfirmationSyncCheckpointStore.save(checkpoint, profileID: profileID, source: .lotw)
                UserDefaults.standard.set(now, forKey: "lastLoTWSyncDate")
                self.appendLog(outcome.detail)
            } else if let message = lotw.errorMessage {
                self.appendLog("LoTW confirmation sync failed: \(message)")
            }

            if let outcome = qrz.outcome {
                var checkpoint = qrzCheckpoint
                checkpoint.baselineCompleted = true
                checkpoint.lastSuccess = now
                ConfirmationSyncCheckpointStore.save(checkpoint, profileID: profileID, source: .qrz)
                UserDefaults.standard.set(now, forKey: "lastQRZSyncDate")
                self.appendLog(outcome.detail)
            } else if let message = qrz.errorMessage {
                self.appendLog("QRZ confirmation sync failed: \(message)")
            }

            var importedConfirmedRecords = 0
            if !mergeResult.changedRecordIDs.isEmpty || !mergeResult.lotwUnmatchedRecords.isEmpty || !mergeResult.qrzUnmatchedRecords.isEmpty {
                self.qsoRecords = mergeResult.records
                let changedRecords = mergeResult.records.filter { mergeResult.changedRecordIDs.contains($0.id) }
                self.rememberConfirmedRecords(changedRecords)
                importedConfirmedRecords = self.importRemoteConfirmationRecords(
                    lotw: lotwFailed ? [] : mergeResult.lotwUnmatchedRecords,
                    qrz: qrzFailed ? [] : mergeResult.qrzUnmatchedRecords
                )
                self.autoSaveActiveWorkspace()
                self.refreshAwardProgress()
            }

            let lotwMessage = lotwFailed
                ? (lotw.errorMessage ?? "LoTW synchronization failed")
                : "\(lotwFetched) downloaded, \(mergeResult.lotwMatched) matched, \(mergeResult.lotwUnmatched) unmatched, \(mergeResult.lotwChanged) updated"
            let qrzMessage = qrzFailed
                ? (qrz.errorMessage ?? "QRZ synchronization failed")
                : "\(qrzFetched) downloaded, \(mergeResult.qrzMatched) matched, \(mergeResult.qrzUnmatched) unmatched, \(mergeResult.qrzChanged) updated"

            if syncLoTW {
                self.finishSyncStatus(
                    .lotw,
                    state: lotwFailed ? .failure : .success,
                    detail: lotwMessage,
                    changed: mergeResult.lotwChanged
                )
            }
            if syncQRZ {
                self.finishSyncStatus(
                    .qrz,
                    state: qrzFailed ? .failure : .success,
                    detail: qrzMessage,
                    changed: mergeResult.qrzChanged
                )
            }

            let summary = ConfirmationSyncSummary(
                lotwFetched: lotwFetched,
                qrzFetched: qrzFetched,
                lotwReported: lotwReported,
                qrzReported: qrzReported,
                lotwMatched: mergeResult.lotwMatched,
                qrzMatched: mergeResult.qrzMatched,
                lotwUnmatched: mergeResult.lotwUnmatched,
                qrzUnmatched: mergeResult.qrzUnmatched,
                lotwChanged: mergeResult.lotwChanged,
                qrzChanged: mergeResult.qrzChanged,
                lotwMessage: lotwMessage,
                qrzMessage: qrzMessage,
                lotwFailed: lotwFailed,
                qrzFailed: qrzFailed
            )
            self.updateConfirmationReconciliation(with: summary)
            self.isSyncingAPI = false

            if showCompletionAlert {
                self.alertTitle = lotwFailed || qrzFailed
                    ? "Confirmation Sync Incomplete"
                    : (summary.changed > 0 ? "Confirmations Updated" : "Confirmations Up to Date")
                var reportLines: [String] = []
                if syncLoTW {
                    reportLines.append(lotwFailed
                        ? "LoTW: \(lotwMessage)"
                        : "LoTW: \(lotwFetched.formatted()) downloaded, \(mergeResult.lotwMatched.formatted()) matched, \(mergeResult.lotwUnmatched.formatted()) unmatched, \(mergeResult.lotwChanged.formatted()) updated.")
                } else if requestedLoTW {
                    reportLines.append("LoTW: skipped because its username or password is missing in Settings.")
                }
                if syncQRZ {
                    reportLines.append(qrzFailed
                        ? "QRZ: \(qrzMessage)"
                        : "QRZ: \(qrzFetched.formatted()) downloaded, \(mergeResult.qrzMatched.formatted()) matched, \(mergeResult.qrzUnmatched.formatted()) unmatched, \(mergeResult.qrzChanged.formatted()) updated.")
                } else if requestedQRZ {
                    reportLines.append("QRZ: skipped because the active station has no QRZ Logbook API key.")
                }
                if !lotwFailed, !qrzFailed, summary.unmatched > 0 {
                    reportLines.append("\(importedConfirmedRecords.formatted()) confirmed QSO(s) absent from the local log were added and marked with their cloud source. Remaining unmatched records belong to another station log or do not contain enough QSO detail to import safely.")
                }
                self.alertMessage = reportLines.joined(separator: "\n")
                self.showAlert = true
            }
            self.appendLog("Confirmation sync finished: \(summary.matched) of \(summary.fetched) cloud record(s) matched; \(summary.changed) local QSO row(s) updated; \(importedConfirmedRecords) confirmed cloud QSO(s) added; \(summary.unmatched) unmatched.")
            self.playActivitySound(lotwFailed || qrzFailed ? .failure : .success)
            completion?(summary)
        }
    }

    private static func lotwFallbackCursor(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Preserves a valid remote confirmation when the corresponding local QSO is absent.
    /// Only call/date records are imported; incomplete responses remain visible as unmatched.
    private func importRemoteConfirmationRecords(
        lotw: [[String: String]],
        qrz: [[String: String]]
    ) -> Int {
        var added = 0
        var knownIdentities = Set(qsoRecords.map(remoteConfirmationIdentity))

        for (source, records) in [(SyncSource.lotw, lotw), (.qrz, qrz)] {
            for record in records {
                var fields = stationTaggedFields(record)
                let call = fields["CALL"]?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
                let date = (fields["QSO_DATE"] ?? "").filter(\.isNumber)
                guard !call.isEmpty, date.count == 8 else { continue }

                fields["QSL_RCVD"] = "Y"
                fields["APP_YAAM_REMOTE_CONFIRMATION_IMPORTED"] = source.rawValue.uppercased()
                switch source {
                case .lotw:
                    fields["LOTW_QSL_RCVD"] = "Y"
                case .qrz:
                    fields["QRZLOG_QSL_RCVD"] = "Y"
                    fields["APP_QRZLOG_STATUS"] = "C"
                default:
                    break
                }

                let identity = remoteConfirmationIdentity(fields)
                guard !knownIdentities.contains(identity) else { continue }
                let model = QSORecordModel(index: qsoRecords.count + 1, fields: fields)
                qsoRecords.append(model)
                knownIdentities.insert(identity)
                added += 1
            }
        }

        if added > 0 {
            for header in ["LOTW_QSL_RCVD", "QRZLOG_QSL_RCVD", "QSL_RCVD", "APP_YAAM_REMOTE_CONFIRMATION_IMPORTED"] where !tableHeaders.contains(header) {
                tableHeaders.append(header)
            }
            rememberConfirmedRecords(Array(qsoRecords.suffix(added)))
        }
        return added
    }

    private func remoteConfirmationIdentity(_ record: QSORecordModel) -> String {
        remoteConfirmationIdentity(record.fields)
    }

    private func remoteConfirmationIdentity(_ fields: [String: String]) -> String {
        let call = fields["CALL"]?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let date = (fields["QSO_DATE"] ?? "").filter(\.isNumber)
        let time = (fields["TIME_ON"] ?? fields["TIME_OFF"] ?? "").filter(\.isNumber)
        let band = (fields["BAND"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let mode = (fields["MODE"] ?? fields["SUBMODE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return "\(call)|\(date)|\(time)|\(band)|\(mode)"
    }
}
