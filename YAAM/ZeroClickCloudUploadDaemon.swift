//
//  ZeroClickCloudUploadDaemon.swift
//  YAAM
//
//  Zero-Click Background Cloud Log Synchronization Daemon
//  Instantly uploads newly logged QSOs (manual, Quick Log, or WSJT-X / JTDX)
//  in milliseconds to QRZ Logbook (ACTION=INSERT), Club Log (realtime.php),
//  eQSL.cc, and Wavelog/Cloudlog without user intervention.
//

import AppKit
import Combine
import Foundation
import Network
import SwiftUI

// MARK: - Upload Log Item

public struct CloudUploadLogItem: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let callsign: String
    public let band: String
    public let mode: String
    public let services: [String]
    public let timestamp: Date
    public let latencyMs: Int
    public let success: Bool
    public let message: String
}

// MARK: - Persistent Outbox Item

public struct PendingCloudUploadItem: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var recordFields: [String: String]
    public let stationID: String?
    public let stationLocation: String?
    public var pendingServices: [String]
    public var attemptCount: Int
    public var lastAttemptDate: Date?
    public var lastErrorMessage: String?
    public let enqueuedAt: Date

    public init(
        id: UUID = UUID(),
        recordFields: [String: String],
        stationID: String? = nil,
        stationLocation: String? = nil,
        pendingServices: [String],
        attemptCount: Int = 0,
        lastAttemptDate: Date? = nil,
        lastErrorMessage: String? = nil,
        enqueuedAt: Date = Date()
    ) {
        self.id = id
        self.recordFields = recordFields
        self.stationID = stationID
        self.stationLocation = stationLocation
        self.pendingServices = pendingServices
        self.attemptCount = attemptCount
        self.lastAttemptDate = lastAttemptDate
        self.lastErrorMessage = lastErrorMessage
        self.enqueuedAt = enqueuedAt
    }

    public var callsign: String {
        recordFields["CALL"] ?? "UNKNOWN"
    }

    public var band: String {
        recordFields["BAND"] ?? ""
    }

    public var mode: String {
        recordFields["MODE"] ?? ""
    }
}

// MARK: - Zero-Click Cloud Upload Daemon

@MainActor
public final class ZeroClickCloudUploadDaemon: ObservableObject {
    public static let shared = ZeroClickCloudUploadDaemon()

    // Preferences & Toggles (Defaults to enabled for seamless experience)
    @AppStorage("zeroClickCloudUploadEnabled") public var isEnabled: Bool = true
    @AppStorage("zeroClickUploadQRZ") public var uploadToQRZ: Bool = true
    @AppStorage("zeroClickUploadClubLog") public var uploadToClubLog: Bool = true
    @AppStorage("zeroClickUploadEQSL") public var uploadToEQSL: Bool = true
    @AppStorage("zeroClickUploadWavelog") public var uploadToWavelog: Bool = true
    @AppStorage("zeroClickUploadLoTW") public var uploadToLoTW: Bool = true
    @AppStorage("lotwStationLocation") public var lotwStationLocation: String = ""
    @AppStorage("autoCommitWSJTX") public var autoCommitWSJTX: Bool = true

    // Real-Time Live Status
    @Published public var lastUploadStatus: String = ""
    @Published public var lastUploadLatencyMs: Int = 0
    @Published public var showToast: Bool = false
    @Published public var isUploading: Bool = false
    @Published public var isFlushingQueue: Bool = false
    @Published public var isNetworkConnected: Bool = true
    @Published public var pendingQueueCount: Int = 0
    @Published public var pendingQueue: [PendingCloudUploadItem] = []
    @Published public var recentUploadLogs: [CloudUploadLogItem] = []

