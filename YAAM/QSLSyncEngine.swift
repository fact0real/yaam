//
//  QSLSyncEngine.swift
//  YAAM
//
//  One-Click Parallel Multi-Service QSL Synchronization Engine
//  Coordinates background sync across LoTW, eQSL.cc, QRZ Logbook, and Club Log.
//  Streams real-time diagnostic logs and automatically fetches eQSL graphic card images.
//

import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - Diagnostic Entry

public enum QSLDiagnosticLevel: String, Sendable {
    case info = "INFO"
    case success = "SUCCESS"
    case warning = "WARNING"
    case error = "ERROR"

    public var color: Color {
        switch self {
        case .info: return .cyan
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    public var icon: String {
        switch self {
        case .info: return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

public struct QSLDiagnosticEntry: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: QSLDiagnosticLevel
    public let service: String
    public let message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: QSLDiagnosticLevel,
        service: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.service = service
        self.message = message
    }

    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

// MARK: - QSL Sync Engine

@MainActor
public final class QSLSyncEngine: ObservableObject {
    public static let shared = QSLSyncEngine()

    @Published public var isSyncing: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var currentStepText: String = "Ready to synchronize"
    @Published public var diagnosticLogs: [QSLDiagnosticEntry] = []
    @Published public var lastSyncCompletedAt: Date? = nil

    // Stats
    @Published public var totalFetchedCount: Int = 0
    @Published public var totalUpdatedCount: Int = 0
    @Published public var downloadedCardCount: Int = 0

    public init() {
        appendLog(level: .info, service: "System", message: "QSL Sync Engine initialized. Multi-service parallel runner ready.")
    }

    public func appendLog(level: QSLDiagnosticLevel, service: String, message: String) {
        let entry = QSLDiagnosticEntry(level: level, service: service, message: message)
        diagnosticLogs.insert(entry, at: 0)
        // Keep maximum 200 logs
        if diagnosticLogs.count > 200 {
            diagnosticLogs.removeLast(diagnosticLogs.count - 200)
        }
    }

    public func clearLogs() {
        diagnosticLogs.removeAll()
    }

    // MARK: - One-Click Sync All Services

    func syncAllServices(appState: AppState) async {
        guard !isSyncing else { return }

        isSyncing = true
        progress = 0.05
        currentStepText = "Starting One-Click Multi-Service Synchronization..."
        totalFetchedCount = 0
        totalUpdatedCount = 0

        appendLog(level: .info, service: "Sync Manager", message: "🚀 Initiating parallel sync across LoTW, eQSL.cc, QRZ, and Club Log...")

        // Parallel tasks using TaskGroup
        await withTaskGroup(of: Void.self) { group in
            // Task 1: eQSL.cc Inbox & Card Download
            group.addTask { @MainActor in
                await self.syncEQSL(appState: appState)
            }

            // Task 2: LoTW & QRZ Logbook
            group.addTask { @MainActor in
                await self.syncLoTWAndQRZ(appState: appState)
            }

            // Task 3: Club Log LoTW State
            group.addTask { @MainActor in
                await self.syncClubLog(appState: appState)
            }
        }

        progress = 1.0
        isSyncing = false
        lastSyncCompletedAt = Date()
        currentStepText = "Sync Complete: \(totalUpdatedCount) confirmed QSO(s) updated."
        appendLog(level: .success, service: "Sync Manager", message: "🎉 All services synchronized successfully! \(totalUpdatedCount) QSOs updated.")

        appState.refreshAwardProgress()
        appState.playActivitySound(.success)
    }

    // MARK: - Service 1: eQSL.cc Sync & Graphic Card Ingestion

    private func syncEQSL(appState: AppState) async {
        appendLog(level: .info, service: "eQSL.cc", message: "Connecting to eQSL.cc Inbox API...")

        let creds = appState.qslServiceCredentials(for: [.eqsl])
        guard !creds.eqslUsername.isEmpty, !creds.eqslPassword.isEmpty else {
            appendLog(level: .warning, service: "eQSL.cc", message: "⚠️ eQSL username or password not configured in Settings. Skipping.")
            return
        }

        do {
            let lastSync = UserDefaults.standard.object(forKey: "eqslLastInboxSync") as? Date
            let incoming = try await appState.qslHubClient.downloadEQSLConfirmations(
                credentials: creds,
                since: lastSync
            )

            appendLog(level: .info, service: "eQSL.cc", message: "Downloaded \(incoming.count) inbox confirmations from eQSL.cc")

            var updated = 0
            for fields in incoming {
                guard let index = appState.qslConfirmationMatchIndex(fields) else { continue }
                appState.qsoRecords[index].fields = ImportReviewAnalyzer.mergeUpdate(incoming: fields, into: appState.qsoRecords[index].fields)
                appState.qsoRecords[index].fields["EQSL_QSL_RCVD"] = "Y"
                updated += 1

                // Download Card Graphic if not cached yet
                let call = appState.qsoRecords[index]["CALL"]
                let date = appState.qsoRecords[index]["QSO_DATE"]
                let time = appState.qsoRecords[index]["TIME_ON"]
                let band = appState.qsoRecords[index]["BAND"]
                let mode = appState.qsoRecords[index]["MODE"]

                if !EQSLService.shared.hasCachedCard(callsign: call, date: date, band: band, mode: mode) {
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000) // Rate limit buffer
                        if let cardURL = try? await EQSLService.shared.downloadCardImage(
                            callsign: call,
                            date: date,
                            time: time,
                            band: band,
                            mode: mode,
                            username: creds.eqslUsername,
                            password: creds.eqslPassword
                        ) {
                            appState.qsoRecords[index].fields["QSL_MEDIA_PATH"] = cardURL.path
                            self.appendLog(level: .success, service: "eQSL.cc", message: "🖼️ Cached eQSL graphic card for \(call) [\(band)/\(mode)]")
                            self.downloadedCardCount += 1
                        }
                    }
                }
            }

            totalUpdatedCount += updated
            UserDefaults.standard.set(Date(), forKey: "eqslLastInboxSync")
            appendLog(level: .success, service: "eQSL.cc", message: "✅ eQSL sync finished: \(updated) record(s) merged into local log.")

        } catch let error as QSLHubError {
            appendLog(level: .error, service: "eQSL.cc", message: "❌ eQSL API Error: \(error.localizedDescription)")
        } catch {
            appendLog(level: .error, service: "eQSL.cc", message: "❌ Connection error: \(error.localizedDescription)")
        }
    }

    // MARK: - Service 2: LoTW & QRZ Logbook Sync

    private func syncLoTWAndQRZ(appState: AppState) async {
        appendLog(level: .info, service: "LoTW / QRZ", message: "Querying ARRL LoTW and QRZ Logbook...")

        await withCheckedContinuation { continuation in
            appState.syncConfirmations(sources: [.lotw, .qrz], showCompletionAlert: false) { [weak self] summary in
                guard let self else {
                    continuation.resume()
                    return
                }

                self.totalFetchedCount += summary.fetched
                self.totalUpdatedCount += summary.changed

                if summary.changed > 0 {
                    self.appendLog(level: .success, service: "LoTW / QRZ", message: "✅ Confirmed \(summary.changed) QSO(s) out of \(summary.fetched) checked.")
                } else {
                    self.appendLog(level: .info, service: "LoTW / QRZ", message: "No new confirmations found (\(summary.fetched) checked).")
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Service 3: Club Log LoTW State

    private func syncClubLog(appState: AppState) async {
        appendLog(level: .info, service: "Club Log", message: "Fetching Club Log LoTW verification status...")

        let creds = appState.qslServiceCredentials(for: [.clubLog])
        guard !creds.clubLogEmail.isEmpty, !creds.clubLogPassword.isEmpty, !creds.clubLogAPIKey.isEmpty else {
            appendLog(level: .warning, service: "Club Log", message: "⚠️ Club Log API key or application password missing. Skipping.")
            return
        }

        do {
            let matches = try await appState.qslHubClient.downloadClubLogLoTWState(
                credentials: creds,
                earliestQSODate: nil
            )

            var updated = 0
            for record in matches {
                guard let index = appState.qslConfirmationMatchIndex(record) else { continue }
                if record["LOTW_QSL_RCVD"] == "Y" {
                    appState.qsoRecords[index].fields["CLUBLOG_LOTW_RCVD"] = "Y"
                    updated += 1
                }
            }

            appendLog(level: .success, service: "Club Log", message: "✅ Club Log LoTW state updated: \(updated) match(es) verified.")
        } catch {
            appendLog(level: .error, service: "Club Log", message: "❌ Club Log error: \(error.localizedDescription)")
        }
    }
}
