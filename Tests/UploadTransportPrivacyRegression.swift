// Recording URLProtocol and fake TQSL process. No real provider, keychain, database, audio or radio is used.
// Run via Tests/run-upload-privacy-regressions.sh.
import Foundation

nonisolated struct QSORecordModel {
    var fields: [String: String] = [:]
    var isConfirmed = false
    subscript(key: String) -> String { fields[key] ?? "" }
}
nonisolated enum CredentialVault {
    enum Key { case lotwCertificatePassword }
    static func value(for key: Key) -> String { "" }
}
nonisolated struct FakeStation {
    let id = UUID()
    let lotwStationLocation = ""
}
nonisolated struct LogbookDatabase {
    init() throws {}
    func loadStationProfiles() throws -> [FakeStation] { [] }
}
nonisolated enum TQSLService {
    static var folder = URL(fileURLWithPath: "/nonexistent-yaam-test")
    static var exitCode = 0
    static func realTQSLDirectory() -> String { folder.path }
    static func containerTQSLDirectory() -> String { folder.path }
    static func synchronizeTQSLStorage() {}
    static func tqslProcessEnvironment() -> [String: String] {
        ["PATH": "/usr/bin:/bin", "YAAM_TEST_EXIT": String(exitCode), "YAAM_TEST_CAPTURE": folder.appendingPathComponent("captured.adi").path]
    }
}