    private var toastDismissTask: Task<Void, Never>?
    private var retryTimerTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "org.yaam.cloudUpload.networkMonitor", qos: .utility)

    private var queueFileURL: URL {
        let dir = LogbookDatabase.canonicalDataDirectory()
        return dir.appendingPathComponent("PendingCloudUploads.json")
    }

    private init() {
        loadPendingQueueFromDisk()
        startNetworkMonitoring()
        startPeriodicRetryTimer()
    }

    deinit {
        pathMonitor?.cancel()
        retryTimerTask?.cancel()
        toastDismissTask?.cancel()
    }

    // MARK: - Disk Persistence
    private func loadPendingQueueFromDisk() {
        let url = queueFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let items = try decoder.decode([PendingCloudUploadItem].self, from: data)
            self.pendingQueue = items
            self.pendingQueueCount = items.count
            // Older builds stored the QRZ API key in this file; rewrite it without the key.
            if data.range(of: Data("qrzKeyOverride".utf8)) != nil {
                savePendingQueueToDisk()
            }
        } catch {
            print("⚠️ [ZeroClickDaemon] Failed to load PendingCloudUploads: \(error.localizedDescription)")
        }
    }

    private func savePendingQueueToDisk() {
        self.pendingQueueCount = self.pendingQueue.count
        let url = queueFileURL
        let items = self.pendingQueue
        Task.detached(priority: .utility) {
            do {
                let dir = url.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: dir.path) {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(items)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                print("⚠️ [ZeroClickDaemon] Failed to save PendingCloudUploads: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Network Connectivity Monitoring
    private func startNetworkMonitoring() {
        let monitor = NWPathMonitor()
        self.pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let currentlyConnected = (path.status == .satisfied)
                let wasDisconnected = !self.isNetworkConnected
                self.isNetworkConnected = currentlyConnected

                if currentlyConnected && wasDisconnected {
                    // Reconnected to internet! Wait 2.5s for DNS/routes to settle, then flush outbox
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if !self.pendingQueue.isEmpty {
                        await self.flushPendingQueue(triggerReason: "Internet Reconnected")
                    }
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Periodic Retry Heartbeat
    private func startPeriodicRetryTimer() {
        retryTimerTask?.cancel()
        retryTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // Every 60 seconds
                guard let self = self else { return }
                if self.isNetworkConnected && !self.pendingQueue.isEmpty && !self.isFlushingQueue {
                    await self.flushPendingQueue(triggerReason: "Periodic Check")
                }
            }
        }
    }

    // MARK: - Active Services Helper
    /// True when `dispatch` will push Wavelog itself, so callers must not push it again.
    public var ownsWavelogPush: Bool { isEnabled && uploadToWavelog }

    public func enabledServices() -> [String] {
        var services: [String] = []
        if uploadToQRZ { services.append("QRZ") }
        if uploadToClubLog { services.append("Club Log") }
        if uploadToEQSL { services.append("eQSL") }
        if uploadToWavelog { services.append("Wavelog") }
        if uploadToLoTW { services.append("LoTW") }
        return services
    }

    // MARK: - Main Dispatch Entry Point
    func dispatch(
        record: QSORecordModel,
        stationID: String? = nil,
        stationLocation: String? = nil,
        qrzKeyOverride: String? = nil
    ) {
        guard isEnabled else { return }

        let call = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !call.isEmpty else { return }

        let activeServices = enabledServices()
        guard !activeServices.isEmpty else { return }

        // If offline right now, enqueue immediately without waiting for network timeouts
        if !isNetworkConnected {
            enqueue(
                record: record,
                stationID: stationID,
                stationLocation: stationLocation,
                targetServices: activeServices,
                errorReason: "Internet disconnected (Offline)"
            )
            return
        }

        Task { [weak self] in
            guard let self = self else { return }
            await self.executeUpload(
                record: record,
                stationID: stationID,
                stationLocation: stationLocation,
                qrzKeyOverride: qrzKeyOverride,
                targetServices: activeServices
            )
        }
    }

    // MARK: - Enqueue into Persistent Outbox
    private func enqueue(
        record: QSORecordModel,
        stationID: String?,
        stationLocation: String?,
        targetServices: [String],
        errorReason: String?
    ) {
        let call = record["CALL"].uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetServices.isEmpty else { return }

        if let existingIdx = pendingQueue.firstIndex(where: {
            let existingCall = ($0.recordFields["CALL"] ?? "").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let existingDate = $0.recordFields["QSO_DATE"] ?? ""
            let existingTime = $0.recordFields["TIME_ON"] ?? ""
            let newDate = record["QSO_DATE"]
            let newTime = record["TIME_ON"]
            return existingCall == call && existingDate == newDate && existingTime == newTime
        }) {
            var current = Set(pendingQueue[existingIdx].pendingServices)
            current.formUnion(targetServices)
            pendingQueue[existingIdx].pendingServices = Array(current)
            pendingQueue[existingIdx].lastErrorMessage = errorReason
            pendingQueue[existingIdx].lastAttemptDate = Date()
        } else {
            let newItem = PendingCloudUploadItem(
                recordFields: record.fields,
                stationID: stationID,
                stationLocation: stationLocation,
                pendingServices: targetServices,
                attemptCount: 0,
                lastAttemptDate: Date(),
                lastErrorMessage: errorReason,
                enqueuedAt: Date()
            )
            pendingQueue.append(newItem)
            if pendingQueue.count > 500 {
                pendingQueue.removeFirst(pendingQueue.count - 500)
            }
        }

        savePendingQueueToDisk()

        let serviceNames = targetServices.joined(separator: ", ")
        let statusText = "📦 Offline Outbox: \(call) queued for upload (\(serviceNames))"
        self.lastUploadStatus = statusText
        triggerToast()

        let logItem = CloudUploadLogItem(
            callsign: call,
            band: record["BAND"],
            mode: record["MODE"],
            services: [],
            timestamp: Date(),
            latencyMs: 0,
            success: false,
            message: "Queued in offline outbox (\(serviceNames)): \(errorReason ?? "Network offline")"
        )
        appendRecentLog(logItem)
    }

    // MARK: - Network Error Detection
    private func isNetworkFailure(_ message: String) -> Bool {
        if !isNetworkConnected { return true }
        let lower = message.lowercased()
        if lower.isEmpty { return false }
        return lower.contains("offline") ||
               lower.contains("internet connection") ||
               lower.contains("network") ||
               lower.contains("timed out") ||
               lower.contains("timeout") ||
               lower.contains("could not connect") ||
               lower.contains("cannot find host") ||
               lower.contains("hostname could not be found") ||
               lower.contains("connection lost") ||
               lower.contains("connection refused") ||
               lower.contains("network is down") ||
               lower.contains("no route to host") ||
               lower.contains("the request timed out") ||
               lower.contains("http error") ||
               lower.contains("connection reset") ||
               lower.contains("socket") ||
               lower.contains("communication error") ||
               lower.contains("unable to upload") ||
               lower.contains("upload failed")
    }

    // MARK: - Upload Worker
    private func executeUpload(
        record: QSORecordModel,
        stationID: String?,
        stationLocation: String?,
        qrzKeyOverride: String?,
        targetServices: [String]
    ) async {
        let startTime = Date()
        isUploading = true
        defer { isUploading = false }

        var successfulServices: [String] = []
        var networkFailedServices: [String] = []
        var configErrors: [String] = []

        // 1. QRZ Logbook (ACTION=INSERT)
        if targetServices.contains("QRZ") {
            let qrzOutcome = await uploadToQRZLogbook(record: record, stationID: stationID, keyOverride: qrzKeyOverride)
            if qrzOutcome.success {
                successfulServices.append("QRZ")
            } else if isNetworkFailure(qrzOutcome.message) {
                networkFailedServices.append("QRZ")
            } else if !qrzOutcome.message.isEmpty {
                configErrors.append("QRZ: \(qrzOutcome.message)")
            }
        }

        // 2. Club Log (realtime.php)
        if targetServices.contains("Club Log") {
            let clubLogOutcome = await uploadToClubLogRealTime(record: record)
            if clubLogOutcome.success {
                successfulServices.append("Club Log")
            } else if isNetworkFailure(clubLogOutcome.message) {
                networkFailedServices.append("Club Log")
            } else if !clubLogOutcome.message.isEmpty {
                configErrors.append("ClubLog: \(clubLogOutcome.message)")
            }
        }

        // 3. eQSL.cc
        if targetServices.contains("eQSL") {
            let eqslOutcome = await uploadToEQSLRealTime(record: record)
            if eqslOutcome.success {
                successfulServices.append("eQSL")
            } else if isNetworkFailure(eqslOutcome.message) {
                networkFailedServices.append("eQSL")
            }
        }

        // 4. Wavelog / Cloudlog
        if targetServices.contains("Wavelog") {
            let wavelogOutcome = await WavelogSyncEngine.shared.pushSingleQSO(record: record)
            switch wavelogOutcome {
            case .success, .duplicate:
                successfulServices.append("Wavelog")
            case .networkError:
                networkFailedServices.append("Wavelog")
            case .rejected(let reason):
                configErrors.append("Wavelog: \(reason)")
            case .notConfigured:
                break
            }
        }

        // 5. ARRL LoTW via TQSL CLI
        if targetServices.contains("LoTW") {
            let lotwOutcome = await uploadToLoTWViaTQSL(
                record: record,
                stationID: stationID,
                stationLocation: stationLocation
            )
            if lotwOutcome.success {
                successfulServices.append("LoTW")
            } else if isNetworkFailure(lotwOutcome.message) {
                networkFailedServices.append("LoTW")
            } else if !lotwOutcome.message.isEmpty && !lotwOutcome.message.contains("not found") {
                configErrors.append("LoTW: \(lotwOutcome.message)")
            }
        }

        let latency = Int(Date().timeIntervalSince(startTime) * 1000)
        self.lastUploadLatencyMs = latency

        let call = record["CALL"]
        let band = record["BAND"]
        let mode = record["MODE"]

        // If any service failed due to network / connectivity issues, buffer in offline outbox!
        if !networkFailedServices.isEmpty {
            enqueue(
                record: record,
                stationID: stationID,
                stationLocation: stationLocation,
                targetServices: networkFailedServices,
                errorReason: "Connection failed during upload"
            )
        }

        if !successfulServices.isEmpty {
            let serviceList = successfulServices.joined(separator: " & ")
            var statusText = "☁️ Instant Upload: \(call) (\(band)/\(mode)) → \(serviceList) [\(latency)ms]"
            if !networkFailedServices.isEmpty {
                statusText += " (Queued: \(networkFailedServices.joined(separator: ", ")))"
            }
            self.lastUploadStatus = statusText
            triggerToast()

            let logItem = CloudUploadLogItem(
                callsign: call,
                band: band,
                mode: mode,
                services: successfulServices,
                timestamp: Date(),
                latencyMs: latency,
                success: true,
                message: "Successfully synchronized"
            )
            appendRecentLog(logItem)
        } else if !configErrors.isEmpty && networkFailedServices.isEmpty {
            let logItem = CloudUploadLogItem(
                callsign: call,
                band: band,
                mode: mode,
                services: [],
                timestamp: Date(),
                latencyMs: latency,
                success: false,
                message: configErrors.joined(separator: "; ")
            )
            appendRecentLog(logItem)
        }
    }

    // MARK: - Queue Flush (Auto & Manual)
    public func flushNow() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.flushPendingQueue(triggerReason: "Manual Sync")
        }
    }

    public func flushPendingQueue(triggerReason: String = "") async {
        guard !isFlushingQueue else { return }
        guard !pendingQueue.isEmpty else { return }
        guard isNetworkConnected else { return }

        isFlushingQueue = true
        defer { isFlushingQueue = false }

        var fullyCompletedIndices: [Int] = []
        var totalUploadedServices = 0
        var encounteredNetworkFailure = false

        for index in pendingQueue.indices {
            if encounteredNetworkFailure { break }

            var item = pendingQueue[index]
            let record = QSORecordModel(fields: item.recordFields)
            var servicesToRemove: [String] = []

            for service in item.pendingServices {
                var success = false
                var networkFailure = false

                switch service {
                case "QRZ":
                    let outcome = await uploadToQRZLogbook(
                        record: record,
                        stationID: item.stationID
                    )
                    success = outcome.success
                    networkFailure = isNetworkFailure(outcome.message)
                case "Club Log":
                    let outcome = await uploadToClubLogRealTime(record: record)
                    success = outcome.success
                    networkFailure = isNetworkFailure(outcome.message)
                case "eQSL":
                    let outcome = await uploadToEQSLRealTime(record: record)
                    success = outcome.success
                    networkFailure = isNetworkFailure(outcome.message)
                case "Wavelog":
                    // Only transport trouble is retried; any other answer leaves the outbox as before
                    // (the reason is kept in WavelogSyncEngine.lastError).
                    let outcome = await WavelogSyncEngine.shared.pushSingleQSO(record: record)
                    if case .networkError = outcome { networkFailure = true } else { success = true }
                case "LoTW":
                    let outcome = await uploadToLoTWViaTQSL(
                        record: record,
                        stationID: item.stationID,
                        stationLocation: item.stationLocation
                    )
                    success = outcome.success
                    networkFailure = isNetworkFailure(outcome.message)
                default:
                    success = true
                }

                if success {
                    servicesToRemove.append(service)
                    totalUploadedServices += 1
                } else if networkFailure {
                    encounteredNetworkFailure = true
                    item.lastErrorMessage = "Network connection failed during sync"
                    break
                } else {
                    // Non-network failure (e.g. unconfigured credentials or permanent rejection).
                    // Drop service from pending item to prevent infinite retry loops.
                    servicesToRemove.append(service)
                    item.lastErrorMessage = "Service configuration error: \(service)"
                }
            }

            item.pendingServices.removeAll { servicesToRemove.contains($0) }
            item.attemptCount += 1
            item.lastAttemptDate = Date()
            pendingQueue[index] = item

            if item.pendingServices.isEmpty || item.attemptCount >= 15 {
                fullyCompletedIndices.append(index)
            }
        }

        // Remove fully completed items in reverse order
        for idx in fullyCompletedIndices.sorted(by: >) {
            if idx < pendingQueue.count {
                let completed = pendingQueue.remove(at: idx)
                let logItem = CloudUploadLogItem(
                    callsign: completed.callsign,
                    band: completed.band,
                    mode: completed.mode,
                    services: ["Outbox Sync"],
                    timestamp: Date(),
                    latencyMs: 0,
                    success: true,
                    message: "Completed outbox sync"
                )
                appendRecentLog(logItem)
            }
        }

        savePendingQueueToDisk()

        if totalUploadedServices > 0 {
            let reasonStr = triggerReason.isEmpty ? "" : " (\(triggerReason))"
            let statusText = "☁️ Outbox Synced: \(fullyCompletedIndices.count) QSO(s) uploaded successfully\(reasonStr)"
            self.lastUploadStatus = statusText
            triggerToast()
        }
    }

    private func triggerToast() {
        showToast = true
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard let self = self else { return }
            self.showToast = false
        }
    }

    private func appendRecentLog(_ item: CloudUploadLogItem) {
        recentUploadLogs.insert(item, at: 0)
        if recentUploadLogs.count > 40 {
            recentUploadLogs.removeLast()
        }
    }

    // MARK: - 1. QRZ Logbook Real-Time Insert
    private func uploadToQRZLogbook(record: QSORecordModel, stationID: String?, keyOverride: String? = nil) async -> (success: Bool, message: String) {
        // Live uploads pass the active key; queued retries resolve it from the vault (never stored in the outbox)
        var apiKey = (keyOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKey.isEmpty {
            apiKey = CredentialVault.qrzLogbookKey(stationID: stationID)
        }
        guard !apiKey.isEmpty else {
            return (false, "No QRZ API Key configured")
        }

        let adif = buildSingleQSOADIF(record)
        guard let endpoint = URL(string: "https://logbook.qrz.com/api") else {
            return (false, "Invalid endpoint")
        }

        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("YAAM-macOS/ZeroClickCloudUpload", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let postString = "KEY=\(urlEncode(apiKey))&ACTION=INSERT&ADIF=\(urlEncode(adif))"
        request.httpBody = postString.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return (false, "HTTP error")
            }
            let responseText = String(data: data, encoding: .utf8) ?? ""
            if responseText.contains("RESULT=OK") {
                return (true, "OK")
            } else if responseText.contains("DUPLICATE") {
                return (true, "Already in log")
            } else {
                let reason = extractQRZReason(from: responseText)
                return (false, reason)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - 2. Club Log Real-Time Upload
    private func uploadToClubLogRealTime(record: QSORecordModel) async -> (success: Bool, message: String) {
        let email = UserDefaults.standard.string(forKey: "clubLogEmail") ?? ""
        let call = UserDefaults.standard.string(forKey: "clubLogCallsign") ?? ""
        let password = CredentialVault.value(for: .clubLogPassword)
        let apiKey = CredentialVault.value(for: .clubLogAPIKey)

        guard !email.isEmpty, !call.isEmpty, !password.isEmpty, !apiKey.isEmpty else {
            return (false, "Club Log credentials not configured")
        }

        guard let endpoint = URL(string: "https://clublog.org/realtime.php") else {
            return (false, "Invalid endpoint")
        }

        let adif = buildSingleQSOADIF(record)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("YAAM-macOS/ZeroClickCloudUpload", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let postString = "email=\(urlEncode(email))&password=\(urlEncode(password))&callsign=\(urlEncode(call))&api=\(urlEncode(apiKey))&adif=\(urlEncode(adif))"
        request.httpBody = postString.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return (false, "HTTP error")
            }
            let resText = String(data: data, encoding: .utf8) ?? ""
            if resText.contains("OK") || resText.isEmpty {
                return (true, "OK")
            }
            return (false, resText.prefix(60).description)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - 3. eQSL.cc Real-Time Upload
    private func uploadToEQSLRealTime(record: QSORecordModel) async -> (success: Bool, message: String) {
        let username = UserDefaults.standard.string(forKey: "eqslUsername") ?? ""
        let password = CredentialVault.value(for: .eqslPassword)

        guard !username.isEmpty, !password.isEmpty else {
            return (false, "eQSL credentials not configured")
        }

        guard let endpoint = URL(string: "https://www.eqsl.cc/qslcard/ImportADIF.txt") else {
            return (false, "Invalid endpoint")
        }

        let adif = buildSingleQSOADIF(record)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("YAAM-macOS/ZeroClickCloudUpload", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let postString = "EQSL_USER=\(urlEncode(username))&EQSL_PSWD=\(urlEncode(password))&ADIFData=\(urlEncode(adif))"
        request.httpBody = postString.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return (false, "HTTP error")
            }
            let resText = String(data: data, encoding: .utf8) ?? ""
            if resText.localizedCaseInsensitiveContains("Success") || resText.localizedCaseInsensitiveContains("Result: 1") {
                return (true, "OK")
            }
            return (false, resText.prefix(50).description)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Single QSO ADIF Generator
    private func buildSingleQSOADIF(_ record: QSORecordModel) -> String {
        var out = "<ADIF_VER:5>3.1.4 <PROGRAMID:4>YAAM <EOH>\n"
        var normalizedFields = record.fields
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
        for (key, val) in normalizedFields {
            let cleanVal = val.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanVal.isEmpty else { continue }
            // Filter non-standard internal fields
            if key.starts(with: "APP_YAAM_") { continue }
            if key == "COMMENT" {
                let sanitized = QSOMetadataFormatter.cleanComment(cleanVal)
                guard !sanitized.isEmpty else { continue }
                out += "<\(key):\(sanitized.utf8.count)>\(sanitized) "
                continue
            }
            out += "<\(key):\(cleanVal.utf8.count)>\(cleanVal) "
        }
        out += "<EOR>\n"
        return out
    }

    // MARK: - ARRL LoTW via TQSL CLI
    private func uploadToLoTWViaTQSL(
        record: QSORecordModel,
        stationID: String? = nil,
        stationLocation: String? = nil
    ) async -> (success: Bool, message: String) {
        var resolvedLocation = (stationLocation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedLocation.isEmpty {
            resolvedLocation = (UserDefaults.standard.string(forKey: "lotwStationLocation") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if resolvedLocation.isEmpty {
            if let db = try? LogbookDatabase(), let profiles = try? db.loadStationProfiles() {
                if let sid = stationID, let uuid = UUID(uuidString: sid),
                   let prof = profiles.first(where: { $0.id == uuid }),
                   !prof.lotwStationLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolvedLocation = prof.lotwStationLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let activeID = UserDefaults.standard.string(forKey: "activeStationProfileID").flatMap(UUID.init(uuidString:)),
                          let prof = profiles.first(where: { $0.id == activeID }),
                          !prof.lotwStationLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolvedLocation = prof.lotwStationLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let firstProf = profiles.first,
                          !firstProf.lotwStationLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolvedLocation = firstProf.lotwStationLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        let adifContent = buildSingleQSOADIF(record)
        return await TQSLCoordinator.shared.execute(
            adifContent: adifContent,
            stationLocation: resolvedLocation
        )
    }

    private func urlEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    private func extractQRZReason(from text: String) -> String {
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.starts(with: "REASON=") {
                return String(trimmed.dropFirst(7))
            }
        }
        return text.prefix(60).description
    }
}

// MARK: - Sleek Floating Toast HUD View

public struct ZeroClickCloudToastView: View {
    @ObservedObject var daemon = ZeroClickCloudUploadDaemon.shared

    public init() {}

    public var body: some View {
        if daemon.showToast && !daemon.lastUploadStatus.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: isOutboxNotification ? "tray.and.arrow.down.fill" : "icloud.and.arrow.up.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                Text(daemon.lastUploadStatus)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)

                if daemon.pendingQueueCount > 0 && daemon.isNetworkConnected && !daemon.isFlushingQueue {
                    Button {
                        daemon.flushNow()
                    } label: {
                        Text("Upload Now")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.28))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation { daemon.showToast = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isOutboxNotification
                          ? Color(red: 0.88, green: 0.48, blue: 0.08).opacity(0.95)
                          : Color(red: 0.12, green: 0.45, blue: 0.88).opacity(0.92))
                    .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: daemon.showToast)
        }
    }

    private var isOutboxNotification: Bool {
        daemon.lastUploadStatus.contains("Offline") || daemon.lastUploadStatus.contains("Outbox")
    }
}
