//
//  QSLHub.swift
//  YAAM
//

import Foundation

nonisolated enum QSLProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case lotw
    case qrz
    case eqsl
    case clubLog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lotw: return "LoTW"
        case .qrz: return "QRZ Logbook"
        case .eqsl: return "eQSL"
        case .clubLog: return "Club Log"
        }
    }

    var icon: String {
        switch self {
        case .lotw: return "checkmark.seal"
        case .qrz: return "globe.americas"
        case .eqsl: return "envelope.badge"
        case .clubLog: return "person.3"
        }
    }

    var sentField: String {
        switch self {
        case .lotw: return "LOTW_QSL_SENT"
        case .qrz: return "QRZCOM_QSO_UPLOAD_STATUS"
        case .eqsl: return "EQSL_QSL_SENT"
        case .clubLog: return "APP_YAAM_CLUBLOG_SENT"
        }
    }
}

nonisolated enum QSLQueueState: String, CaseIterable, Codable, Sendable {
    case queued
    case uploading
    case retry
    case succeeded
    case failed
    case blocked

    var isPending: Bool { self == .queued || self == .retry || self == .uploading }
}

nonisolated struct QSLQueueJob: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var stationProfileID: UUID
    var qsoID: UUID
    var provider: QSLProvider
    var adif: String
    var state: QSLQueueState
    var attempts: Int
    var nextAttemptAt: Date?
    var message: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        stationProfileID: UUID,
        qsoID: UUID,
        provider: QSLProvider,
        adif: String,
        state: QSLQueueState = .queued,
        attempts: Int = 0,
        nextAttemptAt: Date? = nil,
        message: String = "Waiting",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.stationProfileID = stationProfileID
        self.qsoID = qsoID
        self.provider = provider
        self.adif = adif
        self.state = state
        self.attempts = attempts
        self.nextAttemptAt = nextAttemptAt
        self.message = message
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct QSLServiceCredentials: Sendable {
    var qrzAPIKey = ""
    var lotwCallsign = ""
    var lotwPassword = ""
    var lotwStationLocation = ""
    var tqslExecutablePath = ""
    var tqslBookmarkData: Data?
    var eqslUsername = ""
    var eqslPassword = ""
    var eqslQTHNickname = ""
    var clubLogEmail = ""
    var clubLogPassword = ""
    var clubLogAPIKey = ""
    var clubLogCallsign = ""
}

nonisolated struct QSLUploadResult: Sendable {
    var provider: QSLProvider
    var accepted: Bool
    var authenticationFailure: Bool
    var message: String
}

nonisolated enum QSLHubError: LocalizedError, Sendable {
    case missingCredential(String)
    case invalidResponse(String)
    case serviceRejected(String, authenticationFailure: Bool)
    case tqslUnavailable
    case tqslFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCredential(let value): return "Missing \(value)."
        case .invalidResponse(let value): return value
        case .serviceRejected(let value, _): return value
        case .tqslUnavailable: return "TrustedQSL was not found. Install TQSL or choose its executable in QSL Hub settings."
        case .tqslFailed(let value): return value
        }
    }

    var authenticationFailure: Bool {
        if case .serviceRejected(_, let authenticationFailure) = self { return authenticationFailure }
        return false
    }
}