final class UploadRecordingProtocol: URLProtocol, @unchecked Sendable {
    static var requests: [URLRequest] = []
    static var responder: (URLRequest) throws -> (Int, Data) = { _ in fatalError("Unexpected request") }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            Self.requests.append(request)
            let (code, body) = try Self.responder(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main
@MainActor
struct UploadTransportPrivacyRegression {
    nonisolated static func json(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }
    nonisolated static func rawBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(contentsOf: buffer.prefix(n))
        }
        return data
    }
    nonisolated static func payload(_ request: URLRequest) -> [String: Any] {
        (try! JSONSerialization.jsonObject(with: rawBody(request))) as! [String: Any]
    }
    static func main() async throws {
        let off = UploadFieldOptions(shareNameAndQTH: false, shareContactDetails: false)
        let full = UploadFieldOptions(shareNameAndQTH: true, shareContactDetails: true, shareFreeText: true)
        let record = ["CALL": "EA3XYZ", "QSO_DATE": "20261017", "TIME_ON": "120000", "BAND": "20m", "MODE": "CW", "STATION_CALLSIGN": "K0ABC",
                      "EMAIL": "private@example.invalid", "MY_STREET": "private street", "NAME_INTL": "private", "APP_FOREIGN": "private", "UNKNOWN": "private",
                      "QSL_VIA": "private postal route", "COMMENT": "[RANK=1] free text", "QSLMSG": "private words",
                      "GRIDSQUARE": "JN11AB12", "MY_GRIDSQUARE": "FN31AB12", "VUCC_GRIDS": "JN11AB12,JN12CD34"]
        for destination in QSLUploadDestination.allCases {
            let fields = QSLUploadStatus.uploadFields(record, for: destination, options: off)
            precondition(!fields.values.contains { $0.contains("private") || $0.contains("free text") })
            precondition(fields["MY_GRIDSQUARE"] == "FN31AB")
            if destination != .lotw {
                precondition(fields["GRIDSQUARE"] == "JN11AB" && fields["VUCC_GRIDS"] == "JN11AB,JN12CD")
                let shared = QSLUploadStatus.uploadFields(record, for: destination, options: full)
                precondition(shared["COMMENT"] == "free text" && shared["QSL_VIA"] != nil)
                precondition(shared["GRIDSQUARE"] == "JN11AB12")
                precondition(shared["APP_FOREIGN"] == nil && shared["NAME_INTL"] == nil && shared["UNKNOWN"] == nil)
            }
        }
        precondition(QSLUploadStatus.uploadFields(["CALL": "K0ABC", "call": "EV1L"], for: .qrz, options: full).isEmpty)
        let all = [(id: UUID(), fields: record), (id: UUID(), fields: ["STATION_CALLSIGN": "K0ABC/P"]), (id: UUID(), fields: [:])]
        precondition(QSLSyncAll.recordsToSync(all: all, selectedIDs: nil, stationCallsign: " k0abc ").count == 2)
        precondition(QSLSyncAll.recordsToSync(all: all, selectedIDs: [all[1].id], stationCallsign: "K0ABC").isEmpty)
        precondition(!UploadStationPolicy.matches(record, stationCallsign: ""))
        precondition(!UploadStationPolicy.matches(["STATION_CALLSIGN": "K0ABC", "station_callsign": "EV1L"], stationCallsign: "K0ABC"))
        precondition(UploadStationPolicy.matches(["OPERATOR": "OTHER"], stationCallsign: "K0ABC"))
        let original = record
        _ = QSLUploadStatus.uploadFields(record, for: .qrz, options: off)
        precondition(original == record, "Upload filtering must not change the local record")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UploadRecordingProtocol.self]
        let client = WavelogClient(session: URLSession(configuration: config))
        let base = "https://log.example.invalid/subdirectory"
        let key = "INVENTED-KEY"
        UploadRecordingProtocol.responder = { request in
            let body=payload(request)
            precondition(request.httpMethod=="POST" && request.url!.path=="/subdirectory/api/radio")
            precondition(body["power"]==nil && body["frequency"] as? Int==14_074_000)
            return (200,json(["status":"success"]))
        }
        let unknownPower=try await client.broadcastRadio(baseURL:base,apiKey:key,radioName:"Fixture",frequencyHz:14_074_000,mode:"USB")
        precondition(unknownPower)
        UploadRecordingProtocol.responder = { request in
            precondition(payload(request)["power"] as? Int==12)
            return (200,json(["status":"success"]))
        }
        let knownPower=try await client.broadcastRadio(baseURL:base,apiKey:key,radioName:"Fixture",frequencyHz:14_074_000,mode:"USB",powerWatts:12)
        precondition(knownPower)
        UploadRecordingProtocol.responder = { _ in (200,json(["status":"failed","reason":"fixture rejection"])) }
        do {
            _=try await client.broadcastRadio(baseURL:base,apiKey:key,radioName:"Fixture",frequencyHz:14_074_000,mode:"USB")
            preconditionFailure("A failed HTTP 200 radio update must not count as successful")
        } catch WavelogError.serverRejected { }
        UploadRecordingProtocol.responder = { request in
            precondition(request.httpMethod == "GET" && request.url!.path == "/subdirectory/api/check_auth/" + key)
            precondition(request.httpBody == nil)
            return (200, json(["status": "valid", "rights": "r"]))
        }
        let rights = try await client.checkAuth(baseURL: base, apiKey: key)
        precondition(rights == .readOnly)
        UploadRecordingProtocol.responder = { request in
            precondition(request.httpMethod == "GET" && request.url!.path == "/subdirectory/api/station_info/" + key)
            return (200, Data("[{\"station_id\":2,\"station_callsign\":\"K0ABC\"}]".utf8))
        }
        let profiles = try await client.fetchStationProfiles(baseURL: base, apiKey: key)
        precondition(profiles.count == 1 && profiles[0].stationID == "2")
        UploadRecordingProtocol.requests = []
        UploadRecordingProtocol.responder = { request in
            if request.url!.path == "/subdirectory/api/qso" { return (404, Data()) }
            precondition(request.url!.path == "/subdirectory/index.php/api/qso")
            let body = payload(request)
            let adif = body["string"] as! String
            precondition(body["station_profile_id"] as? String == "2")
            precondition(!adif.contains("private") && !adif.contains("APP_") && !adif.contains("UNKNOWN"))
            return (201, json(["status": "created", "adif_count": 1, "adif_errors": 0]))
        }
        let batch = try await client.uploadBatchADIF(adifContent: generateADIF(originalContent: "", records: [record]), baseURL: base, apiKey: key, stationProfileID: "2")
        precondition(batch.success && UploadRecordingProtocol.requests.count == 2)
        UploadRecordingProtocol.responder = { _ in (200, json(["status": "failed", "reason": "private " + key])) }
        do {
            _ = try await client.uploadBatchADIF(adifContent: generateADIF(originalContent: "", records: [record]), baseURL: base, apiKey: key, stationProfileID: "2")
            preconditionFailure("A business failure with HTTP 200 must fail")
        } catch { precondition(!error.localizedDescription.contains(key) && !error.localizedDescription.contains("private")) }
        UploadRecordingProtocol.requests = []
        UploadRecordingProtocol.responder = { request in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: request.url!.absoluteString])
        }
        do { _ = try await client.checkAuth(baseURL: base, apiKey: key); preconditionFailure() }
        catch { precondition(!error.localizedDescription.contains(key) && UploadRecordingProtocol.requests.count == 1) }
        UploadRecordingProtocol.responder = { request in
            precondition(request.url!.path == "/subdirectory/api/get_contacts_adif")
            let body = payload(request)
            precondition(body["station_id"] as? String == "2" && body["station_profile_id"] == nil)
            let cursor = body["fetchfromid"] as! Int
            if cursor == 0 { return (200, json(["status": "successful", "exported_qsos": 1, "lastfetchedid": 10, "adif": "<CALL:6>EA3XYZ<EOR>"])) }
            if cursor == 10 { return (200, json(["status": "successful", "exported_qsos": 1, "lastfetchedid": 20, "adif": "<CALL:5>K0ABC<EOR>"])) }
            precondition(cursor == 20)
            return (200, json(["status": "successful", "exported_qsos": 0, "lastfetchedid": 20, "adif": NSNull()]))
        }
        let downloaded = try await client.exportADIF(baseURL: base, apiKey: key, stationProfileID: "2")
        precondition(parseADIF(content: downloaded).1.count == 2)
        UploadRecordingProtocol.responder = { _ in (200, json(["status": "successful", "exported_qsos": 1, "lastfetchedid": 0, "adif": "<CALL:5>K0ABC<EOR>"])) }
        do { _ = try await client.exportADIF(baseURL: base, apiKey: key, stationProfileID: "2"); preconditionFailure() } catch {}

        // Exercise the real QSL Hub request builders with prebuilt ADIF containing private data.
        let hub = QSLHubClient(session: URLSession(configuration: config))
        var credentials = QSLServiceCredentials()
        credentials.qrzAPIKey = "INVENTED-QRZ"
        credentials.eqslUsername = "LAB"
        credentials.eqslPassword = "INVENTED-PASSWORD"
        credentials.clubLogCallsign = "K0ABC"
        credentials.clubLogEmail = "lab@example.invalid"
        credentials.clubLogPassword = "INVENTED-PASSWORD"
        credentials.clubLogAPIKey = "INVENTED-CLUBLOG"
        UploadRecordingProtocol.responder = { request in
            let body = String(decoding: rawBody(request), as: UTF8.self)
            let decoded = body.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? body
            precondition(!decoded.contains("private") && !decoded.contains("UNKNOWN") && !decoded.contains("APP_FOREIGN"))
            precondition(decoded.contains("EA3XYZ"))
            return (200, Data((request.url!.host == "logbook.qrz.com" ? "RESULT=OK&LOGID=1" : "OK").utf8))
        }
        for provider in [QSLProvider.qrz, .eqsl, .clubLog] {
            let outcome = await hub.upload(provider: provider, adifRecords: [generateADIF(originalContent: "", records: [record])], credentials: credentials)
            precondition(outcome.accepted, outcome.message)
        }
        let job = QSLQueueJob(stationProfileID: UUID(), qsoID: UUID(), provider: .qrz, adif: "")
        var interrupted = QSLProviderPass(provider: .qrz, jobs: [job])
        precondition(interrupted.nextBatch()?.count == 1)
        interrupted.stopBeforeSending(reason: "the station changed")
        let deferred = interrupted.finish(now: Date())
        precondition(deferred.count == 1 && deferred[0].job.state == .retry && deferred[0].job.attempts == 0 && !deferred[0].markSent)
        precondition(interrupted.summary.notSent == 1 && interrupted.summary.sent == 0)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("yaam-upload-review-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        TQSLService.folder = folder
        let executable = folder.appendingPathComponent("fake-tqsl")
        let fakeTQSL = #"""
        #!/bin/sh
        for last; do :; done
        lock="${YAAM_TEST_CAPTURE}.lock"
        if ! /bin/mkdir "$lock"; then echo "overlapping TQSL processes"; exit 99; fi
        trap '/bin/rmdir "$lock"' EXIT
        trap 'exit 0' TERM
        echo run >> "${YAAM_TEST_CAPTURE}.runs"
        sleep 0.15
        /bin/cp "$last" "$YAAM_TEST_CAPTURE"
        echo "Final Status: fake TQSL result ($YAAM_TEST_EXIT)"
        exit "$YAAM_TEST_EXIT"
        """#
        try (fakeTQSL + "\n").write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let coordinator = TQSLCoordinator(cleanStaleFiles: false)
        let originalURL = folder.appendingPathComponent("original.adi")
        let originalADIF = generateADIF(originalContent: "", records: [record])
        try originalADIF.write(to: originalURL, atomically: true, encoding: .utf8)
        let companion = folder.appendingPathComponent("original.tq8")
        try Data("keep me".utf8).write(to: companion)
        for code in [0, 8, 9, 14] {
            TQSLService.exitCode = code
            let outcome = await coordinator.execute(adifFileURL: originalURL, stationLocation: "LAB", certificatePassword: "", customExecutablePath: executable.path, securityBookmark: Data())
            precondition(outcome.success == (code == 0), "Only TQSL zero confirms all QSOs")
            if code != 0 { precondition(outcome.message.contains("Final Status")) }
            let capture = try String(contentsOf: folder.appendingPathComponent("captured.adi"), encoding: .utf8)
            precondition(!capture.contains("private") && !capture.contains("COMMENT"))
            precondition(Set(parseADIF(content: capture).1[0].keys).isSubset(of: QSLUploadStatus.lotwFields))
        }
        TQSLService.exitCode = 0
        // The fake fails with 99 if two child processes overlap. An actor alone is not enough at await points.
        let first = Task { await coordinator.execute(adifContent: originalADIF, stationLocation: "LAB", customExecutablePath: executable.path, securityBookmark: Data()) }
        let second = Task { await coordinator.execute(adifContent: originalADIF, stationLocation: "LAB", customExecutablePath: executable.path, securityBookmark: Data()) }
        let firstResult = await first.value
        let secondResult = await second.value
        precondition(firstResult.success && secondResult.success)
        let cancelled = Task { await coordinator.execute(adifContent: originalADIF, stationLocation: "LAB", customExecutablePath: executable.path, securityBookmark: Data()) }
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        precondition(!cancelledResult.success && cancelledResult.message.contains("cancelled before signing"))
        let timeoutResult = await coordinator.execute(adifContent: originalADIF, stationLocation: "LAB", customExecutablePath: executable.path, securityBookmark: Data(), timeoutSeconds: 0.03)
        precondition(!timeoutResult.success && timeoutResult.message.contains("timed out"), "Even a zero exit after the watchdog fires must not succeed: \(timeoutResult)")
        let latin1 = folder.appendingPathComponent("legacy.adi")
        var legacyBytes = Data("<CALL:5>K0ABC<COMMENT:4>caf".utf8)
        legacyBytes.append(0xE9)
        legacyBytes.append(Data("<EOR>".utf8))
        try legacyBytes.write(to: latin1)
        let latinResult = await coordinator.execute(adifFileURL: latin1, stationLocation: "LAB", customExecutablePath: executable.path, securityBookmark: Data())
        precondition(latinResult.success)
        let cleanupRoot = folder.appendingPathComponent("cleanup")
        try FileManager.default.createDirectory(at: cleanupRoot, withIntermediateDirectories: false)
        let old = cleanupRoot.appendingPathComponent("yaam-lotw-" + UUID().uuidString)
        let recent = cleanupRoot.appendingPathComponent("yaam-lotw-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: recent, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-90_000)], ofItemAtPath: old.path)
        let userFile = cleanupRoot.appendingPathComponent("yaam_lotw_my-original.adi")
        try Data("keep".utf8).write(to: userFile)
        TQSLCoordinator.cleanStaleTemporaryFiles(in: cleanupRoot)
        precondition(!FileManager.default.fileExists(atPath: old.path))
        precondition(FileManager.default.fileExists(atPath: recent.path) && FileManager.default.fileExists(atPath: userFile.path))
        let preservedADIF = try String(contentsOf: originalURL, encoding: .utf8)
        let preservedCompanion = try Data(contentsOf: companion)
        precondition(preservedADIF == originalADIF && preservedCompanion == Data("keep me".utf8))
        print("UploadTransportPrivacyRegression passed: seven field policies, station identity, Wavelog routes/rights/pagination/errors, real TQSL process exits and file preservation")
    }
}
