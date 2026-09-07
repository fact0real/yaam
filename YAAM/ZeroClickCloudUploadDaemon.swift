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
    @AppStorage("autoCommitWSJTX") public var autoCommitWSJTX: Bool = true

    // Real-Time Live Status
    @Published public var lastUploadStatus: String = ""
    @Published public var lastUploadLatencyMs: Int = 0
    @Published public var showToast: Bool = false
    @Published public var isUploading: Bool = false
    @Published public var pendingQueueCount: Int = 0
    @Published public var recentUploadLogs: [CloudUploadLogItem] = []

    // Offline buffer
    private var offlineQueue: [QSORecordModel] = []
    private var toastDismissTask: Task<Void, Never>?

    private init() {}

    // MARK: - Main Dispatch Entry Point
    func dispatch(record: QSORecordModel, stationID: String? = nil, qrzKeyOverride: String? = nil) {
        guard isEnabled else { return }

        let call = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !call.isEmpty else { return }

        Task { [weak self] in
            guard let self = self else { return }
            await self.executeUpload(record: record, stationID: stationID, qrzKeyOverride: qrzKeyOverride)
        }
    }

    // MARK: - Upload Worker
    private func executeUpload(record: QSORecordModel, stationID: String?, qrzKeyOverride: String?) async {
        let startTime = Date()
        isUploading = true
        defer { isUploading = false }

        var successfulServices: [String] = []
        var errors: [String] = []

        // 1. QRZ Logbook (ACTION=INSERT)
        if uploadToQRZ {
            let qrzOutcome = await uploadToQRZLogbook(record: record, stationID: stationID, keyOverride: qrzKeyOverride)
            if qrzOutcome.success {
                successfulServices.append("QRZ")
            } else if !qrzOutcome.message.isEmpty {
                errors.append("QRZ: \(qrzOutcome.message)")
            }
        }

        // 2. Club Log (realtime.php)
        if uploadToClubLog {
            let clubLogOutcome = await uploadToClubLogRealTime(record: record)
            if clubLogOutcome.success {
                successfulServices.append("Club Log")
            } else if !clubLogOutcome.message.isEmpty {
                errors.append("ClubLog: \(clubLogOutcome.message)")
            }
        }

        // 3. eQSL.cc
        if uploadToEQSL {
            let eqslOutcome = await uploadToEQSLRealTime(record: record)
            if eqslOutcome.success {
                successfulServices.append("eQSL")
            }
        }

        // 4. Wavelog / Cloudlog
        if uploadToWavelog {
            WavelogSyncEngine.shared.autoPushSingleQSO(record: record)
            successfulServices.append("Wavelog")
        }

        let latency = Int(Date().timeIntervalSince(startTime) * 1000)
        self.lastUploadLatencyMs = latency

        let call = record["CALL"]
        let band = record["BAND"]
        let mode = record["MODE"]

        if !successfulServices.isEmpty {
            let serviceList = successfulServices.joined(separator: " & ")
            let statusText = "☁️ Instant Upload: \(call) (\(band)/\(mode)) → \(serviceList) [\(latency)ms]"
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
        } else if !errors.isEmpty {
            let logItem = CloudUploadLogItem(
                callsign: call,
                band: band,
                mode: mode,
                services: [],
                timestamp: Date(),
                latencyMs: latency,
                success: false,
                message: errors.joined(separator: "; ")
            )
            appendRecentLog(logItem)
        }
    }

    private func triggerToast() {
        showToast = true
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
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
    private func uploadToQRZLogbook(record: QSORecordModel, stationID: String?, keyOverride: String?) async -> (success: Bool, message: String) {
        // Find QRZ API Key from override, vault, or preferences
        var apiKey = (keyOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKey.isEmpty, let sid = stationID, !sid.isEmpty {
            apiKey = KeychainStore.string(for: "qrz_api_key_\(sid)")
        }
        if apiKey.isEmpty {
            apiKey = CredentialVault.value(for: .qrzPassword).trimmingCharacters(in: .whitespacesAndNewlines)
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
        for (key, val) in record.fields {
            let cleanVal = val.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanVal.isEmpty else { continue }
            // Filter non-standard internal fields
            if key.starts(with: "APP_YAAM_") { continue }
            out += "<\(key):\(cleanVal.utf8.count)>\(cleanVal) "
        }
        out += "<EOR>\n"
        return out
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
                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                Text(daemon.lastUploadStatus)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)

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
                    .fill(Color(red: 0.12, green: 0.45, blue: 0.88).opacity(0.92))
                    .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: daemon.showToast)
        }
    }
}