actor QSLHubClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 120
        configuration.httpAdditionalHeaders = ["User-Agent": "YAAM-QSL-Hub"]
        session = URLSession(configuration: configuration)
    }

    func upload(provider: QSLProvider, adifRecords: [String], credentials: QSLServiceCredentials) async -> QSLUploadResult {
        do {
            switch provider {
            case .qrz:
                try await uploadQRZ(adifRecords, apiKey: credentials.qrzAPIKey)
            case .eqsl:
                try await uploadEQSL(adifRecords, credentials: credentials)
            case .clubLog:
                try await uploadClubLog(adifRecords, credentials: credentials)
            case .lotw:
                try uploadLoTW(adifRecords, credentials: credentials)
            }
            return QSLUploadResult(provider: provider, accepted: true, authenticationFailure: false, message: "Accepted by \(provider.title)")
        } catch let error as QSLHubError {
            return QSLUploadResult(
                provider: provider,
                accepted: false,
                authenticationFailure: error.authenticationFailure,
                message: error.localizedDescription
            )
        } catch {
            return QSLUploadResult(provider: provider, accepted: false, authenticationFailure: false, message: error.localizedDescription)
        }
    }

    func downloadEQSLConfirmations(credentials: QSLServiceCredentials, since: Date?) async throws -> [[String: String]] {
        guard !credentials.eqslUsername.isEmpty else { throw QSLHubError.missingCredential("eQSL username") }
        guard !credentials.eqslPassword.isEmpty else { throw QSLHubError.missingCredential("eQSL password") }
        guard var components = URLComponents(string: "https://www.eqsl.cc/qslcard/DownloadInBox.cfm") else {
            throw QSLHubError.invalidResponse("Invalid eQSL Inbox endpoint.")
        }
        var items = [
            URLQueryItem(name: "UserName", value: credentials.eqslUsername),
            URLQueryItem(name: "Password", value: credentials.eqslPassword)
        ]
        if !credentials.eqslQTHNickname.isEmpty {
            items.append(URLQueryItem(name: "QTHNickname", value: credentials.eqslQTHNickname))
        }
        if let since {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd"
            items.append(URLQueryItem(name: "RcvdSince", value: formatter.string(from: since)))
        }
        components.queryItems = items
        guard let url = components.url else { throw QSLHubError.invalidResponse("Unable to create the eQSL Inbox request.") }
        let (data, response) = try await session.data(from: url)
        let text = Self.responseText(data)
        try Self.requireHTTP(response, body: text)
        if Self.looksLikeAuthenticationFailure(text) {
            throw QSLHubError.serviceRejected("eQSL rejected the username or password.", authenticationFailure: true)
        }
        let parsed = parseADIF(content: text).records
        return parsed.map { record in
            var confirmed = record
            confirmed["EQSL_QSL_RCVD"] = "Y"
            return confirmed
        }
    }

    func downloadClubLogLoTWState(credentials: QSLServiceCredentials, earliestQSODate: String?) async throws -> [[String: String]] {
        guard !credentials.clubLogEmail.isEmpty else { throw QSLHubError.missingCredential("Club Log email") }
        guard !credentials.clubLogPassword.isEmpty else { throw QSLHubError.missingCredential("Club Log application password") }
        guard !credentials.clubLogCallsign.isEmpty else { throw QSLHubError.missingCredential("Club Log callsign") }
        guard !credentials.clubLogAPIKey.isEmpty else { throw QSLHubError.missingCredential("Club Log API key") }
        guard var components = URLComponents(string: "https://clublog.org/getlotwstate.php") else {
            throw QSLHubError.invalidResponse("Invalid Club Log LoTW-state endpoint.")
        }
        var items = [
            URLQueryItem(name: "api", value: credentials.clubLogAPIKey),
            URLQueryItem(name: "email", value: credentials.clubLogEmail),
            URLQueryItem(name: "password", value: credentials.clubLogPassword),
            URLQueryItem(name: "callsign", value: credentials.clubLogCallsign)
        ]
        let date = (earliestQSODate ?? "").filter(\.isNumber)
        if date.count >= 8 {
            items += [
                URLQueryItem(name: "startyear", value: String(date.prefix(4))),
                URLQueryItem(name: "startmonth", value: String(date.dropFirst(4).prefix(2))),
                URLQueryItem(name: "startday", value: String(date.dropFirst(6).prefix(2)))
            ]
        }
        components.queryItems = items
        guard let url = components.url else {
            throw QSLHubError.invalidResponse("Unable to create the Club Log LoTW-state request.")
        }

        let (data, response) = try await session.data(from: url)
        let text = Self.responseText(data)
        try Self.requireHTTP(response, body: text)
        if Self.looksLikeAuthenticationFailure(text) {
            throw QSLHubError.serviceRejected("Club Log rejected the credentials. Use an application password.", authenticationFailure: true)
        }
        return try Self.parseClubLogLoTWState(data)
    }

    nonisolated static func parseClubLogLoTWState(_ data: Data) throws -> [[String: String]] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw QSLHubError.invalidResponse("Club Log returned unreadable LoTW-state data.")
        }

        return payload.dropFirst().compactMap { element in
            guard let row = element as? [Any], row.count >= 5,
                  let callsign = row[0] as? String,
                  let timestamp = row[1] as? String,
                  let band = row[2] as? String,
                  let mode = row[3] as? String,
                  let rawState = row[4] as? String else { return nil }

            let dateAndTime = timestamp.split(separator: " ", maxSplits: 1).map(String.init)
            guard let rawDate = dateAndTime.first else { return nil }
            let qsoDate = rawDate.filter(\.isNumber)
            guard qsoDate.count == 8 else { return nil }
            let rawTime = dateAndTime.count > 1 ? dateAndTime[1].filter(\.isNumber) : ""
            let timeOn = String((rawTime + "000000").prefix(6))
            let state = rawState.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard ["S", "C", "G"].contains(state) else { return nil }

            var fields = [
                "CALL": callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                "QSO_DATE": qsoDate,
                "TIME_ON": timeOn,
                "BAND": normalizeClubLogBand(band),
                "MODE": mode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                "LOTW_QSL_SENT": "Y",
                "APP_YAAM_CLUBLOG_LOTW_STATE": state
            ]
            if state == "C" || state == "G" {
                fields["LOTW_QSL_RCVD"] = state == "G" ? "V" : "Y"
                fields["QSL_RCVD"] = "Y"
            }
            return fields
        }
    }

    private func uploadQRZ(_ records: [String], apiKey: String) async throws {
        guard !apiKey.isEmpty else { throw QSLHubError.missingCredential("QRZ Logbook API key") }
        guard let url = URL(string: "https://logbook.qrz.com/api") else {
            throw QSLHubError.invalidResponse("Invalid QRZ Logbook API endpoint.")
        }

        // QRZ's INSERT action accepts one ADIF record per request.
        for adif in records {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formBody([
                URLQueryItem(name: "KEY", value: apiKey),
                URLQueryItem(name: "ACTION", value: "INSERT"),
                URLQueryItem(name: "ADIF", value: adif)
            ])
            let (data, response) = try await session.data(for: request)
            let text = Self.responseText(data)
            try Self.requireHTTP(response, body: text)
            let upper = text.uppercased()
            guard upper.contains("RESULT=OK") else {
                let auth = upper.contains("INVALID") || upper.contains("KEY") || upper.contains("AUTH")
                throw QSLHubError.serviceRejected("QRZ rejected the upload: \(Self.concise(text))", authenticationFailure: auth)
            }
        }
    }

    private func uploadEQSL(_ records: [String], credentials: QSLServiceCredentials) async throws {
        guard !credentials.eqslUsername.isEmpty else { throw QSLHubError.missingCredential("eQSL username") }
        guard !credentials.eqslPassword.isEmpty else { throw QSLHubError.missingCredential("eQSL password") }
        guard let url = URL(string: "https://www.eqsl.cc/qslcard/ImportADIF.cfm") else {
            throw QSLHubError.invalidResponse("Invalid eQSL upload endpoint.")
        }
        let adif = "Generated by YAAM\r\n<ADIF_VER:5>3.1.6<PROGRAMID:4>YAAM<EOH>\r\n" + records.joined(separator: "\r\n")
        var items = [
            URLQueryItem(name: "EQSL_USER", value: credentials.eqslUsername),
            URLQueryItem(name: "EQSL_PSWD", value: credentials.eqslPassword),
            URLQueryItem(name: "ADIFData", value: adif)
        ]
        if !credentials.eqslQTHNickname.isEmpty {
            items.append(URLQueryItem(name: "APP_EQSL_QTH_NICKNAME", value: credentials.eqslQTHNickname))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(items)
        let (data, response) = try await session.data(for: request)
        let text = Self.responseText(data)
        try Self.requireHTTP(response, body: text)
        if Self.looksLikeAuthenticationFailure(text) {
            throw QSLHubError.serviceRejected("eQSL rejected the username or password.", authenticationFailure: true)
        }
        let upper = text.uppercased()
        if upper.contains("ERROR") || upper.contains("FAILED") || upper.contains("REJECTED") {
            throw QSLHubError.serviceRejected("eQSL rejected the upload: \(Self.concise(text))", authenticationFailure: false)
        }
    }

    private func uploadClubLog(_ records: [String], credentials: QSLServiceCredentials) async throws {
        guard !credentials.clubLogEmail.isEmpty else { throw QSLHubError.missingCredential("Club Log email") }
        guard !credentials.clubLogPassword.isEmpty else { throw QSLHubError.missingCredential("Club Log application password") }
        guard !credentials.clubLogCallsign.isEmpty else { throw QSLHubError.missingCredential("Club Log callsign") }
        guard !credentials.clubLogAPIKey.isEmpty else { throw QSLHubError.missingCredential("Club Log API key") }
        guard let url = URL(string: "https://clublog.org/putlogs.php") else {
            throw QSLHubError.invalidResponse("Invalid Club Log upload endpoint.")
        }

        let boundary = "YAAM-\(UUID().uuidString)"
        let adif = "Generated by YAAM\r\n<ADIF_VER:5>3.1.6<PROGRAMID:4>YAAM<EOH>\r\n" + records.joined(separator: "\r\n")
        let fields = [
            "email": credentials.clubLogEmail,
            "password": credentials.clubLogPassword,
            "callsign": credentials.clubLogCallsign,
            "clear": "0",
            "api": credentials.clubLogAPIKey
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipart(fields: fields, fileName: "yaam-upload.adi", fileData: Data(adif.utf8), boundary: boundary)
        let (data, response) = try await session.data(for: request)
        let text = Self.responseText(data)
        guard let http = response as? HTTPURLResponse else {
            throw QSLHubError.invalidResponse("Club Log returned no HTTP response.")
        }
        if http.statusCode == 403 {
            throw QSLHubError.serviceRejected("Club Log rejected the credentials. Create and use an application password.", authenticationFailure: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw QSLHubError.serviceRejected("Club Log returned HTTP \(http.statusCode): \(Self.concise(text))", authenticationFailure: false)
        }
    }

    private func uploadLoTW(_ records: [String], credentials: QSLServiceCredentials) throws {
        guard !credentials.lotwCallsign.isEmpty else { throw QSLHubError.missingCredential("LoTW callsign") }
        var scopedURL: URL?
        var didAccessScopedURL = false
        if let bookmark = credentials.tqslBookmarkData {
            var stale = false
            scopedURL = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if let scopedURL { didAccessScopedURL = scopedURL.startAccessingSecurityScopedResource() }
        }
        defer { if didAccessScopedURL { scopedURL?.stopAccessingSecurityScopedResource() } }
        let candidates = [
            scopedURL?.path ?? "",
            credentials.tqslExecutablePath,
            "/Applications/TrustedQSL/tqsl.app/Contents/MacOS/tqsl",
            "/Applications/tqsl.app/Contents/MacOS/tqsl",
            "/opt/homebrew/bin/tqsl",
            "/usr/local/bin/tqsl"
        ].filter { !$0.isEmpty }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw QSLHubError.tqslUnavailable
        }

        let adif = "Generated by YAAM\r\n<ADIF_VER:5>3.1.6<PROGRAMID:4>YAAM<EOH>\r\n" + records.joined(separator: "\r\n")
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("YAAM-LoTW-\(UUID().uuidString).adi")
        try Data(adif.utf8).write(to: inputURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        var arguments = ["-u", "-q"]
        if !credentials.lotwStationLocation.isEmpty {
            arguments += ["-l", credentials.lotwStationLocation]
        }
        arguments.append(inputURL.path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw QSLHubError.tqslFailed("TQSL stopped with code \(process.terminationStatus): \(Self.concise(output))")
        }
    }

    private static func formBody(_ items: [URLQueryItem]) -> Data? {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private static func multipart(fields: [String: String], fileName: String, fileData: Data, boundary: String) -> Data {
        var data = Data()
        for key in fields.keys.sorted() {
            data.append(Data("--\(boundary)\r\n".utf8))
            data.append(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
            data.append(Data((fields[key] ?? "").utf8))
            data.append(Data("\r\n".utf8))
        }
        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".utf8))
        data.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        data.append(fileData)
        data.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return data
    }

    private static func requireHTTP(_ response: URLResponse, body: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw QSLHubError.invalidResponse("The service returned no HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let auth = http.statusCode == 401 || http.statusCode == 403
            throw QSLHubError.serviceRejected("HTTP \(http.statusCode): \(concise(body))", authenticationFailure: auth)
        }
    }

    private static func responseText(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private static func looksLikeAuthenticationFailure(_ text: String) -> Bool {
        let upper = text.uppercased()
        return upper.contains("INVALID PASSWORD") || upper.contains("LOGIN FAILED") || upper.contains("AUTHENTICATION FAILED") || upper.contains("ACCESS DENIED")
    }

    private nonisolated static func normalizeClubLogBand(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasSuffix("M") || value.hasSuffix("CM") || value.isEmpty { return value }
        let centimetreBands = [
            "0.7": "70CM", "0.33": "33CM", "0.23": "23CM", "0.13": "13CM",
            "0.09": "9CM", "0.06": "6CM", "0.03": "3CM", "0.0125": "1.25CM"
        ]
        return centimetreBands[value] ?? "\(value)M"
    }

    private static func concise(_ text: String) -> String {
        let clean = text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(clean.prefix(240))
    }
}
